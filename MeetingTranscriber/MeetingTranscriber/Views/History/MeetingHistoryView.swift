import SwiftUI

struct MeetingHistoryView: View {
    @EnvironmentObject private var viewModel: MeetingHistoryViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.meetings.isEmpty {
                    emptyState
                } else {
                    meetingList
                }
            }
            .navigationTitle("Meetings")
            .onAppear {
                viewModel.loadMeetings()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "An unknown error occurred.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("No Meetings Yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Record a meeting to see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var meetingList: some View {
        List {
            ForEach(viewModel.meetings) { meeting in
                NavigationLink(destination: MeetingDetailView(meeting: meeting)) {
                    MeetingRowView(meeting: meeting)
                }
            }
            .onDelete(perform: viewModel.deleteMeeting(at:))
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Meeting Row

struct MeetingRowView: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 12) {
                Label(meeting.formattedDuration, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(meeting.segments.count) segments", systemImage: "text.quote")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if meeting.summaryText != nil {
                    Label("Summary", systemImage: "doc.plaintext")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            Text(formattedDate)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: meeting.createdAt)
    }
}
