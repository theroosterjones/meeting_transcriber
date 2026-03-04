import SwiftUI

struct RecordingView: View {
    @StateObject private var viewModel = MeetingRecorderViewModel()
    @EnvironmentObject private var historyViewModel: MeetingHistoryViewModel
    @State private var navigateToMeeting: Meeting?
    @State private var showStopConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isRecording {
                    liveTranscriptionView
                } else {
                    idleView
                }

                recordingControls
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "An unknown error occurred.")
            }
            .confirmationDialog("Stop Recording?", isPresented: $showStopConfirmation) {
                Button("Stop & Save", role: .destructive) {
                    stopAndSave()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will finalize the transcript and save the meeting.")
            }
            .navigationDestination(item: $navigateToMeeting) { meeting in
                MeetingDetailView(meeting: meeting)
            }
        }
    }

    // MARK: - Idle State

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue.opacity(0.3))

            VStack(spacing: 8) {
                Text("Ready to Record")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Tap the record button to start\ncapturing your meeting.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Live Transcription

    private var liveTranscriptionView: some View {
        VStack(spacing: 0) {
            recordingHeader

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(viewModel.liveSegments.enumerated()), id: \.element.id) { index, segment in
                            TranscriptSegmentRow(
                                segment: segment,
                                isLatest: index == viewModel.liveSegments.count - 1
                            )
                            .id(segment.id)
                        }

                        if !viewModel.currentPartialText.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Text("")
                                    .frame(width: 44)

                                Text(viewModel.currentPartialText)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }
                            .id("partial")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.liveSegments.count) { _, _ in
                    withAnimation {
                        if let lastSegment = viewModel.liveSegments.last {
                            proxy.scrollTo(lastSegment.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var recordingHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(pulsingOpacity)

                Text("Recording")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
            }

            Spacer()

            Text(viewModel.formattedElapsedTime)
                .font(.subheadline)
                .monospacedDigit()
                .fontWeight(.medium)

            Spacer()

            HStack(spacing: 8) {
                AudioLevelIndicator(level: viewModel.audioLevel)
                SpeakerBadge(label: viewModel.currentSpeaker)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @State private var pulsingOpacity: Double = 1.0

    // MARK: - Controls

    private var recordingControls: some View {
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 40) {
                if viewModel.isRecording {
                    Button {
                        showStopConfirmation = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.red.opacity(0.15))
                                .frame(width: 72, height: 72)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(.red)
                                .frame(width: 28, height: 28)
                        }
                    }
                } else {
                    Button {
                        viewModel.startRecording()
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(.red, lineWidth: 4)
                                .frame(width: 72, height: 72)

                            Circle()
                                .fill(.red)
                                .frame(width: 60, height: 60)
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulsingOpacity = 0.3
            }
        }
    }

    // MARK: - Actions

    private func stopAndSave() {
        if let meeting = viewModel.stopRecording() {
            historyViewModel.loadMeetings()
            navigateToMeeting = meeting
        }
    }
}
