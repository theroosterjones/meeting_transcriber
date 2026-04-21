import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var apiConfig: APIConfiguration
    @State private var showAPIKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $apiConfig.summarizationModeRawValue) {
                        ForEach(SummarizationProcessingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Summarization Mode")
                } footer: {
                    Text("Local mode runs summarization on-device with no API costs. Cloud mode uses your own OpenAI-compatible API key.")
                }

                if apiConfig.summarizationMode == .cloud {
                    Section {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.orange)

                            if showAPIKey {
                                TextField("API Key", text: $apiConfig.apiKey)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("API Key", text: $apiConfig.apiKey)
                                    .textInputAutocapitalization(.never)
                            }

                            Button {
                                showAPIKey.toggle()
                            } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        TextField("Model", text: $apiConfig.model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("Base URL", text: $apiConfig.baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    } header: {
                        Text("OpenAI Configuration")
                    } footer: {
                        Text("Used only when Cloud mode is selected. Your API key is stored securely on device.")
                    }
                }

                Section("Status") {
                    HStack {
                        Text("Summary Engine Ready")
                        Spacer()
                        Image(systemName: apiConfig.isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(apiConfig.isConfigured ? .green : .red)
                    }
                }

                Section {
                    LabeledContent("Transcription", value: "On-device (Apple Speech)")
                    LabeledContent("Diarization", value: "On-device (Audio Analysis)")
                    LabeledContent("Summarization", value: apiConfig.summarizationMode == .local ? "On-device (Local algorithm)" : "Cloud (OpenAI-compatible)")
                } header: {
                    Text("Processing")
                } footer: {
                    Text("Transcription and speaker detection always run on device. Summarization can stay fully local or use cloud mode.")
                }

                Section {
                    LabeledContent("Healthy capture", value: "No warning banner")
                    LabeledContent("Low input level", value: "Move phone closer / raise speaker volume")
                    LabeledContent("Low speech clarity", value: "Reduce room noise / reposition phone")
                    LabeledContent("Segment confidence cue", value: "Orange 'Low confidence' label in transcript")
                } header: {
                    Text("Recording Health Guide")
                } footer: {
                    Text("These indicators appear while recording to help improve transcript quality in noisy or far-field meetings.")
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build", value: "1")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
