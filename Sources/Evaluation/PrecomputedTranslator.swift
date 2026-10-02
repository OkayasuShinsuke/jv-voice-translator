import Foundation
import TranslatorCore

/// 別の場所で先に訳しておいた訳文1件。`jv-eval --translator file:<パス>` で読む JSON の1要素。
///
/// 例:
/// ```json
/// [{"id": "ja-flores-001", "language": "ja-JP", "source": "抗体カクテルの…", "output": "Một hỗn hợp…"}]
/// ```
public struct TranslationHypothesis: Codable, Sendable, Equatable {
    /// 評価データの id(目印。照合には使わない)。
    public var id: String?
    /// 原文の言語。
    public var language: Language
    /// 原文。評価データの referenceTranscript と同じ文字列。
    public var source: String
    /// 翻訳エンジンが出した訳文。
    public var output: String

    public init(id: String? = nil, language: Language, source: String, output: String) {
        self.id = id
        self.language = language
        self.source = source
        self.output = output
    }
}

/// 「答えを書いたメモ」を見て返すだけの翻訳エンジン。
///
/// たとえ話: 試験(評価データ)の答案を、別の部屋(Python の翻訳モデルや iPhone 実機)で
/// 先に書いておき、採点係(`jv-eval`)はその答案用紙を受け取って採点するだけ。
/// こうすると、GitHub の Mac では動かせない翻訳エンジンでも同じ物差しで点数を比べられる。
///
///     [Python + 翻訳モデル] --訳文.json--> [PrecomputedTranslator] --> [EvaluationRunner で採点]
///     [iPhone 実機のアプリ] --訳文.json--/
///
/// 答案に無い文を聞かれたらエラーにする(黙って 0 点にすると、訳し忘れと下手な訳の区別がつかないため)。
public struct PrecomputedTranslator: Translating {
    public enum LoadError: Error, CustomStringConvertible, Equatable {
        case missing(language: Language, source: String)

        public var description: String {
            switch self {
            case .missing(let language, let source):
                return "訳文ファイルに \(language.rawValue) の原文「\(source)」の訳がありません。"
            }
        }
    }

    /// 「言語 + 原文」→ 訳文 の辞書。
    private let outputs: [String: String]

    public init(_ hypotheses: [TranslationHypothesis]) {
        var outputs: [String: String] = [:]
        for hypothesis in hypotheses {
            outputs[Self.key(hypothesis.language, hypothesis.source)] = hypothesis.output
        }
        self.outputs = outputs
    }

    /// JSON ファイルから読む。
    public init(contentsOf url: URL) throws {
        self.init(try JSONDecoder().decode([TranslationHypothesis].self, from: Data(contentsOf: url)))
    }

    public var count: Int { outputs.count }

    public func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        guard let output = outputs[Self.key(source, text)] else {
            throw LoadError.missing(language: source, source: text)
        }
        return output
    }

    private static func key(_ language: Language, _ source: String) -> String {
        language.rawValue + "\n" + source
    }
}

extension TranslatorRegistry {
    /// `--translator` に書く「訳文ファイルを使う」ときの目印。例: `file:mt-hypotheses.json`
    public static let filePrefix = "file:"

    /// 名前からエンジンを作る。`file:<パス>` なら訳文ファイルを読み、それ以外は名簿から探す。
    public func makeTranslator(named name: String) throws -> Translating? {
        if name.hasPrefix(Self.filePrefix) {
            let path = String(name.dropFirst(Self.filePrefix.count))
            return try PrecomputedTranslator(contentsOf: URL(fileURLWithPath: path))
        }
        return make(name)
    }
}
