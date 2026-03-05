import Foundation

@MainActor
final class MeetingAnalyticsViewModel: ObservableObject {
    @Published var metrics: ConversationMetrics = .empty
    @Published var isComputed = false

    private let meeting: Meeting

    init(meeting: Meeting) {
        self.meeting = meeting
    }

    func computeMetrics() {
        guard !meeting.segments.isEmpty else { return }

        metrics = ConversationAnalyticsEngine.analyze(
            segments: meeting.segments,
            meetingDuration: meeting.duration
        )
        isComputed = true
    }
}
