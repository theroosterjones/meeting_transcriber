import Foundation

enum SummaryType: String, CaseIterable, Identifiable {
    case keyPoints = "Key Points"
    case executive = "Executive Summary"
    case detailed = "Detailed Summary"

    var id: String { rawValue }

    var systemPrompt: String {
        switch self {
        case .keyPoints:
            return """
            You are a meeting notes assistant. Extract the key points from the meeting transcript.
            Format as a bulleted list of the most important decisions, action items, and discussion points.
            Be concise. Each bullet should be one sentence.
            """
        case .executive:
            return """
            You are an executive assistant. Write a brief executive summary of this meeting.
            Include: purpose of meeting, key decisions made, action items with owners, and next steps.
            Keep it under 200 words.
            """
        case .detailed:
            return """
            You are a professional note-taker. Create a detailed summary of this meeting transcript.
            Structure it with sections: Overview, Discussion Points, Decisions Made, Action Items, and Follow-ups.
            Preserve important details and context.
            """
        }
    }
}

protocol SummarizationServiceProtocol {
    func summarize(transcript: String, type: SummaryType) async throws -> String
}

final class OpenAISummarizationService: SummarizationServiceProtocol {
    private let apiKey: String
    private let model: String
    private let baseURL: String
    private let session: URLSession

    private static let maxTokensPerChunk = 12_000

    init(
        apiKey: String,
        model: String = "gpt-4o-mini",
        baseURL: String = "https://api.openai.com/v1"
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    func summarize(transcript: String, type: SummaryType) async throws -> String {
        guard !apiKey.isEmpty else { throw AppError.apiKeyMissing }

        let chunks = chunkTranscript(transcript)

        if chunks.count == 1 {
            return try await callAPI(system: type.systemPrompt, user: transcript)
        }

        var chunkSummaries = [String]()
        for (index, chunk) in chunks.enumerated() {
            let prompt = """
            This is part \(index + 1) of \(chunks.count) of a meeting transcript.
            Summarize this section:
            
            \(chunk)
            """
            let summary = try await callAPI(system: type.systemPrompt, user: prompt)
            chunkSummaries.append(summary)
        }

        let combinedPrompt = """
        Below are summaries of different sections of the same meeting.
        Combine them into one cohesive \(type.rawValue.lowercased()):
        
        \(chunkSummaries.enumerated().map { "--- Section \($0.offset + 1) ---\n\($0.element)" }.joined(separator: "\n\n"))
        """
        return try await callAPI(system: type.systemPrompt, user: combinedPrompt)
    }

    // MARK: - Private

    private func callAPI(system: String, user: String) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.3,
            "max_tokens": 2048
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AppError.networkError(
                NSError(domain: "OpenAI", code: statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "API returned status \(statusCode)"])
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AppError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chunkTranscript(_ text: String) -> [String] {
        let words = text.split(separator: " ")
        let wordsPerChunk = Self.maxTokensPerChunk * 3 / 4

        guard words.count > wordsPerChunk else { return [text] }

        var chunks = [String]()
        var start = 0
        while start < words.count {
            let end = min(start + wordsPerChunk, words.count)
            let chunk = words[start..<end].joined(separator: " ")
            chunks.append(chunk)
            start = end
        }
        return chunks
    }
}
