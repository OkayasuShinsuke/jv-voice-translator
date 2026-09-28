import XCTest
import TranslatorCore
@testable import TextTranslation

struct EchoTranslator: Translating {
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        "<\(text)>"
    }
}

final class ChunkedTranslatorTests: XCTestCase {
    func testSplitsJapaneseSentences() {
        XCTAssertEqual(SentenceSplitter.split("今日は晴れです。散歩に行きましょう!"),
                       ["今日は晴れです。", "散歩に行きましょう!"])
    }

    func testSplitsVietnameseSentences() {
        XCTAssertEqual(SentenceSplitter.split("Hôm nay trời đẹp. Đi dạo nhé!"),
                       ["Hôm nay trời đẹp.", "Đi dạo nhé!"])
    }

    func testTranslatesEachSentenceAndJoins() async throws {
        let translator = ChunkedTranslator(base: EchoTranslator())
        let ja = try await translator.translate("A. B.", from: .vietnamese, to: .japanese)
        XCTAssertEqual(ja, "<A.><B.>")
        let vi = try await translator.translate("あ。い。", from: .japanese, to: .vietnamese)
        XCTAssertEqual(vi, "<あ。> <い。>")
    }
}
