import AVFoundation
import Accelerate
import Combine

protocol SpeakerDiarizationManagerProtocol: AnyObject {
    var currentSpeakerPublisher: AnyPublisher<String, Never> { get }
    var speakerProfiles: [SpeakerProfile] { get }
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, at timestamp: TimeInterval)
    func reset()
}

/// Energy-envelope + zero-crossing based speaker change detector.
///
/// This approach works entirely on-device with zero latency. It extracts a compact
/// feature vector from each audio chunk (spectral centroid, energy bands, ZCR, MFCC-like
/// features via DCT of log-mel energies) and clusters speakers using online cosine
/// similarity against running centroids.
///
/// For production-grade diarization with >4 speakers, swap this for a CoreML
/// speaker-embedding model (e.g., ECAPA-TDNN exported from SpeechBrain).
final class SpeakerDiarizationManager: SpeakerDiarizationManagerProtocol {
    private let currentSpeakerSubject = CurrentValueSubject<String, Never>("Speaker 1")
    private(set) var speakerProfiles: [SpeakerProfile] = []

    private let maxSpeakers: Int
    private let similarityThreshold: Float
    private let silenceThreshold: Float
    private let featureDimension = 26

    private var previousEnergy: Float = 0
    private var framesSinceLastChange = 0
    private let minFramesBetweenChanges = 15 // ~300ms at 50fps

    var currentSpeakerPublisher: AnyPublisher<String, Never> {
        currentSpeakerSubject.eraseToAnyPublisher()
    }

    init(maxSpeakers: Int = 8, similarityThreshold: Float = 0.82, silenceThreshold: Float = 0.005) {
        self.maxSpeakers = maxSpeakers
        self.similarityThreshold = similarityThreshold
        self.silenceThreshold = silenceThreshold
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, at timestamp: TimeInterval) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let energy = computeRMSEnergy(channelData, count: frameCount)
        guard energy > silenceThreshold else { return }

        let features = extractFeatures(channelData, count: frameCount, sampleRate: Float(buffer.format.sampleRate))
        let speaker = assignSpeaker(features: features)

        framesSinceLastChange += 1
        previousEnergy = energy

