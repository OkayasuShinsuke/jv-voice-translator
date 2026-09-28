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

/// 翻訳1件ぶんの採点結果。
public struct TranslationScore: Codable, Sendable {
    public var id: String
    /// 話された(翻訳元の)言語。ja-JP なら「日本語 → ベトナム語」の翻訳。
    public var language: Language
    /// 翻訳エンジンが実際に出した訳文。
    public var output: String
    public var chrF: Double
    public var latency: TimeInterval

    public init(id: String, language: Language, output: String, chrF: Double, latency: TimeInterval) {
        self.id = id
        self.language = language
        self.output = output
        self.chrF = chrF
        self.latency = latency
    }
}

/// 翻訳の採点結果のまとめ。
public struct EvaluationReport: Codable, Sendable {
    public var scores: [TranslationScore]
    public var averageChrF: Double
    public var averageLatency: TimeInterval

    public init(scores: [TranslationScore]) {
        self.scores = scores
        let count = Double(max(scores.count, 1))
        self.averageChrF = scores.map(\.chrF).reduce(0, +) / count
        self.averageLatency = scores.map(\.latency).reduce(0, +) / count
    }

    /// 遅延の統計(平均・中央値・p90)。サンプルが0件なら nil。
    public var latencyStats: LatencyStats? {
        LatencyStats(scores.map(\.latency))
    }

