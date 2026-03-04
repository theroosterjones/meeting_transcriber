import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var apiConfig: APIConfiguration
    @State private var showAPIKey = false

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("Required for AI-powered meeting summarization. Your API key is stored securely on device.")
                }

                Section("Status") {
                    HStack {
                        Text("API Configured")
                        Spacer()
                        Image(systemName: apiConfig.isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(apiConfig.isConfigured ? .green : .red)
                    }
                }

                Section {
                    LabeledContent("Transcription", value: "On-device (Apple Speech)")
                    LabeledContent("Diarization", value: "On-device (Audio Analysis)")
                    LabeledContent("Summarization", value: "Cloud (OpenAI-compatible)")
                } header: {
                    Text("Processing")
                } footer: {
                    Text("Transcription and speaker detection run entirely on device. Only summarization requires a network connection.")
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
