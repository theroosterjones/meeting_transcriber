import AVFoundation
import Accelerate
import Combine

protocol AudioCaptureManagerProtocol: AnyObject {
    var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> { get }
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }
    var isRecording: Bool { get }
    func startCapture(recordingOutputURL: URL?) async throws
    func stopCapture()
}

final class AudioCaptureManager: AudioCaptureManagerProtocol {
    private let audioEngine = AVAudioEngine()
    private let audioBufferSubject = PassthroughSubject<AVAudioPCMBuffer, Never>()
    private let audioLevelSubject = PassthroughSubject<Float, Never>()
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var recordingFile: AVAudioFile?

    private(set) var isRecording = false

    static let sampleRate: Double = 16_000
    static let bufferSize: AVAudioFrameCount = 1024

    var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> {
        audioBufferSubject.eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    func startCapture(recordingOutputURL: URL? = nil) async throws {
        try await requestMicrophonePermission()
        try configureAudioSession()
        try installTapAndStart(recordingOutputURL: recordingOutputURL)
        registerForInterruptions()
        isRecording = true
    }

    func stopCapture() {
        guard isRecording else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recordingFile = nil
        teardownInterruptionObserver()
        teardownRouteChangeObserver()
        deactivateAudioSession()
        isRecording = false
    }

    deinit {
        stopCapture()
    }

    // MARK: - Private

    private func requestMicrophonePermission() async throws {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { throw AppError.microphonePermissionDenied }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            // Use .videoRecording to reduce aggressive voice-processing suppression and improve
            // far-field capture (e.g. nearby laptop/phone speakers in hybrid meetings).
            try session.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
            )
            try session.setPreferredSampleRate(Self.sampleRate)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setPreferredInputNumberOfChannels(1)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw AppError.audioSessionSetupFailed(error)
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func installTapAndStart(recordingOutputURL: URL?) throws {
        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AppError.recordingFailed(
                NSError(domain: "AudioCaptureManager", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Cannot create desired audio format"])
            )
        }

        let converter = AVAudioConverter(from: hardwareFormat, to: desiredFormat)
        let writeFormat = converter?.outputFormat ?? hardwareFormat

        if let recordingOutputURL {
            do {
                recordingFile = try AVAudioFile(
                    forWriting: recordingOutputURL,
                    settings: writeFormat.settings,
                    commonFormat: writeFormat.commonFormat,
                    interleaved: writeFormat.isInterleaved
                )
            } catch {
                throw AppError.fileWriteFailed(error)
            }
        } else {
            recordingFile = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: Self.bufferSize, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self else { return }

            if let converter {
                let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: desiredFormat,
                    frameCapacity: AVAudioFrameCount(
                        Double(buffer.frameLength) * Self.sampleRate / hardwareFormat.sampleRate
                    )
                )!

                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if status == .haveData {
                    self.audioBufferSubject.send(convertedBuffer)
                    self.publishAudioLevel(from: convertedBuffer)
                    try? self.recordingFile?.write(from: convertedBuffer)
                }
            } else {
                self.audioBufferSubject.send(buffer)
                self.publishAudioLevel(from: buffer)
                try? self.recordingFile?.write(from: buffer)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw AppError.recordingFailed(error)
        }
    }

    private func publishAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        var rms: Float = 0
        vDSP_measqv(channelData, 1, &rms, vDSP_Length(count))
        let db = 10 * log10f(max(rms, 1e-12))
        let normalizedLevel = max(0, min(1, (db + 60) / 60))
        audioLevelSubject.send(normalizedLevel)
    }

    private func registerForInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
    }

    private func teardownInterruptionObserver() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    private func teardownRouteChangeObserver() {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            if audioEngine.isRunning {
                audioEngine.pause()
            }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                try? audioEngine.start()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard isRecording else { return }
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange, .override:
            // Keep long recordings resilient if route/device changes mid-session.
            if !audioEngine.isRunning {
                audioEngine.prepare()
                try? audioEngine.start()
            }
        default:
            break
        }
    }
}
