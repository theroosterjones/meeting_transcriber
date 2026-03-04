import Foundation
import Accelerate

struct SpeakerProfile: Identifiable, Codable {
    let id: UUID
    let label: String
    var color: SpeakerColor
    var embeddingCentroid: [Float]
    var sampleCount: Int

    init(
        id: UUID = UUID(),
        label: String,
        color: SpeakerColor = .blue,
        embeddingCentroid: [Float] = [],
        sampleCount: Int = 0
    ) {
        self.id = id
        self.label = label
        self.color = color
        self.embeddingCentroid = embeddingCentroid
        self.sampleCount = sampleCount
    }

    mutating func updateCentroid(with newEmbedding: [Float]) {
        guard !newEmbedding.isEmpty else { return }

        if embeddingCentroid.isEmpty {
            embeddingCentroid = newEmbedding
            sampleCount = 1
            return
        }

        let n = Float(sampleCount)
        let newN = n + 1.0
        embeddingCentroid = zip(embeddingCentroid, newEmbedding).map { old, new in
            (old * n + new) / newN
        }
        sampleCount += 1
    }

    func cosineSimilarity(to embedding: [Float]) -> Float {
        guard embeddingCentroid.count == embedding.count, !embeddingCentroid.isEmpty else {
            return 0
        }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(embeddingCentroid, 1, embedding, 1, &dot, vDSP_Length(embeddingCentroid.count))
        vDSP_dotpr(embeddingCentroid, 1, embeddingCentroid, 1, &normA, vDSP_Length(embeddingCentroid.count))
        vDSP_dotpr(embedding, 1, embedding, 1, &normB, vDSP_Length(embedding.count))

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }
}

enum SpeakerColor: String, Codable, CaseIterable {
    case blue, green, orange, purple, red, teal, pink, indigo

    var displayName: String { rawValue.capitalized }
}
