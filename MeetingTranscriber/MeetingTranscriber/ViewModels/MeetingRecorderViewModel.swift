import Foundation
import Combine
import SwiftUI

@MainActor
final class MeetingRecorderViewModel: ObservableObject {
    // MARK: - Published State
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var liveSegments: [TranscriptSegment] = []
    @Published var currentPartialText = ""
    @Published var currentSpeaker = "Speaker 1"
    @Published var audioLevel: Float = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var error: AppError?
    @Published var showError = false

    // MARK: - Dependencies
    private let transcriptionEngine: TranscriptionEngineProtocol
    private let storageManager: FileStorageManagerProtocol
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?
    private var recordingStartDate = Date()

    init(
        transcriptionEngine: TranscriptionEngineProtocol? = nil,
        storageManager: FileStorageManagerProtocol = FileStorageManager()
    ) {
        self.transcriptionEngine = transcriptionEngine ?? TranscriptionEngine()
        self.storageManager = storageManager
    }

    // MARK: - Actions

    func startRecording() {
        Task {
            do {
                liveSegments.removeAll()
                currentPartialText = ""
                recordingStartDate = Date()

                bindEngine()
                try await transcriptionEngine.start()

                isRecording = true
                isPaused = false
                startTimer()
            } catch let appError as AppError {
                self.error = appError
                showError = true
            } catch {
                self.error = .recordingFailed(error)
                showError = true
            }
        }
    }

    func stopRecording() -> Meeting? {
        guard isRecording else { return nil }

        let segments = transcriptionEngine.stop()
        isRecording = false
        isPaused = false
        stopTimer()
        cancellables.removeAll()

        let meeting = Meeting(
            title: generateTitle(),
            createdAt: recordingStartDate,
            duration: elapsedTime,
            segments: segments.isEmpty ? liveSegments : segments,
            isRecording: false
        )

        do {
            try storageManager.saveMeeting(meeting)
            try storageManager.saveTranscript(meeting.fullTranscriptText, for: meeting)
        } catch let appError as AppError {
            self.error = appError
            showError = true
        } catch {
            self.error = .fileWriteFailed(error)
            showError = true
        }

        liveSegments.removeAll()
        currentPartialText = ""
        elapsedTime = 0

        return meeting
    }

    // MARK: - Private

    private func bindEngine() {
        transcriptionEngine.segmentPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] segment in
                self?.liveSegments.append(segment)
                self?.currentPartialText = ""
            }
            .store(in: &cancellables)

        if let engine = transcriptionEngine as? TranscriptionEngine {
            if let audioMgr = Mirror(reflecting: engine).children
                .first(where: { $0.label == "audioManager" })?.value as? AudioCaptureManagerProtocol {
                audioMgr.audioLevelPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] level in
                        self?.audioLevel = level
                    }
                    .store(in: &cancellables)
            }

            if let diarizationMgr = Mirror(reflecting: engine).children
                .first(where: { $0.label == "diarizationManager" })?.value as? SpeakerDiarizationManagerProtocol {
                diarizationMgr.currentSpeakerPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] speaker in
                        self?.currentSpeaker = speaker
                    }
                    .store(in: &cancellables)
            }
        }
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isRecording else { return }
                self.elapsedTime = Date().timeIntervalSince(self.recordingStartDate)
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func generateTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return "Meeting — \(formatter.string(from: recordingStartDate))"
    }

    var formattedElapsedTime: String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
