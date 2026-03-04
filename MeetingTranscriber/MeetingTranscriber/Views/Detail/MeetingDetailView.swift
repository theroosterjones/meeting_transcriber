import SwiftUI

struct MeetingDetailView: View {
    @StateObject private var viewModel: MeetingDetailViewModel
    @State private var selectedTab = 0

    init(meeting: Meeting) {
        _viewModel = StateObject(wrappedValue: MeetingDetailViewModel(meeting: meeting))
    }

    var body: some View {
        VStack(spacing: 0) {
            meetingHeader

            Picker("View", selection: $selectedTab) {
                Text("Transcript").tag(0)
                Text("Summary").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            TabView(selection: $selectedTab) {
                transcriptTab.tag(0)
                summaryTab.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle(viewModel.meeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        viewModel.shareTranscript()
                    } label: {
                        Label("Share Transcript", systemImage: "square.and.arrow.up")
                    }

                    if viewModel.hasSummary {
                        Button {
                            viewModel.shareSummary()
                        } label: {
                            Label("Share Summary", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            viewModel.loadContent()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.error?.localizedDescription ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let url = viewModel.shareURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    // MARK: - Header

    private var meetingHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Label(viewModel.meeting.formattedDuration, systemImage: "clock")
                    .font(.subheadline)

                Spacer()

                Text(formattedDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("\(viewModel.meeting.segments.count) segments", systemImage: "text.quote")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                let speakerCount = Set(viewModel.meeting.segments.map(\.speakerLabel)).count
                Label("\(speakerCount) speaker\(speakerCount == 1 ? "" : "s")", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Transcript Tab

    private var transcriptTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.meeting.segments) { segment in
                    TranscriptSegmentRow(segment: segment)
                }
            }
            .padding()
        }
    }

    // MARK: - Summary Tab

    private var summaryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.hasSummary {
                    Text(viewModel.summaryText)
                        .font(.body)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                } else {
                    summaryGenerationCard
                }
            }
            .padding()
        }
    }

    private var summaryGenerationCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.blue.gradient)

            Text("Generate a Summary")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Use AI to create a concise summary\nof this meeting transcript.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Picker("Summary Type", selection: $viewModel.selectedSummaryType) {
                ForEach(SummaryType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)

            Button {
                viewModel.generateSummary()
            } label: {
                Group {
                    if viewModel.isSummarizing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Generate Summary", systemImage: "sparkles")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canGenerateSummary)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: viewModel.meeting.createdAt)
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
