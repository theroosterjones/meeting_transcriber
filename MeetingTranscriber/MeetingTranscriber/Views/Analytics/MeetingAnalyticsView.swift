import SwiftUI

struct MeetingAnalyticsView: View {
    @StateObject private var viewModel: MeetingAnalyticsViewModel

    init(meeting: Meeting) {
        _viewModel = StateObject(wrappedValue: MeetingAnalyticsViewModel(meeting: meeting))
    }

    var body: some View {
        Group {
            if viewModel.isComputed {
                analyticsContent
            } else {
                ProgressView("Computing metrics...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            viewModel.computeMetrics()
        }
    }

    private var analyticsContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                MeetingOverviewPanel(metrics: viewModel.metrics)
                TalkTimeBarChart(speakers: viewModel.metrics.speakersByTalkTime)
                SpeakerParticipationList(speakers: viewModel.metrics.speakersByTalkTime)

                if !viewModel.metrics.silenceGaps.isEmpty {
                    SilenceGapsPanel(gaps: viewModel.metrics.silenceGaps)
                }
            }
            .padding()
        }
    }
}

// MARK: - Meeting Overview Panel

struct MeetingOverviewPanel: View {
    let metrics: ConversationMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Meeting Overview", systemImage: "chart.bar.xaxis")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetricCard(
                    title: "Duration",
                    value: metrics.formattedDuration,
                    icon: "clock",
                    color: .blue
                )
                MetricCard(
                    title: "Speakers",
                    value: "\(metrics.totalSpeakers)",
                    icon: "person.2",
                    color: .green
                )
                MetricCard(
                    title: "Speaker Turns",
                    value: "\(metrics.speakerSwitches)",
                    icon: "arrow.left.arrow.right",
                    color: .orange
                )
                MetricCard(
                    title: "Silence Gaps",
                    value: "\(metrics.silenceGapCount)",
                    icon: "pause.circle",
                    color: metrics.silenceGapCount > 0 ? .yellow : .gray
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }
}

// MARK: - Talk Time Bar Chart

struct TalkTimeBarChart: View {
    let speakers: [SpeakerMetrics]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Talk Time Distribution", systemImage: "chart.bar.fill")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(speakers) { speaker in
                    TalkTimeBar(speaker: speaker, maxPercentage: speakers.first?.talkPercentage ?? 100)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct TalkTimeBar: View {
    let speaker: SpeakerMetrics
    let maxPercentage: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SpeakerBadge(label: speaker.speakerId)

                Spacer()

                Text(speaker.formattedTalkTime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()

                Text("(\(Int(speaker.talkPercentage))%)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                let barWidth = max(4, geometry.size.width * CGFloat(speaker.talkPercentage / max(maxPercentage, 1)))

                RoundedRectangle(cornerRadius: 4)
                    .fill(SpeakerBadge.colorForSpeaker(speaker.speakerId).gradient)
                    .frame(width: barWidth, height: 8)
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Speaker Participation List

struct SpeakerParticipationList: View {
    let speakers: [SpeakerMetrics]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Speaker Details", systemImage: "person.crop.rectangle.stack")
                .font(.headline)

            ForEach(speakers) { speaker in
                SpeakerDetailRow(speaker: speaker)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct SpeakerDetailRow: View {
    let speaker: SpeakerMetrics

    var body: some View {
        HStack(alignment: .top) {
            Circle()
                .fill(SpeakerBadge.colorForSpeaker(speaker.speakerId))
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(speaker.speakerId)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(spacing: 16) {
                    DetailChip(label: "Talk Time", value: speaker.formattedTalkTime)
                    DetailChip(label: "Turns", value: "\(speaker.speakingTurns)")
                    DetailChip(label: "Longest", value: speaker.formattedLongestMonologue)
                }
            }

            Spacer()

            Text("\(Int(speaker.talkPercentage))%")
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(SpeakerBadge.colorForSpeaker(speaker.speakerId))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }
}

struct DetailChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}

// MARK: - Silence Gaps Panel

struct SilenceGapsPanel: View {
    let gaps: [SilenceGap]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Silence Gaps (> 3s)", systemImage: "pause.circle")
                .font(.headline)

            ForEach(gaps) { gap in
                HStack {
                    Text("at \(gap.formattedTimestamp)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer()

                    Text(SpeakerMetrics.formatDuration(gap.duration))
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}
