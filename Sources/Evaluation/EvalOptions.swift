import Foundation

/// `jv-eval` コマンドの引数。外部ライブラリを使わず自前で読む。
/// 例: `swift run jv-eval --dataset Evaluation/datasets --out eval-report.md --translator identity`
public struct EvalOptions: Equatable {
    public var datasetPath: String = "Evaluation/datasets"
    public var outputPath: String = "eval-report.md"
    public var translatorName: String = "identity"
    public var showHelp: Bool = false
    public var listTranslators: Bool = false

    public init() {}

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case missingValue(String)
        case unknownOption(String)

        public var description: String {
            switch self {
            case .missingValue(let option): return "\(option) の後に値がありません。"
            case .unknownOption(let option): return "知らないオプションです: \(option)"
            }
        }
    }

    public static let usage = """
    使い方: jv-eval [--dataset <フォルダまたは.json>] [--out <出力.md>] [--translator <名前>]
      --dataset      評価データの場所(既定: Evaluation/datasets)
      --out          レポートの出力先(既定: eval-report.md)
      --translator   使う翻訳エンジンの名前(既定: identity)
      --list-translators  使える翻訳エンジンの名前を表示
      -h, --help     この説明を表示
    """

    /// 引数の配列(プログラム名を除いたもの)を読む。`--out=x.md` の形にも対応。
    public static func parse(_ arguments: [String]) throws -> EvalOptions {
        var options = EvalOptions()
        var index = 0
        while index < arguments.count {
            var argument = arguments[index]
            var inlineValue: String? = nil
            if argument.hasPrefix("--"), let equal = argument.firstIndex(of: "=") {
                inlineValue = String(argument[argument.index(after: equal)...])
                argument = String(argument[..<equal])
            }
            // 値を1つ受け取るオプションの共通処理。
            func value() throws -> String {
                if let inlineValue = inlineValue { return inlineValue }
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                    throw ParseError.missingValue(argument)
                }
                index += 1
                return arguments[index]
            }
            switch argument {
            case "--dataset": options.datasetPath = try value()
            case "--out", "--output": options.outputPath = try value()
            case "--translator": options.translatorName = try value()
            case "--list-translators": options.listTranslators = true
            case "-h", "--help": options.showHelp = true
            default: throw ParseError.unknownOption(argument)
            }
            index += 1
        }
        return options
    }
}