    /// 指定した言語から訳したサンプルだけの平均 chrF。該当が0件なら nil。
    public func averageChrF(from language: Language) -> Double? {
        let values = scores.filter { $0.language == language }.map(\.chrF)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - 音声認識(ASR)の評価

/// 音声認識の誤り率の種類。日本語は CER(文字)、ベトナム語は WER(単語)で測る。
public enum ErrorMetric: String, Codable, Sendable {
    case cer = "CER"
    case wer = "WER"

    /// 言語ごとに使う指標を決める。
    public static func forLanguage(_ language: Language) -> ErrorMetric {
        language == .japanese ? .cer : .wer
    }
}

/// 音声認識エンジンが出した書き起こし1件。id で評価データのサンプルと結びつける。
public struct TranscriptHypothesis: Codable, Sendable {
    public var id: String
    public var text: String
    /// 話し終わってから確定するまでの秒数。測っていなければ nil。
    public var latency: TimeInterval?

    public init(id: String, text: String, latency: TimeInterval? = nil) {
        self.id = id
        self.text = text
        self.latency = latency
    }
}

/// 書き起こし1件ぶんの採点結果。
public struct TranscriptScore: Codable, Sendable {
    public var id: String
    public var language: Language
    public var metric: ErrorMetric
    public var reference: String
    public var hypothesis: String
    /// 誤り率。0 が完璧(1 を超えることもある)。
    public var errorRate: Double
    public var latency: TimeInterval?

    public init(id: String, language: Language, metric: ErrorMetric, reference: String, hypothesis: String, errorRate: Double, latency: TimeInterval?) {
        self.id = id
        self.language = language
        self.metric = metric
        self.reference = reference
        self.hypothesis = hypothesis
        self.errorRate = errorRate
        self.latency = latency
    }
}

/// 音声認識の採点結果のまとめ。
public struct TranscriptionReport: Codable, Sendable {
    public var scores: [TranscriptScore]
    /// 評価データにあるのに書き起こしが無かったサンプルの id。
    public var missingIDs: [String]

    public init(scores: [TranscriptScore], missingIDs: [String] = []) {
        self.scores = scores
        self.missingIDs = missingIDs
    }

    /// 日本語サンプルの平均 CER。日本語が0件なら nil。
    public var averageCER: Double? { average(of: .cer) }
    /// ベトナム語サンプルの平均 WER。ベトナム語が0件なら nil。
    public var averageWER: Double? { average(of: .wer) }

    /// 遅延の統計。遅延を測ったサンプルが0件なら nil。
    public var latencyStats: LatencyStats? {
        LatencyStats(scores.compactMap(\.latency))
    }

    private func average(of metric: ErrorMetric) -> Double? {
        let values = scores.filter { $0.metric == metric }.map(\.errorRate)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

/// 評価データを読み込むときのエラー。
public enum EvaluationError: Error, CustomStringConvertible, Equatable {
    case noDatasetFiles(String)
    case duplicateID(String)

    public var description: String {
        switch self {
        case .noDatasetFiles(let path): return "評価データ(.json)が見つかりません: \(path)"
        case .duplicateID(let id): return "評価データの id が重複しています: \(id)"
        }
    }
}

/// 翻訳エンジンを評価データで採点する。エンジンを入れ替えて同じデータで比べれば、どれが良いか数字で分かる。
public struct EvaluationRunner {
    public init() {}

    /// JSON ファイル1つから評価データを読む。
    public static func loadSamples(from url: URL) throws -> [EvaluationSample] {
        try JSONDecoder().decode([EvaluationSample].self, from: Data(contentsOf: url))
    }

    /// ファイルでもフォルダでも読める。フォルダなら中の .json をファイル名順に全部読んでつなげる。
    /// id が重複していたらエラーにする(採点結果が混ざらないように)。
    public static func loadSamples(at url: URL) throws -> [EvaluationSample] {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let files: [URL]
        if exists && isDirectory.boolValue {
            files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if files.isEmpty { throw EvaluationError.noDatasetFiles(url.path) }
        } else {
            files = [url]
        }
        var samples: [EvaluationSample] = []
        var seen = Set<String>()
        for file in files {
            for sample in try loadSamples(from: file) {
                if seen.contains(sample.id) { throw EvaluationError.duplicateID(sample.id) }
                seen.insert(sample.id)
                samples.append(sample)
            }
        }
        return samples
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
                language: sample.language,
                output: output,
                chrF: Metrics.chrF(reference: sample.referenceTranslation, hypothesis: output),
                latency: latency))
        }
        return EvaluationReport(scores: scores)
    }

    /// 言語に合った誤り率を計算する(日本語 = CER、ベトナム語 = WER)。
    public static func errorRate(reference: String, hypothesis: String, language: Language) -> Double {
        switch ErrorMetric.forLanguage(language) {
        case .cer: return Metrics.characterErrorRate(reference: reference, hypothesis: hypothesis)
        case .wer: return Metrics.wordErrorRate(reference: reference, hypothesis: hypothesis)
        }
    }

    /// 音声認識の書き起こし(認識結果の一覧)を、評価データの正解書き起こしと比べて採点する。
    /// - 書き起こしは id でサンプルと結びつける。評価データに無い id の書き起こしは無視する。
    /// - 書き起こしが無いサンプルは採点せず、`missingIDs` に入れる(0点扱いにして平均を歪めないため)。
    /// 音声を実際に認識する部分はここには無いので、実機で集めた結果を渡して使う。
    public func evaluateTranscripts(_ hypotheses: [TranscriptHypothesis], samples: [EvaluationSample]) -> TranscriptionReport {
        var byID: [String: TranscriptHypothesis] = [:]
        for hypothesis in hypotheses where byID[hypothesis.id] == nil {
            byID[hypothesis.id] = hypothesis
        }
        var scores: [TranscriptScore] = []
        var missing: [String] = []
        for sample in samples {
            guard let hypothesis = byID[sample.id] else {
                missing.append(sample.id)
                continue
            }
            scores.append(TranscriptScore(
                id: sample.id,
                language: sample.language,
                metric: ErrorMetric.forLanguage(sample.language),
                reference: sample.referenceTranscript,
                hypothesis: hypothesis.text,
                errorRate: Self.errorRate(
                    reference: sample.referenceTranscript, hypothesis: hypothesis.text, language: sample.language),
                latency: hypothesis.latency))
        }
        return TranscriptionReport(scores: scores, missingIDs: missing)
    }
}
