import XCTest
@testable import TextTranslation

/// SentenceSplitter の「気をつけていること」を確認するテスト。
/// (数字の間の小数点や、閉じカッコの扱い)
final class SentenceSplitterEdgeCaseTests: XCTestCase {
    func testDoesNotSplitOnDecimalPoint() {
        XCTAssertEqual(
            SentenceSplitter.split("体温は35.5度です。明日も測りましょう。"),
            ["体温は35.5度です。", "明日も測りましょう。"])
    }

    func testDoesNotSplitOnDecimalPointInVietnamese() {
        XCTAssertEqual(
            SentenceSplitter.split("Giá là 20.5 đô la. Bạn có muốn mua không?"),
            ["Giá là 20.5 đô la.", "Bạn có muốn mua không?"])
    }

    func testStillSplitsOnNumberedListPeriod() {
        // "1." のように、ピリオドの後が数字でなければ(番号付きリストなど)ふつうに区切る。
        // 小数点だけを特別扱いし、他のピリオドの動きは変えない。
        XCTAssertEqual(
            SentenceSplitter.split("1. 準備する。2. 出発する。"),
            ["1.", "準備する。", "2.", "出発する。"])
    }

    func testKeepsClosingQuoteWithItsSentence() {
        // 修正前は「」」だけが次の文の先頭に取り残されていた(例: "」と言った。")。
        // 修正後は、区切り記号のすぐ後の閉じカッコを前の文の末尾に残す。
        XCTAssertEqual(
            SentenceSplitter.split("彼は「はい。」と言った。次の話をしよう。"),
            ["彼は「はい。」", "と言った。", "次の話をしよう。"])
    }

    func testHandlesMultipleDecimalNumbersInOneSentence() {
        XCTAssertEqual(
            SentenceSplitter.split("身長は1.75で体重は68.2です。"),
            ["身長は1.75で体重は68.2です。"])
    }
}
