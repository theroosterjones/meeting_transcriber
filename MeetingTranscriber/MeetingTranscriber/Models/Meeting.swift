import Foundation

struct Meeting: Identifiable, Codable, Hashable {
    static func == (lhs: Meeting, rhs: Meeting) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id: UUID
    var title: String
    let createdAt: Date
    var duration: TimeInterval
    var segments: [TranscriptSegment]
    var summaryText: String?
    var isRecording: Bool

    var transcriptFileName: String {
        "transcript_\(id.uuidString).txt"
    }

    var summaryFileName: String {
        "summary_\(id.uuidString).txt"
    }

    var audioFileName: String {
        "audio_\(id.uuidString).caf"
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var fullTranscriptText: String {
        segments.map { segment in
            let timestamp = formatTimestamp(segment.timestamp)
            return "[\(timestamp)] \(segment.speakerLabel): \(segment.text)"
        }.joined(separator: "\n")
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        segments: [TranscriptSegment] = [],
        summaryText: String? = nil,
        isRecording: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.segments = segments
        self.summaryText = summaryText
        self.isRecording = isRecording
    }

    private func formatTimestamp(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
