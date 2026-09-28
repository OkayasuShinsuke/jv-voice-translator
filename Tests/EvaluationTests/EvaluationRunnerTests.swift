import XCTest
import TranslatorCore
@testable import Evaluation

final class EvaluationRunnerTests: XCTestCase {
    func testErrorRateUsesCERForJapaneseAndWERForVietnamese() {
        XCTAssertEqual(ErrorMetric.forLanguage(.japanese), .cer)
        XCTAssertEqual(ErrorMetric.forLanguage(.vietnamese), .wer)
        XCTAssertEqual(EvaluationRunner.errorRate(reference: "こんにちは", hypothesis: "こんばちは", language: .japanese), 0.2, accuracy: 1e-9)
        XCTAssertEqual(EvaluationRunner.errorRate(reference: "tôi là sinh viên", hypothesis: "tôi là học viên", language: .vietnamese), 0.25, accuracy: 1e-9)
    }

    func testEvaluateTranscripts() throws {
        let samples = [
            EvaluationSample(id: "ja-1", language: .japanese, referenceTranscript: "ありがとう", referenceTranslation: "Cảm ơn"),
            EvaluationSample(id: "vi-1", language: .vietnamese, referenceTranscript: "cảm ơn bạn", referenceTranslation: "ありがとう"),
            EvaluationSample(id: "vi-2", language: .vietnamese, referenceTranscript: "xin chào", referenceTranslation: "こんにちは"),
        ]
        let report = EvaluationRunner().evaluateTranscripts([
            TranscriptHypothesis(id: "ja-1", text: "ありがとう", latency: 0.4),
            TranscriptHypothesis(id: "vi-1", text: "cảm ơn", latency: nil),
        ], samples: samples)
        XCTAssertEqual(report.scores.map(\.id), ["ja-1", "vi-1"])
        XCTAssertEqual(report.missingIDs, ["vi-2"])
        XCTAssertEqual(try XCTUnwrap(report.averageCER), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(report.averageWER), 1.0 / 3.0, accuracy: 1e-9)
        // 遅延は測ったもの(1件)だけで統計を取る
        XCTAssertEqual(report.latencyStats?.count, 1)
    }

    func testIdentityTranslatorAndRegistry() async throws {
        var registry = TranslatorRegistry.builtIn
        XCTAssertEqual(registry.names, ["identity"])
        XCTAssertNil(registry.make("does-not-exist"))
        let identity = try XCTUnwrap(registry.make("identity"))
        let output = try await identity.translate("こんにちは", from: .japanese, to: .vietnamese)
        XCTAssertEqual(output, "こんにちは")

        // 後から別のエンジンを足せる
        registry.register("another") { IdentityTranslator() }
        XCTAssertEqual(registry.names, ["another", "identity"])
    }

    func testEvaluateTranslationWithIdentity() async throws {
        let samples = [
            EvaluationSample(id: "same", language: .japanese, referenceTranscript: "OK", referenceTranslation: "OK"),
            EvaluationSample(id: "diff", language: .vietnamese, referenceTranscript: "xin chào", referenceTranslation: "こんにちは"),
        ]
        let report = try await EvaluationRunner().evaluateTranslation(IdentityTranslator(), samples: samples)
        XCTAssertEqual(report.scores.count, 2)
        XCTAssertEqual(report.scores[0].chrF, 100, accuracy: 1e-9)
        XCTAssertEqual(report.scores[1].chrF, 0, accuracy: 1e-9)
        XCTAssertEqual(report.averageChrF, 50, accuracy: 1e-9)
        XCTAssertEqual(report.scores[1].output, "xin chào")
        XCTAssertNotNil(report.latencyStats)
    }

    /// リポジトリの評価データそのものを読み、件数と id の重複を確かめる。
    func testBundledDatasets() throws {
        let datasets = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EvaluationTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // リポジトリの一番上
            .appendingPathComponent("Evaluation/datasets")
        let samples = try EvaluationRunner.loadSamples(at: datasets)
        XCTAssertGreaterThanOrEqual(samples.count, 40)
        XCTAssertGreaterThanOrEqual(samples.filter { $0.language == .japanese }.count, 20)
        XCTAssertGreaterThanOrEqual(samples.filter { $0.language == .vietnamese }.count, 20)
        for sample in samples {
            XCTAssertFalse(sample.referenceTranscript.isEmpty, sample.id)
            XCTAssertFalse(sample.referenceTranslation.isEmpty, sample.id)
        }
    }

    func testDuplicateIDIsRejected() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("jv-eval-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let json = #"[{"id":"x","language":"ja-JP","referenceTranscript":"a","referenceTranslation":"b"}]"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("a.json"))
        try Data(json.utf8).write(to: folder.appendingPathComponent("b.json"))
        XCTAssertThrowsError(try EvaluationRunner.loadSamples(at: folder)) { error in
            XCTAssertEqual(error as? EvaluationError, .duplicateID("x"))
        }
    }
}
