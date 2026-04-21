import Foundation
import SwiftUI

enum SummarizationProcessingMode: String, CaseIterable, Identifiable {
    case local
    case cloud

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local:
            return "Local (On-device)"
        case .cloud:
            return "Cloud (OpenAI-compatible)"
        }
    }
}

final class APIConfiguration: ObservableObject {
    @AppStorage("summarization_processing_mode") var summarizationModeRawValue: String = SummarizationProcessingMode.local.rawValue
    @AppStorage("openai_api_key") var apiKey: String = ""
    @AppStorage("openai_model") var model: String = "gpt-4o-mini"
    @AppStorage("openai_base_url") var baseURL: String = "https://api.openai.com/v1"

    var summarizationMode: SummarizationProcessingMode {
        get { SummarizationProcessingMode(rawValue: summarizationModeRawValue) ?? .local }
        set { summarizationModeRawValue = newValue.rawValue }
    }

    var isConfigured: Bool {
        switch summarizationMode {
        case .local:
            return true
        case .cloud:
            return !apiKey.isEmpty
        }
    }

    func createSummarizationService() -> SummarizationServiceProtocol {
        switch summarizationMode {
        case .local:
            return LocalSummarizationService()
        case .cloud:
            return OpenAISummarizationService(apiKey: apiKey, model: model, baseURL: baseURL)
        }
    }
}
