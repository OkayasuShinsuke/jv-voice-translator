import XCTest
import TranslatorCore
@testable import Evaluation

final class ReportTests: XCTestCase {
    private func sampleTranslationReport() -> EvaluationReport {
        EvaluationReport(scores: [
            TranslationScore(id: "ja-1", language: .japanese, output: "Xin chào", chrF: 80, latency: 0.1),
            TranslationScore(id: "ja-2", language: .japanese, output: "a|b\nc", chrF: 60, latency: 0.3),
            TranslationScore(id: "vi-1", language: .vietnamese, output: "こんにちは", chrF: 40, latency: 0.2),
        ])
    }

    func testTranslationSummaryAndRows() {
        let markdown = MarkdownReportGenerator(title: "テスト").render(
            translation: sampleTranslationReport(), translatorName: "identity", notes: ["メモ"])
        XCTAssertTrue(markdown.hasPrefix("# テスト\n"))
        XCTAssertTrue(markdown.contains("- 翻訳エンジン: `identity`"))
        XCTAssertTrue(markdown.contains("- メモ"))
        // 方向ごとの平均と全体の平均
        XCTAssertTrue(markdown.contains("| 日本語 → ベトナム語 | 2 | 70.0 |"))
        XCTAssertTrue(markdown.contains("| ベトナム語 → 日本語 | 1 | 40.0 |"))
        XCTAssertTrue(markdown.contains("| **全体** | 3 | 60.0 |"))
        // 遅延:平均 200ms、p50 200ms、p90 280ms、最大 300ms
        XCTAssertTrue(markdown.contains("| ミリ秒 | 200.0 | 200.0 | 280.0 | 300.0 |"))
        // サンプルごとの行
        XCTAssertTrue(markdown.contains("| ja-1 | ja→vi | 80.0 | 100.0 | Xin chào |"))
        XCTAssertTrue(markdown.contains("| vi-1 | vi→ja | 40.0 | 200.0 | こんにちは |"))
        // 「|」と改行は表を壊さないように無害化される
        XCTAssertTrue(markdown.contains("| a\\|b c |"))
    }

    func testRenderIsDeterministic() {
        let generator = MarkdownReportGenerator()
        let report = sampleTranslationReport()
        XCTAssertEqual(generator.render(translation: report), generator.render(translation: report))
    }

    func testLongTextIsTruncated() {
        let generator = MarkdownReportGenerator(maxCellLength: 5)
        XCTAssertEqual(generator.cell("あいうえおかきくけこ"), "あいうえお…")
        XCTAssertEqual(generator.cell("あいう"), "あいう")
    }

    func testEmptyReport() {
        let markdown = MarkdownReportGenerator().render()
        XCTAssertTrue(markdown.contains("採点結果がありません。"))
        let emptyTranslation = MarkdownReportGenerator().render(translation: EvaluationReport(scores: []))
        XCTAssertTrue(emptyTranslation.contains("サンプルがありません。"))
    }

    func testTranscriptionSection() {
        let samples = [
            EvaluationSample(id: "ja-1", language: .japanese, referenceTranscript: "こんにちは", referenceTranslation: "Xin chào"),
            EvaluationSample(id: "vi-1", language: .vietnamese, referenceTranscript: "tôi là sinh viên", referenceTranslation: "私は学生です"),
            EvaluationSample(id: "vi-2", language: .vietnamese, referenceTranscript: "xin chào", referenceTranslation: "こんにちは"),
        ]
        let hypotheses = [
            TranscriptHypothesis(id: "ja-1", text: "こんばちは", latency: 0.5),
            TranscriptHypothesis(id: "vi-1", text: "tôi là học viên", latency: 1.5),
            TranscriptHypothesis(id: "unknown", text: "無視される"),
        ]
        let report = EvaluationRunner().evaluateTranscripts(hypotheses, samples: samples)
        let markdown = MarkdownReportGenerator().render(transcription: report)
        XCTAssertTrue(markdown.contains("| 日本語 CER | 1 | 20.0% |"))
        XCTAssertTrue(markdown.contains("| ベトナム語 WER | 1 | 25.0% |"))
        XCTAssertTrue(markdown.contains("書き起こしが無く採点しなかったサンプル: 1 件(vi-2)"))
        XCTAssertTrue(markdown.contains("| ja-1 | CER | 20.0% | 500.0 | こんにちは | こんばちは |"))
        XCTAssertTrue(markdown.contains("| ミリ秒 | 1000.0 | 1000.0 | 1400.0 | 1500.0 |"))
    }
}
