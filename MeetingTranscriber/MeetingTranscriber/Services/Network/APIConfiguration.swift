import Foundation
import SwiftUI

final class APIConfiguration: ObservableObject {
    @AppStorage("openai_api_key") var apiKey: String = ""
    @AppStorage("openai_model") var model: String = "gpt-4o-mini"
    @AppStorage("openai_base_url") var baseURL: String = "https://api.openai.com/v1"

    var isConfigured: Bool {
        !apiKey.isEmpty
    }

    func createSummarizationService() -> SummarizationServiceProtocol {
        OpenAISummarizationService(apiKey: apiKey, model: model, baseURL: baseURL)
    }
}
