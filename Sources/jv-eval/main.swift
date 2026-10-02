import Foundation
import Evaluation
import TranslatorCore

// `swift run jv-eval --dataset Evaluation/datasets --out eval-report.md --translator identity`
// 評価データで翻訳エンジンを採点し、Markdown のレポートを書き出すコマンド。
// CI(GitHub Actions)でも毎回動かし、レポートを成果物(artifact)として保存する。

/// エラーメッセージは標準エラー出力へ(レポート本文と混ざらないように)。
func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// 本体。戻り値は終了コード(0 = 成功)。
func run() async -> Int32 {
    let options: EvalOptions
    do {
        options = try EvalOptions.parse(Array(CommandLine.arguments.dropFirst()))
    } catch {
        printError("エラー: \(error)")
        printError(EvalOptions.usage)
        return 2
    }
    if options.showHelp {
        print(EvalOptions.usage)
        return 0
    }

    // 本物の翻訳エンジンができたら、ここで registry.register("名前") { ... } と足す。
    let registry = TranslatorRegistry.builtIn
    if options.listTranslators {
        print(registry.names.joined(separator: "\n"))
        return 0
    }
    let translator: Translating
    do {
        guard let made = try registry.makeTranslator(named: options.translatorName) else {
            printError("エラー: 翻訳エンジン \"\(options.translatorName)\" はありません。使えるもの: \(registry.names.joined(separator: ", ")), \(TranslatorRegistry.filePrefix)<訳文ファイル.json>")
            return 2
        }
        translator = made
    } catch {
        printError("エラー: 訳文ファイルを読めませんでした: \(error)")
        return 2
    }

    do {
        let samples = try EvaluationRunner.loadSamples(at: URL(fileURLWithPath: options.datasetPath))
        let report = try await EvaluationRunner().evaluateTranslation(translator, samples: samples)
        var notes = ["評価データ: `\(options.datasetPath)`(\(samples.count) 件)"]
        if options.translatorName == "identity" {
            notes.append("identity は入力をそのまま返す基準用のエンジンです。chrF がほぼ 0 になるのが正常です。")
        }
        if options.translatorName.hasPrefix(TranslatorRegistry.filePrefix) {
            notes.append("訳文は事前に別の場所で作ったものです。ここでの遅延はファイルを引く時間なので、翻訳の速さの目安にはなりません。")
        }
        let markdown = MarkdownReportGenerator().render(
            translation: report, translatorName: options.translatorName, notes: notes)
        try markdown.write(to: URL(fileURLWithPath: options.outputPath), atomically: true, encoding: .utf8)
        print("サンプル \(samples.count) 件を採点しました。平均 chrF = \(String(format: "%.1f", report.averageChrF))")
        print("レポート: \(options.outputPath)")
        return 0
    } catch {
        printError("エラー: \(error)")
        return 1
    }
}

exit(await run())
