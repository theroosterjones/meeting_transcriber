import Foundation
import Combine

@MainActor
final class MeetingHistoryViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var isLoading = false
    @Published var error: AppError?
    @Published var showError = false

    private let storageManager: FileStorageManagerProtocol

    init(storageManager: FileStorageManagerProtocol = FileStorageManager()) {
        self.storageManager = storageManager
    }

    func loadMeetings() {
        isLoading = true
        do {
            meetings = try storageManager.loadAllMeetings()
        } catch let appError as AppError {
            error = appError
            showError = true
        } catch {
            self.error = .fileReadFailed(error)
            showError = true
        }
        isLoading = false
    }

    func deleteMeeting(at offsets: IndexSet) {
        for index in offsets {
            let meeting = meetings[index]
            do {
                try storageManager.deleteMeeting(id: meeting.id)
            } catch {
                self.error = .fileWriteFailed(error)
                showError = true
            }
        }
        meetings.remove(atOffsets: offsets)
    }

    func deleteMeeting(_ meeting: Meeting) {
        do {
            try storageManager.deleteMeeting(id: meeting.id)
            meetings.removeAll { $0.id == meeting.id }
        } catch {
            self.error = .fileWriteFailed(error)
            showError = true
        }
    }
}
