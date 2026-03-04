import Foundation

struct TranscriptSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let timestamp: TimeInterval
    let speakerLabel: String
    let confidence: Float

    init(
        id: UUID = UUID(),
        text: String,
        timestamp: TimeInterval,
        speakerLabel: String = "Speaker 1",
        confidence: Float = 1.0
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.speakerLabel = speakerLabel
        self.confidence = confidence
    }

    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
