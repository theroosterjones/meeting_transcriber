import Foundation

/// Computes quantitative meeting metrics from an array of transcript segments.
///
/// Pipeline position:
///   Audio → Transcription → Diarization → TranscriptSegments → **ConversationAnalyticsEngine**
///
/// This engine is stateless and side-effect-free. It accepts segments and returns
/// a `ConversationMetrics` value. It does not modify any recording, transcription,
/// or diarization state.
struct ConversationAnalyticsEngine {

    private static let silenceGapThreshold: TimeInterval = 3.0

    /// Primary entry point. Computes all Phase 1 metrics from raw segments.
    static func analyze(segments: [TranscriptSegment], meetingDuration: TimeInterval) -> ConversationMetrics {
        guard !segments.isEmpty else { return .empty }

        let timedSegments = buildTimedSegments(from: segments, meetingDuration: meetingDuration)

        let duration = computeMeetingDuration(timedSegments: timedSegments, fallback: meetingDuration)
        let speakerMetrics = computeSpeakerMetrics(timedSegments: timedSegments, meetingDuration: duration)
        let switches = computeSpeakerSwitches(timedSegments: timedSegments)
        let gaps = detectSilenceGaps(timedSegments: timedSegments)

        return ConversationMetrics(
            meetingDuration: duration,
            totalSpeakers: speakerMetrics.count,
            speakerSwitches: switches,
            silenceGaps: gaps,
            speakers: speakerMetrics
        )
    }

    // MARK: - Timed Segment Construction

    /// The existing TranscriptSegment has a single `timestamp` (start time) but no end time.
    /// We derive end times: each segment ends when the next one begins, and the final
    /// segment ends at the meeting duration.
    private struct TimedSegment {
        let speakerId: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String

        var duration: TimeInterval { max(0, endTime - startTime) }
    }

    private static func buildTimedSegments(from segments: [TranscriptSegment], meetingDuration: TimeInterval) -> [TimedSegment] {
        let sorted = segments.sorted { $0.timestamp < $1.timestamp }
        var timed = [TimedSegment]()

        for i in 0..<sorted.count {
            let start = sorted[i].timestamp
            let end: TimeInterval
            if i + 1 < sorted.count {
                end = sorted[i + 1].timestamp
            } else {
                end = max(start, meetingDuration)
            }

            timed.append(TimedSegment(
                speakerId: sorted[i].speakerLabel,
                startTime: start,
                endTime: end,
                text: sorted[i].text
            ))
        }

        return timed
    }

    // MARK: - Meeting Duration

    private static func computeMeetingDuration(timedSegments: [TimedSegment], fallback: TimeInterval) -> TimeInterval {
        guard let first = timedSegments.first, let last = timedSegments.last else {
            return fallback
        }
        let computed = last.endTime - first.startTime
        return max(computed, fallback)
    }

    // MARK: - Speaker Metrics

    private static func computeSpeakerMetrics(timedSegments: [TimedSegment], meetingDuration: TimeInterval) -> [SpeakerMetrics] {
        let grouped = Dictionary(grouping: timedSegments, by: \.speakerId)
        let safeDuration = max(meetingDuration, 1)

        return grouped.map { speakerId, segments in
            let totalTalk = segments.reduce(0.0) { $0 + $1.duration }
            let percentage = (totalTalk / safeDuration) * 100.0
            let turns = segments.count
            let longest = computeLongestMonologue(segments: segments, allSegments: timedSegments)

            return SpeakerMetrics(
                speakerId: speakerId,
                totalTalkTime: totalTalk,
                talkPercentage: min(percentage, 100),
                speakingTurns: turns,
                longestMonologue: longest
            )
        }.sorted { $0.totalTalkTime > $1.totalTalkTime }
    }

    // MARK: - Longest Monologue

    /// Finds the longest consecutive run where the same speaker holds the floor.
    /// Adjacent segments by the same speaker are merged into a single monologue.
    private static func computeLongestMonologue(segments: [TimedSegment], allSegments: [TimedSegment]) -> TimeInterval {
        guard !allSegments.isEmpty else { return 0 }

        let speakerId = segments.first?.speakerId ?? ""
        var longest: TimeInterval = 0
        var currentStart: TimeInterval?
        var currentEnd: TimeInterval = 0

        for segment in allSegments {
            if segment.speakerId == speakerId {
                if currentStart == nil {
                    currentStart = segment.startTime
                }
                currentEnd = segment.endTime
            } else {
                if let start = currentStart {
                    longest = max(longest, currentEnd - start)
                    currentStart = nil
                }
            }
        }

        if let start = currentStart {
            longest = max(longest, currentEnd - start)
        }

        return longest
    }

    // MARK: - Speaker Switches

    private static func computeSpeakerSwitches(timedSegments: [TimedSegment]) -> Int {
        guard timedSegments.count > 1 else { return 0 }

        var switches = 0
        for i in 1..<timedSegments.count {
            if timedSegments[i].speakerId != timedSegments[i - 1].speakerId {
                switches += 1
            }
        }
        return switches
    }

    // MARK: - Silence Gaps

    private static func detectSilenceGaps(timedSegments: [TimedSegment]) -> [SilenceGap] {
        guard timedSegments.count > 1 else { return [] }

        var gaps = [SilenceGap]()
        for i in 1..<timedSegments.count {
            let gapStart = timedSegments[i - 1].endTime
            let gapEnd = timedSegments[i].startTime
            let gapDuration = gapEnd - gapStart

            if gapDuration > silenceGapThreshold {
                gaps.append(SilenceGap(startTime: gapStart, endTime: gapEnd))
            }
        }
        return gaps
    }
}
