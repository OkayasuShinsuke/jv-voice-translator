import Foundation
import TranslatorCore

/// 評価用データの1件。音声ファイル(任意)、正解の書き起こし、正解の翻訳。
public struct EvaluationSample: Codable, Sendable {
    public var id: String
    public var language: Language
    public var audioFile: String?
    public var referenceTranscript: String
    public var referenceTranslation: String

    public init(id: String, language: Language, audioFile: String? = nil, referenceTranscript: String, referenceTranslation: String) {
        self.id = id
        self.language = language
        self.audioFile = audioFile
        self.referenceTranscript = referenceTranscript
        self.referenceTranslation = referenceTranslation
    }
}

public struct TranslationScore: Codable, Sendable {
    public var id: String
    public var chrF: Double
    public var latency: TimeInterval
}

public struct EvaluationReport: Codable, Sendable {
    public var scores: [TranslationScore]
    public var averageChrF: Double
    public var averageLatency: TimeInterval
}

/// 翻訳エンジンを評価データで採点する。エンジンを入れ替えて同じデータで比べれば、どれが良いか数字で分かる。
public struct EvaluationRunner {
    public init() {}

    public static func loadSamples(from url: URL) throws -> [EvaluationSample] {
        try JSONDecoder().decode([EvaluationSample].self, from: Data(contentsOf: url))
    }

    public func evaluateTranslation(_ translator: Translating, samples: [EvaluationSample]) async throws -> EvaluationReport {
        var scores: [TranslationScore] = []
        for sample in samples {
            let start = Date()
            let output = try await translator.translate(
                sample.referenceTranscript, from: sample.language, to: sample.language.counterpart)
            let latency = Date().timeIntervalSince(start)
            scores.append(TranslationScore(
                id: sample.id,
                chrF: Metrics.chrF(reference: sample.referenceTranslation, hypothesis: output),
                latency: latency))
        }
        let count = Double(max(scores.count, 1))
        return EvaluationReport(
            scores: scores,
            averageChrF: scores.map(\.chrF).reduce(0, +) / count,
            averageLatency: scores.map(\.latency).reduce(0, +) / count)
    }
}
