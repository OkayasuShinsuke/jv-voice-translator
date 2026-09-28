import Foundation
import TranslatorCore

/// 採点結果を Markdown(GitHub でそのまま表として見られる書式)にする。
/// 入力が同じなら出力も必ず同じになる「純粋な」関数なので、テストしやすい。
/// (日時などの変わる情報は入れない。必要なら notes で渡す)
public struct MarkdownReportGenerator {
    public var title: String
    /// 表のセルに入れる文章の最大文字数。長文はここで切って「…」を付ける。
    public var maxCellLength: Int

    public init(title: String = "日越翻訳 評価レポート", maxCellLength: Int = 40) {
        self.title = title
        self.maxCellLength = maxCellLength
    }

    /// レポート全体を作る。translation / transcription は片方だけでもよい。
    /// - Parameters:
    ///   - translatorName: 翻訳エンジンの名前(表示用)。
    ///   - notes: 冒頭に箇条書きで載せる補足。
    public func render(
        translation: EvaluationReport? = nil,
        transcription: TranscriptionReport? = nil,
        translatorName: String? = nil,
        notes: [String] = []
    ) -> String {
        var lines: [String] = ["# \(title)", ""]
        if let translatorName = translatorName {
            lines.append("- 翻訳エンジン: `\(translatorName)`")
        }
        for note in notes {
            lines.append("- \(note)")
        }
        if translatorName != nil || !notes.isEmpty {
            lines.append("")
        }
        if let translation = translation {
            lines += translationSection(translation)
        }
        if let transcription = transcription {
            lines += transcriptionSection(transcription)
        }
        if translation == nil && transcription == nil {
            lines += ["採点結果がありません。", ""]
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 翻訳

    func translationSection(_ report: EvaluationReport) -> [String] {
        var lines: [String] = ["## 翻訳のまとめ(chrF:0〜100、高いほど良い)", ""]
        lines.append("| 方向 | 件数 | 平均 chrF |")
        lines.append("|---|---:|---:|")
        for language in Language.allCases {
            let count = report.scores.filter { $0.language == language }.count
            guard count > 0, let average = report.averageChrF(from: language) else { continue }
            lines.append("| \(Self.directionLabel(language)) | \(count) | \(Self.format(average, digits: 1)) |")
        }
        lines.append("| **全体** | \(report.scores.count) | \(Self.format(report.averageChrF, digits: 1)) |")
        lines.append("")
        lines += latencyTable(report.latencyStats, caption: "翻訳の遅延")
        lines.append("## 翻訳のサンプルごとの結果")
        lines.append("")
        if report.scores.isEmpty {
            lines += ["サンプルがありません。", ""]
            return lines
        }
        lines.append("| ID | 方向 | chrF | 遅延 (ms) | 訳文 |")
        lines.append("|---|---|---:|---:|---|")
        for score in report.scores {
            lines.append("| \(Self.escape(score.id)) | \(Self.shortDirection(score.language)) | \(Self.format(score.chrF, digits: 1)) | \(Self.milliseconds(score.latency)) | \(cell(score.output)) |")
        }
        lines.append("")
        return lines
    }

    // MARK: - 音声認識

    func transcriptionSection(_ report: TranscriptionReport) -> [String] {
        var lines: [String] = ["## 音声認識のまとめ(誤り率:0% が完璧、低いほど良い)", ""]
        lines.append("| 指標 | 件数 | 平均 |")
        lines.append("|---|---:|---:|")
        let cerCount = report.scores.filter { $0.metric == .cer }.count
        let werCount = report.scores.filter { $0.metric == .wer }.count
        if let cer = report.averageCER {
            lines.append("| 日本語 CER | \(cerCount) | \(Self.percent(cer)) |")
        }
        if let wer = report.averageWER {
            lines.append("| ベトナム語 WER | \(werCount) | \(Self.percent(wer)) |")
        }
        lines.append("")
        if !report.missingIDs.isEmpty {
            lines.append("書き起こしが無く採点しなかったサンプル: \(report.missingIDs.count) 件(\(report.missingIDs.map(Self.escape).joined(separator: ", ")))")
            lines.append("")
        }
        lines += latencyTable(report.latencyStats, caption: "音声認識の遅延")
        lines.append("## 音声認識のサンプルごとの結果")
        lines.append("")
        if report.scores.isEmpty {
            lines += ["サンプルがありません。", ""]
            return lines
        }
        lines.append("| ID | 指標 | 誤り率 | 遅延 (ms) | 正解 | 認識結果 |")
        lines.append("|---|---|---:|---:|---|---|")
        for score in report.scores {
            let latency = score.latency.map(Self.milliseconds) ?? "-"
            lines.append("| \(Self.escape(score.id)) | \(score.metric.rawValue) | \(Self.percent(score.errorRate)) | \(latency) | \(cell(score.reference)) | \(cell(score.hypothesis)) |")
        }
        lines.append("")
        return lines
    }

    // MARK: - 部品

    func latencyTable(_ stats: LatencyStats?, caption: String) -> [String] {
        guard let stats = stats else { return [] }
        return [
            "| \(caption) | 平均 | p50 | p90 | 最大 |",
            "|---|---:|---:|---:|---:|",
            "| ミリ秒 | \(Self.milliseconds(stats.mean)) | \(Self.milliseconds(stats.p50)) | \(Self.milliseconds(stats.p90)) | \(Self.milliseconds(stats.maximum)) |",
            "",
        ]
    }

    /// 表のセル用に、改行と「|」を無害化し、長すぎる文章を切る。
    func cell(_ text: String) -> String {
        var value = text
        if value.count > maxCellLength {
            value = String(value.prefix(maxCellLength)) + "…"
        }
        return Self.escape(value)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
    }

    static func directionLabel(_ source: Language) -> String {
        switch source {
        case .japanese: return "日本語 → ベトナム語"
        case .vietnamese: return "ベトナム語 → 日本語"
        }
    }

    static func shortDirection(_ source: Language) -> String {
        "\(source.languageCode)→\(source.counterpart.languageCode)"
    }

    /// 小数を決まった桁数の文字列にする(例: 12.345 → "12.3")。
    static func format(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

    /// 秒をミリ秒の文字列にする(例: 0.1234 → "123.4")。
    static func milliseconds(_ seconds: TimeInterval) -> String {
        format(seconds * 1000, digits: 1)
    }

    /// 0〜1 の割合をパーセントの文字列にする(例: 0.25 → "25.0%")。
    static func percent(_ rate: Double) -> String {
        format(rate * 100, digits: 1) + "%"
    }
}
