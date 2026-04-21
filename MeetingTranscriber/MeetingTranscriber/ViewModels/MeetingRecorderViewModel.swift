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
    @Published var recordingQualityMessage: String?
    @Published var elapsedTime: TimeInterval = 0
    @Published var autoStoppedMeeting: Meeting?
    @Published var error: AppError?
    @Published var showError = false

    // MARK: - Dependencies
    private let transcriptionEngine: TranscriptionEngineProtocol
    private let storageManager: FileStorageManagerProtocol
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?
    private var recordingStartDate = Date()
    private var activeMeetingID: UUID?
    private let maximumRecordingDuration: TimeInterval = 60 * 60
    private let checkpointSegmentInterval = 20
    private let lowAudioThreshold: Float = 0.07
    private let lowConfidenceThreshold: Float = 0.45
    private let qualityWindowSize = 30
    private var recentAudioLevels: [Float] = []
    private var recentSegmentConfidences: [Float] = []

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
                autoStoppedMeeting = nil
                liveSegments.removeAll()
                currentPartialText = ""
                currentSpeaker = "Speaker 1"
                audioLevel = 0
                recordingQualityMessage = nil
                recentAudioLevels.removeAll()
                recentSegmentConfidences.removeAll()
                recordingStartDate = Date()
                let meetingID = UUID()
                activeMeetingID = meetingID

                try storageManager.prepareMeetingDirectory(for: meetingID)
                let recordingURL = storageManager.audioRecordingURL(for: meetingID)

                cancellables.removeAll()
                bindEngine()
                try await transcriptionEngine.start(recordingOutputURL: recordingURL)

                isRecording = true
                isPaused = false
                startTimer()
            } catch let appError as AppError {
                self.error = appError
                showError = true
                activeMeetingID = nil
                cancellables.removeAll()
            } catch {
                self.error = .recordingFailed(error)
                showError = true
                activeMeetingID = nil
                cancellables.removeAll()
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
            id: activeMeetingID ?? UUID(),
            title: generateTitle(),
            createdAt: recordingStartDate,
            duration: elapsedTime,
            segments: segments.isEmpty ? liveSegments : segments,
            isRecording: false
        )

        do {
            try storageManager.saveMeeting(meeting)
            try storageManager.saveTranscript(meeting.fullTranscriptText, for: meeting)
            try storageManager.saveTranscriptSegments(meeting.segments, for: meeting.id)
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
        activeMeetingID = nil

        return meeting
    }

    // MARK: - Private

    private func bindEngine() {
        transcriptionEngine.segmentPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] segment in
                guard let self else { return }
                self.liveSegments.append(segment)
                self.currentPartialText = ""
                self.recordRecentConfidence(segment.confidence)
                self.evaluateRecordingQuality()
                self.persistCheckpointIfNeeded()
            }
            .store(in: &cancellables)

        transcriptionEngine.partialTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.currentPartialText = text
            }
            .store(in: &cancellables)

        transcriptionEngine.audioLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self else { return }
                self.audioLevel = level
                self.recordRecentAudioLevel(level)
                self.evaluateRecordingQuality()
            }
            .store(in: &cancellables)

        transcriptionEngine.currentSpeakerPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speaker in
                self?.currentSpeaker = speaker
            }
            .store(in: &cancellables)
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isRecording else { return }
                self.elapsedTime = Date().timeIntervalSince(self.recordingStartDate)
                if self.elapsedTime >= self.maximumRecordingDuration,
                   let meeting = self.stopRecording() {
                    self.autoStoppedMeeting = meeting
                }
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

    private func persistCheckpointIfNeeded() {
        guard let meetingID = activeMeetingID else { return }
        guard !liveSegments.isEmpty else { return }
        guard liveSegments.count.isMultiple(of: checkpointSegmentInterval) else { return }

        do {
            try storageManager.saveTranscriptSegments(liveSegments, for: meetingID)
        } catch let appError as AppError {
            error = appError
            showError = true
        } catch let unexpectedError {
            error = .fileWriteFailed(unexpectedError)
            showError = true
        }
    }

    private func recordRecentAudioLevel(_ level: Float) {
        recentAudioLevels.append(level)
        if recentAudioLevels.count > qualityWindowSize {
            recentAudioLevels.removeFirst(recentAudioLevels.count - qualityWindowSize)
        }
    }

    private func recordRecentConfidence(_ confidence: Float) {
        recentSegmentConfidences.append(confidence)
        if recentSegmentConfidences.count > qualityWindowSize {
            recentSegmentConfidences.removeFirst(recentSegmentConfidences.count - qualityWindowSize)
        }
    }

    private func evaluateRecordingQuality() {
        guard isRecording else {
            recordingQualityMessage = nil
            return
        }

        let lowAudioRatio = recentAudioLevels.isEmpty ? 0 :
            Float(recentAudioLevels.filter { $0 < lowAudioThreshold }.count) / Float(recentAudioLevels.count)
        let lowConfidenceRatio = recentSegmentConfidences.isEmpty ? 0 :
            Float(recentSegmentConfidences.filter { $0 < lowConfidenceThreshold }.count) / Float(recentSegmentConfidences.count)

        if elapsedTime > 10, lowAudioRatio > 0.75 {
            recordingQualityMessage = "Low input level. Move closer to speakers or increase meeting volume."
        } else if recentSegmentConfidences.count >= 5, lowConfidenceRatio > 0.5 {
            recordingQualityMessage = "Speech clarity is low. Reduce background noise or reposition the phone."
        } else {
            recordingQualityMessage = nil
        }
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
