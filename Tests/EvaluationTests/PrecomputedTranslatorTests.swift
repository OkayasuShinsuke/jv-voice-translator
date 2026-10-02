import XCTest
import TranslatorCore
@testable import Evaluation

final class PrecomputedTranslatorTests: XCTestCase {
    func testLooksUpByLanguageAndSource() async throws {
        let translator = PrecomputedTranslator([
            TranslationHypothesis(id: "ja-1", language: .japanese, source: "ありがとう", output: "Cảm ơn"),
            TranslationHypothesis(language: .vietnamese, source: "xin chào", output: "こんにちは"),
        ])
        XCTAssertEqual(translator.count, 2)
        let vi = try await translator.translate("ありがとう", from: .japanese, to: .vietnamese)
        XCTAssertEqual(vi, "Cảm ơn")
        let ja = try await translator.translate("xin chào", from: .vietnamese, to: .japanese)
        XCTAssertEqual(ja, "こんにちは")
    }

    func testMissingSourceThrowsInsteadOfScoringZero() async {
        let translator = PrecomputedTranslator([
            TranslationHypothesis(language: .japanese, source: "ありがとう", output: "Cảm ơn"),
        ])
        do {
            // 原文は同じでも言語が違えば別物として扱う
            _ = try await translator.translate("ありがとう", from: .vietnamese, to: .japanese)
            XCTFail("エラーになるはず")
        } catch {
            XCTAssertEqual(error as? PrecomputedTranslator.LoadError,
                           .missing(language: .vietnamese, source: "ありがとう"))
        }
    }

    func testRegistryLoadsFilePrefixAndScoresPerfectMatch() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hypotheses-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let json = """
        [{"id": "ja-1", "language": "ja-JP", "source": "ありがとう", "output": "Cảm ơn"}]
        """
        try Data(json.utf8).write(to: url)

        let registry = TranslatorRegistry.builtIn
        let translator = try XCTUnwrap(try registry.makeTranslator(named: "file:" + url.path))
        let samples = [EvaluationSample(id: "ja-1", language: .japanese,
                                        referenceTranscript: "ありがとう", referenceTranslation: "Cảm ơn")]
        let report = try await EvaluationRunner().evaluateTranslation(translator, samples: samples)
        XCTAssertEqual(report.averageChrF, 100, accuracy: 1e-6)

        // 普通の名前は今まで通り名簿から探す
        XCTAssertNotNil(try registry.makeTranslator(named: "identity"))
        XCTAssertNil(try registry.makeTranslator(named: "does-not-exist"))
    }
}
