import Speech
import Combine

protocol SpeechRecognitionManagerProtocol: AnyObject {
    var transcriptionPublisher: AnyPublisher<SpeechResult, Never> { get }
    func startRecognition() async throws
    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func stopRecognition()
}

struct SpeechResult {
    let text: String
    let isFinal: Bool
    let timestamp: TimeInterval
    let segments: [SpeechResultSegment]
}

struct SpeechResultSegment {
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Float
}

final class SpeechRecognitionManager: SpeechRecognitionManagerProtocol {
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let transcriptionSubject = PassthroughSubject<SpeechResult, Never>()
    private let recordingStartTime = Date()

    private var restartTimer: Timer?
    private var lastProcessedText = ""

    // Apple caps on-device recognition at ~1 minute; we restart transparently.
    private static let recognitionRestartInterval: TimeInterval = 55

    var transcriptionPublisher: AnyPublisher<SpeechResult, Never> {
        transcriptionSubject.eraseToAnyPublisher()
    }

    func startRecognition() async throws {
        try await requestSpeechPermission()

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw AppError.speechRecognitionUnavailable
        }

        self.recognizer = recognizer
        recognizer.supportsOnDeviceRecognition = true

        try startRecognitionSession()
        scheduleRestart()
    }

    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func stopRecognition() {
        restartTimer?.invalidate()
        restartTimer = nil
        endRecognitionSession()
    }

    // MARK: - Private

    private func requestSpeechPermission() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized else {
            throw AppError.speechRecognitionPermissionDenied
        }
    }

    private func startRecognitionSession() throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer?.supportsOnDeviceRecognition ?? false
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        self.recognitionRequest = request

        guard let recognizer else {
            throw AppError.speechRecognitionUnavailable
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let elapsed = Date().timeIntervalSince(self.recordingStartTime)

                let segments = result.bestTranscription.segments.map { seg in
                    SpeechResultSegment(
                        text: seg.substring,
                        timestamp: seg.timestamp,
                        duration: seg.duration,
                        confidence: seg.confidence
                    )
                }

                let speechResult = SpeechResult(
                    text: result.bestTranscription.formattedString,
                    isFinal: result.isFinal,
                    timestamp: elapsed,
                    segments: segments
                )
                self.transcriptionSubject.send(speechResult)

                if result.isFinal {
                    self.lastProcessedText = result.bestTranscription.formattedString
                }
            }

            if error != nil {
                self.endRecognitionSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    try? self?.startRecognitionSession()
                }
            }
        }
    }

    private func endRecognitionSession() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func scheduleRestart() {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(
            withTimeInterval: Self.recognitionRestartInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            self.endRecognitionSession()
            try? self.startRecognitionSession()
        }
    }
}
