import SwiftUI

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let showTimestamp: Bool
    let isLatest: Bool

    init(segment: TranscriptSegment, showTimestamp: Bool = true, isLatest: Bool = false) {
        self.segment = segment
        self.showTimestamp = showTimestamp
        self.isLatest = isLatest
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showTimestamp {
                Text(segment.formattedTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                SpeakerBadge(label: segment.speakerLabel)

                Text(segment.text)
                    .font(.body)
                    .foregroundStyle(.primary.opacity(isLatest ? 1.0 : 0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(speakerAccentColor)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
        }
    }

    private var speakerAccentColor: Color {
        SpeakerBadge.colorForSpeaker(segment.speakerLabel)
    }
}
