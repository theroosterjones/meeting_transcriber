import Foundation
import Combine

@MainActor
final class MeetingDetailViewModel: ObservableObject {
    @Published var meeting: Meeting
    @Published var transcriptText = ""
    @Published var summaryText = ""
    @Published var isSummarizing = false
    @Published var selectedSummaryType: SummaryType = .keyPoints
    @Published var error: AppError?
    @Published var showError = false
    @Published var showShareSheet = false
    @Published var shareURL: URL?

    private let storageManager: FileStorageManagerProtocol
    private let apiConfiguration: APIConfiguration

    init(
        meeting: Meeting,
        storageManager: FileStorageManagerProtocol = FileStorageManager(),
        apiConfiguration: APIConfiguration = APIConfiguration()
    ) {
        self.meeting = meeting
        self.storageManager = storageManager
        self.apiConfiguration = apiConfiguration
    }

    func loadContent() {
        do {
            transcriptText = try storageManager.loadTranscript(for: meeting)
        } catch {
            transcriptText = meeting.fullTranscriptText
        }

        if meeting.summaryText != nil {
            do {
                summaryText = try storageManager.loadSummary(for: meeting)
            } catch {
                summaryText = meeting.summaryText ?? ""
            }
        }
    }

    func generateSummary() {
        guard !transcriptText.isEmpty else { return }

        isSummarizing = true

        Task {
            do {
                let service = apiConfiguration.createSummarizationService()
                let summary = try await service.summarize(
                    transcript: transcriptText,
                    type: selectedSummaryType
                )

                summaryText = summary
                meeting.summaryText = summary

                try storageManager.saveSummary(summary, for: meeting)
                try storageManager.saveMeeting(meeting)
            } catch let appError as AppError {
                error = appError
                showError = true
            } catch {
                self.error = .summarizationFailed(error)
                showError = true
            }
            isSummarizing = false
        }
    }

    func shareTranscript() {
        do {
            shareURL = try storageManager.exportTranscript(for: meeting)
            showShareSheet = true
        } catch {
            self.error = .fileNotFound(meeting.transcriptFileName)
            showError = true
        }
    }

    func shareSummary() {
        do {
            shareURL = try storageManager.exportSummary(for: meeting)
            showShareSheet = true
        } catch {
            self.error = .fileNotFound(meeting.summaryFileName)
            showError = true
        }
    }

    func shareMeetingReport() {
        do {
            let transcript = transcriptText.isEmpty ? (try storageManager.loadTranscript(for: meeting)) : transcriptText
            let summary = summaryText.isEmpty ? nil : summaryText
            shareURL = try storageManager.exportMeetingReport(for: meeting, transcript: transcript, summary: summary)
            showShareSheet = true
        } catch let appError as AppError {
            error = appError
            showError = true
        } catch {
            self.error = .fileWriteFailed(error)
            showError = true
        }
    }

    var hasSummary: Bool {
        !summaryText.isEmpty
    }

    var canGenerateSummary: Bool {
        !transcriptText.isEmpty && !isSummarizing
    }
}
