import Foundation

struct SpeakerMetrics: Identifiable, Equatable {
    var id: String { speakerId }
    let speakerId: String
    let totalTalkTime: TimeInterval
    let talkPercentage: Double
    let speakingTurns: Int
    let longestMonologue: TimeInterval

    var formattedTalkTime: String {
        Self.formatDuration(totalTalkTime)
    }

    var formattedLongestMonologue: String {
        Self.formatDuration(longestMonologue)
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

struct SilenceGap: Identifiable, Equatable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval

    var duration: TimeInterval { endTime - startTime }

    var formattedTimestamp: String {
        let min = Int(startTime) / 60
        let sec = Int(startTime) % 60
        return String(format: "%02d:%02d", min, sec)
    }
}

struct ConversationMetrics: Equatable {
    let meetingDuration: TimeInterval
    let totalSpeakers: Int
    let speakerSwitches: Int
    let silenceGaps: [SilenceGap]
    let speakers: [SpeakerMetrics]

    var silenceGapCount: Int { silenceGaps.count }

    var totalSilenceTime: TimeInterval {
        silenceGaps.reduce(0) { $0 + $1.duration }
    }

    var formattedDuration: String {
        let hours = Int(meetingDuration) / 3600
        let minutes = (Int(meetingDuration) % 3600) / 60
        let seconds = Int(meetingDuration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Speakers sorted by talk time descending.
    var speakersByTalkTime: [SpeakerMetrics] {
        speakers.sorted { $0.totalTalkTime > $1.totalTalkTime }
    }

    static let empty = ConversationMetrics(
        meetingDuration: 0,
        totalSpeakers: 0,
        speakerSwitches: 0,
        silenceGaps: [],
        speakers: []
    )
}
