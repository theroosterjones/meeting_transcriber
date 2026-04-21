import AVFoundation
import Combine

protocol TranscriptionEngineProtocol: AnyObject {
    var segmentPublisher: AnyPublisher<TranscriptSegment, Never> { get }
    var partialTextPublisher: AnyPublisher<String, Never> { get }
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }
    var currentSpeakerPublisher: AnyPublisher<String, Never> { get }
    var isRunning: Bool { get }
    func start(recordingOutputURL: URL?) async throws
    func stop() -> [TranscriptSegment]
}

/// Orchestrates AudioCapture → SpeechRecognition → SpeakerDiarization into a unified
/// stream of `TranscriptSegment`s. Each final recognition result is paired with the
/// current speaker label from the diarization engine.
final class TranscriptionEngine: TranscriptionEngineProtocol {
    private let audioManager: AudioCaptureManagerProtocol
    private let speechManager: SpeechRecognitionManagerProtocol
    private let diarizationManager: SpeakerDiarizationManagerProtocol

    private let segmentSubject = PassthroughSubject<TranscriptSegment, Never>()
    private let partialTextSubject = CurrentValueSubject<String, Never>("")
    private var cancellables = Set<AnyCancellable>()

    private var accumulatedSegments: [TranscriptSegment] = []
    private var currentSpeaker = "Speaker 1"
    private var pendingText = ""
    private var segmentStartTime: TimeInterval = 0
    private var recordingStartDate = Date()

    private(set) var isRunning = false

    var segmentPublisher: AnyPublisher<TranscriptSegment, Never> {
        segmentSubject.eraseToAnyPublisher()
    }

    var partialTextPublisher: AnyPublisher<String, Never> {
        partialTextSubject.eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioManager.audioLevelPublisher
    }

    var currentSpeakerPublisher: AnyPublisher<String, Never> {
        diarizationManager.currentSpeakerPublisher
    }

    init(
        audioManager: AudioCaptureManagerProtocol = AudioCaptureManager(),
        speechManager: SpeechRecognitionManagerProtocol = SpeechRecognitionManager(),
        diarizationManager: SpeakerDiarizationManagerProtocol = SpeakerDiarizationManager()
    ) {
        self.audioManager = audioManager
        self.speechManager = speechManager
        self.diarizationManager = diarizationManager
    }

    func start(recordingOutputURL: URL? = nil) async throws {
        guard !isRunning else { return }
        accumulatedSegments.removeAll()
        diarizationManager.reset()
        recordingStartDate = Date()
        currentSpeaker = "Speaker 1"
        pendingText = ""
        segmentStartTime = 0
        partialTextSubject.send("")

        try await audioManager.startCapture(recordingOutputURL: recordingOutputURL)
        try await speechManager.startRecognition()

        bindPipeline()
        isRunning = true
    }

    func stop() -> [TranscriptSegment] {
        guard isRunning else { return accumulatedSegments }

        flushPendingSegment()
        speechManager.stopRecognition()
        audioManager.stopCapture()
        cancellables.removeAll()
        isRunning = false

        return accumulatedSegments
    }

    // MARK: - Pipeline Binding

    private func bindPipeline() {
        audioManager.audioBufferPublisher
            .sink { [weak self] buffer in
                guard let self else { return }
                self.speechManager.feedAudioBuffer(buffer)
                let elapsed = Date().timeIntervalSince(self.recordingStartDate)
                self.diarizationManager.processAudioBuffer(buffer, at: elapsed)
            }
            .store(in: &cancellables)

        diarizationManager.currentSpeakerPublisher
            .removeDuplicates()
            .sink { [weak self] newSpeaker in
                guard let self else { return }
                if newSpeaker != self.currentSpeaker {
                    self.flushPendingSegment()
                    self.currentSpeaker = newSpeaker
                }
            }
            .store(in: &cancellables)

        speechManager.transcriptionPublisher
            .sink { [weak self] result in
                guard let self else { return }
                self.handleSpeechResult(result)
            }
            .store(in: &cancellables)
    }

    private func handleSpeechResult(_ result: SpeechResult) {
        let elapsed = Date().timeIntervalSince(recordingStartDate)

        if result.isFinal {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            let segment = TranscriptSegment(
                text: text,
                timestamp: segmentStartTime,
                speakerLabel: currentSpeaker,
                confidence: result.segments.last?.confidence ?? 1.0
            )
            accumulatedSegments.append(segment)
            segmentSubject.send(segment)
            pendingText = ""
            partialTextSubject.send("")
            segmentStartTime = elapsed
        } else {
            pendingText = result.text
            partialTextSubject.send(result.text)
        }
    }

    private func flushPendingSegment() {
        let text = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let segment = TranscriptSegment(
            text: text,
            timestamp: segmentStartTime,
            speakerLabel: currentSpeaker
        )
        accumulatedSegments.append(segment)
        segmentSubject.send(segment)

        pendingText = ""
        segmentStartTime = Date().timeIntervalSince(recordingStartDate)
    }
}
