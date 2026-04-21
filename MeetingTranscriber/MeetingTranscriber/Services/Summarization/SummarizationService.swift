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

final class LocalSummarizationService: SummarizationServiceProtocol {
    private let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "being", "but", "by", "for", "from",
        "had", "has", "have", "he", "her", "his", "i", "if", "in", "into", "is", "it", "its",
        "me", "my", "of", "on", "or", "our", "she", "so", "that", "the", "their", "them", "they",
        "this", "to", "was", "we", "were", "will", "with", "you", "your"
    ]

    private let actionKeywords: [String] = [
        "action item", "next step", "follow up", "owner", "deadline", "by ", "will ", "todo"
    ]

    func summarize(transcript: String, type: SummaryType) async throws -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return "" }

        let sentences = splitIntoSentences(cleanedTranscript)
        guard !sentences.isEmpty else { return cleanedTranscript }

        let ranked = rankSentences(sentences)
        let actionItems = extractActionItems(from: sentences)

        switch type {
        case .keyPoints:
            return buildKeyPointsSummary(from: ranked, actionItems: actionItems)
        case .executive:
            return buildExecutiveSummary(from: ranked, actionItems: actionItems)
        case .detailed:
            return buildDetailedSummary(from: ranked, actionItems: actionItems, transcript: cleanedTranscript)
        }
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { ".!?".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 12 }
    }

    private func rankSentences(_ sentences: [String]) -> [String] {
        var frequencies: [String: Int] = [:]
        for sentence in sentences {
            for token in tokenize(sentence) where !stopWords.contains(token) {
                frequencies[token, default: 0] += 1
            }
        }

        let scored = sentences.enumerated().map { index, sentence -> (Int, String, Int) in
            let score = tokenize(sentence)
                .filter { !stopWords.contains($0) }
                .reduce(0) { $0 + frequencies[$1, default: 0] }
            return (index, sentence, score)
        }

        let best = scored
            .sorted { lhs, rhs in
                if lhs.2 == rhs.2 { return lhs.0 < rhs.0 }
                return lhs.2 > rhs.2
            }
            .prefix(min(12, max(4, sentences.count / 4)))
            .sorted { $0.0 < $1.0 }
            .map(\.1)

        return best
    }

    private func extractActionItems(from sentences: [String]) -> [String] {
        sentences.filter { sentence in
            let lower = sentence.lowercased()
            return actionKeywords.contains { lower.contains($0) }
        }
    }

    private func buildKeyPointsSummary(from ranked: [String], actionItems: [String]) -> String {
        var lines = ranked.prefix(6).map { "- \(normalizedSentence($0))" }
        if lines.isEmpty {
            lines = ["- No major discussion points were detected."]
        }

        if !actionItems.isEmpty {
            lines.append("")
            lines.append("Action Items:")
            lines.append(contentsOf: formattedActionItems(actionItems.prefix(6).map { $0 }))
        }
        return lines.joined(separator: "\n")
    }

    private func buildExecutiveSummary(from ranked: [String], actionItems: [String]) -> String {
        let core = ranked.prefix(4).joined(separator: ". ")
        guard !core.isEmpty else { return "This meeting covered several discussion points and concluded with follow-up work." }

        if let firstAction = actionItems.first {
            return "\(normalizedSentence(core)). Primary follow-up: \(normalizedSentence(firstAction))"
        }
        return normalizedSentence(core)
    }

    private func buildDetailedSummary(from ranked: [String], actionItems: [String], transcript: String) -> String {
        let speakerLabels: [String] = transcript
            .split(separator: "\n")
            .compactMap { line in
                guard let range = line.range(of: ":") else { return nil }
                return String(line[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "[]0123456789 "))
            }
            .filter { !$0.isEmpty }
        let speakerCount = Set(speakerLabels).count

        var sections: [String] = []
        sections.append("Overview\n\(normalizedSentence(ranked.prefix(3).joined(separator: ". ")))")
        sections.append("Discussion Points\n" + ranked.prefix(8).map { "- \(normalizedSentence($0))" }.joined(separator: "\n"))

        if actionItems.isEmpty {
            sections.append("Action Items\n- No explicit action items were detected.")
        } else {
            sections.append("Action Items\n" + formattedActionItems(actionItems.prefix(8).map { $0 }).joined(separator: "\n"))
        }

        sections.append("Meeting Signals\n- Estimated active speakers: \(max(1, speakerCount))")
        return sections.joined(separator: "\n\n")
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func formattedActionItems(_ items: [String]) -> [String] {
        items.enumerated().map { index, item in
            let sentence = normalizedSentence(item)
            let owner = extractOwner(from: sentence) ?? "Unassigned"
            let dueDate = extractDueDate(from: sentence) ?? "Not specified"
            return "- [\(index + 1)] \(sentence) (Owner: \(owner); Due: \(dueDate))"
        }
    }

    private func extractOwner(from sentence: String) -> String? {
        if let range = sentence.range(of: " will ", options: .caseInsensitive) {
            let prefix = sentence[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            guard !prefix.isEmpty else { return nil }
            let parts = prefix.split(separator: " ")
            return parts.suffix(min(2, parts.count)).joined(separator: " ")
        }
        return nil
    }

    private func extractDueDate(from sentence: String) -> String? {
        let lowered = sentence.lowercased()
        if let byRange = lowered.range(of: " by ") {
            let suffix = sentence[byRange.upperBound...]
            let tokens = suffix.split(separator: " ")
            guard !tokens.isEmpty else { return nil }
            return tokens.prefix(min(4, tokens.count)).joined(separator: " ")
        }
        return nil
    }

    private func normalizedSentence(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let last = trimmed.last, ".!?".contains(last) {
            return trimmed
        }
        return trimmed + "."
    }
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