        if speaker != currentSpeakerSubject.value && framesSinceLastChange >= minFramesBetweenChanges {
            framesSinceLastChange = 0
            currentSpeakerSubject.send(speaker)
        }
    }

    func reset() {
        speakerProfiles.removeAll()
        previousEnergy = 0
        framesSinceLastChange = 0
        currentSpeakerSubject.send("Speaker 1")
    }

    // MARK: - Feature Extraction

    private func extractFeatures(_ data: UnsafePointer<Float>, count: Int, sampleRate: Float) -> [Float] {
        var features = [Float]()
        features.reserveCapacity(featureDimension)

        // 1. RMS Energy
        var rms: Float = 0
        vDSP_measqv(data, 1, &rms, vDSP_Length(count))
        features.append(sqrt(rms))

        // 2. Zero-crossing rate
        var zcr: Float = 0
        for i in 1..<count {
            if (data[i] >= 0) != (data[i - 1] >= 0) {
                zcr += 1
            }
        }
        zcr /= Float(count)
        features.append(zcr)

        // 3. Spectral centroid via FFT
        let fftSize = 512
        let halfFFT = fftSize / 2
        let log2n = vDSP_Length(log2f(Float(fftSize)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return Array(repeating: 0, count: featureDimension)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var windowedSignal = [Float](repeating: 0, count: fftSize)
        let copyCount = min(count, fftSize)
        for i in 0..<copyCount {
            windowedSignal[i] = data[i]
        }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(windowedSignal, 1, window, 1, &windowedSignal, 1, vDSP_Length(fftSize))

        var realPart = [Float](repeating: 0, count: halfFFT)
        var imagPart = [Float](repeating: 0, count: halfFFT)

        windowedSignal.withUnsafeBufferPointer { ptr in
            let baseAddr = ptr.baseAddress!
            for i in 0..<halfFFT {
                realPart[i] = baseAddr[2 * i]
                imagPart[i] = baseAddr[2 * i + 1]
            }
        }

        var magnitudes = [Float](repeating: 0, count: halfFFT)
        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfFFT))
            }
        }

        // Spectral centroid
        var weightedSum: Float = 0
        var magSum: Float = 0
        for i in 0..<halfFFT {
            weightedSum += Float(i) * magnitudes[i]
            magSum += magnitudes[i]
        }
        let centroid = magSum > 0 ? weightedSum / magSum : 0
        features.append(centroid / Float(halfFFT))

        // 4. Spectral rolloff (frequency below which 85% of energy lies)
        let rolloffThreshold: Float = 0.85
        var cumSum: Float = 0
        var rolloffBin = halfFFT - 1
        for i in 0..<halfFFT {
            cumSum += magnitudes[i]
            if cumSum >= rolloffThreshold * magSum {
                rolloffBin = i
                break
            }
        }
        features.append(Float(rolloffBin) / Float(halfFFT))

        // 5. Spectral flatness (geometric mean / arithmetic mean of spectrum)
        var logSum: Float = 0
        var arithmeticMean: Float = 0
        let eps: Float = 1e-10
        for i in 0..<halfFFT {
            logSum += logf(magnitudes[i] + eps)
            arithmeticMean += magnitudes[i]
        }
        arithmeticMean /= Float(halfFFT)
        let geometricMean = expf(logSum / Float(halfFFT))
        let flatness = arithmeticMean > eps ? geometricMean / arithmeticMean : 0
        features.append(flatness)

        // 6. Energy in sub-bands (8 bands)
        let bandsCount = 8
        let binsPerBand = halfFFT / bandsCount
        for band in 0..<bandsCount {
            let start = band * binsPerBand
            let end = min(start + binsPerBand, halfFFT)
            var bandEnergy: Float = 0
            for i in start..<end {
                bandEnergy += magnitudes[i] * magnitudes[i]
            }
            features.append(sqrtf(bandEnergy / Float(end - start)))
        }

        // 7. MFCC-like features via log-mel + DCT (13 coefficients)
        let melBands = 13
        let melEnergies = computeLogMelEnergies(magnitudes: magnitudes, numBands: melBands, sampleRate: sampleRate, fftSize: fftSize)

        var dctResult = [Float](repeating: 0, count: melBands)
        for k in 0..<melBands {
            var sum: Float = 0
            for n in 0..<melBands {
                sum += melEnergies[n] * cosf(Float.pi * Float(k) * (Float(n) + 0.5) / Float(melBands))
            }
            dctResult[k] = sum
        }

        features.append(contentsOf: dctResult.prefix(featureDimension - features.count))

        while features.count < featureDimension {
            features.append(0)
        }

        return Array(features.prefix(featureDimension))
    }

    private func computeLogMelEnergies(magnitudes: [Float], numBands: Int, sampleRate: Float, fftSize: Int) -> [Float] {
        let halfFFT = magnitudes.count
        let maxFreq = sampleRate / 2
        let melMax = 2595.0 * log10f(1.0 + maxFreq / 700.0)
        let melMin: Float = 0

        var melPoints = [Float](repeating: 0, count: numBands + 2)
        for i in 0..<(numBands + 2) {
            melPoints[i] = melMin + Float(i) * (melMax - melMin) / Float(numBands + 1)
        }

        let freqPoints = melPoints.map { mel -> Int in
            let freq = 700.0 * (powf(10.0, mel / 2595.0) - 1.0)
            return min(halfFFT - 1, max(0, Int(freq * Float(fftSize) / sampleRate)))
        }

        var melEnergies = [Float](repeating: 0, count: numBands)
        for m in 0..<numBands {
            let left = freqPoints[m]
            let center = freqPoints[m + 1]
            let right = freqPoints[m + 2]

            for k in left...right {
                guard k < halfFFT else { break }
                var weight: Float = 0
                if k <= center && center > left {
                    weight = Float(k - left) / Float(center - left)
                } else if k > center && right > center {
                    weight = Float(right - k) / Float(right - center)
                }
                melEnergies[m] += magnitudes[k] * magnitudes[k] * weight
            }
            melEnergies[m] = logf(melEnergies[m] + 1e-10)
        }

        return melEnergies
    }

    // MARK: - Speaker Assignment

    private func assignSpeaker(features: [Float]) -> String {
        if speakerProfiles.isEmpty {
            var profile = SpeakerProfile(
                label: "Speaker 1",
                color: SpeakerColor.allCases[0]
            )
            profile.updateCentroid(with: features)
            speakerProfiles.append(profile)
            return profile.label
        }

        var bestSimilarity: Float = -1
        var bestIndex = 0

        for (index, profile) in speakerProfiles.enumerated() {
            let similarity = profile.cosineSimilarity(to: features)
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestIndex = index
            }
        }

        if bestSimilarity >= similarityThreshold {
            speakerProfiles[bestIndex].updateCentroid(with: features)
            return speakerProfiles[bestIndex].label
        }

        if speakerProfiles.count < maxSpeakers {
            let newIndex = speakerProfiles.count
            let colorIndex = newIndex % SpeakerColor.allCases.count
            var profile = SpeakerProfile(
                label: "Speaker \(newIndex + 1)",
                color: SpeakerColor.allCases[colorIndex]
            )
            profile.updateCentroid(with: features)
            speakerProfiles.append(profile)
            return profile.label
        }

        speakerProfiles[bestIndex].updateCentroid(with: features)
        return speakerProfiles[bestIndex].label
    }

    // MARK: - Utility

    private func computeRMSEnergy(_ data: UnsafePointer<Float>, count: Int) -> Float {
        var rms: Float = 0
        vDSP_measqv(data, 1, &rms, vDSP_Length(count))
        return sqrtf(rms)
    }
}
