import XCTest
@testable import ConversationKit
import TranslatorCore

final class ConversationStoreTests: XCTestCase {
    func testPartialThenFinalThenDoneReplacesSameBubble() {
        var store = ConversationStore()
        store.updatePartial(Transcript(text: "こんに", language: .japanese, isFinal: false))
        store.updatePartial(Transcript(text: "こんにちは", language: .japanese, isFinal: false))
        store.finalize(Transcript(text: "こんにちは", language: .japanese, isFinal: true))
        let event = TranslationEvent(
            source: Transcript(text: "こんにちは", language: .japanese, isFinal: true),
            translatedText: "Xin chào", voice: .a, translationLatency: 0.1)
        store.complete(with: event)

        // 部分結果→確定→完了 の3段階を経ても、吹き出しは1つのまま(重複しない)。
        XCTAssertEqual(store.messages.count, 1)
        let message = store.messages[0]
        XCTAssertEqual(message.originalText, "こんにちは")
        XCTAssertEqual(message.translatedText, "Xin chào")
        XCTAssertEqual(message.state, .done)
        XCTAssertEqual(message.side, .right)
    }

    func testSideDerivationFromSpokenLanguage() {
        var store = ConversationStore()
        store.updatePartial(Transcript(text: "Xin chào", language: .vietnamese, isFinal: false))
        XCTAssertEqual(store.messages.first?.side, .left)

        store.clear()
        store.updatePartial(Transcript(text: "こんにちは", language: .japanese, isFinal: false))
        XCTAssertEqual(store.messages.first?.side, .right)
    }

    func testCompleteWithoutPriorPartialAppendsNewBubble() {
        var store = ConversationStore()
        let event = TranslationEvent(
            source: Transcript(text: "ありがとう", language: .japanese, isFinal: true),
            translatedText: "Cảm ơn", voice: .a, translationLatency: 0.2)
        store.complete(with: event)

        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].state, .done)
        XCTAssertEqual(store.messages[0].translatedText, "Cảm ơn")
    }

    func testMessagesStayInChronologicalOrder() {
        var store = ConversationStore()
        store.complete(with: TranslationEvent(
            source: Transcript(text: "1つ目", language: .japanese, isFinal: true),
            translatedText: "one", voice: .a, translationLatency: 0.1))
        store.complete(with: TranslationEvent(
            source: Transcript(text: "2つ目", language: .vietnamese, isFinal: true),
            translatedText: "two", voice: .b, translationLatency: 0.1))
        store.complete(with: TranslationEvent(
            source: Transcript(text: "3つ目", language: .japanese, isFinal: true),
            translatedText: "three", voice: .a, translationLatency: 0.1))

        XCTAssertEqual(store.messages.map(\.originalText), ["1つ目", "2つ目", "3つ目"])
    }

    func testMaxCountDropsOldestMessages() {
        var store = ConversationStore(maxCount: 3)
        for i in 1...5 {
            store.complete(with: TranslationEvent(
                source: Transcript(text: "\(i)", language: .japanese, isFinal: true),
                translatedText: "t\(i)", voice: .a, translationLatency: 0.1))
        }

        XCTAssertEqual(store.messages.count, 3)
        XCTAssertEqual(store.messages.map(\.originalText), ["3", "4", "5"])
    }

    func testFailMarksInProgressBubbleAsFailed() {
        var store = ConversationStore()
        store.updatePartial(Transcript(text: "テスト", language: .japanese, isFinal: false))
        store.finalize(Transcript(text: "テスト", language: .japanese, isFinal: true))
        store.fail("通信エラー")

        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].state, .failed(message: "通信エラー"))
    }

    func testClearRemovesAllMessages() {
        var store = ConversationStore()
        store.updatePartial(Transcript(text: "あ", language: .japanese, isFinal: false))
        store.clear()
        XCTAssertTrue(store.messages.isEmpty)
    }

    func testUpdateTranslationProgressFillsInTranslatedTextWhileTranslating() {
        var store = ConversationStore()
        store.finalize(Transcript(text: "こんにちは", language: .japanese, isFinal: true))

        // 1文目ができた時点で呼ばれる。
        store.updateTranslationProgress("Xin")
        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].translatedText, "Xin")
        XCTAssertEqual(store.messages[0].state, .translating)

        // 2文目までつながった状態で、また呼ばれる。
        store.updateTranslationProgress("Xin chào")
        XCTAssertEqual(store.messages[0].translatedText, "Xin chào")
        XCTAssertEqual(store.messages[0].state, .translating)

        // 最後に complete が来たら、通常どおり .done になる。
        let event = TranslationEvent(
            source: Transcript(text: "こんにちは", language: .japanese, isFinal: true),
            translatedText: "Xin chào bạn", voice: .a, translationLatency: 0.1)
        store.complete(with: event)
        XCTAssertEqual(store.messages[0].translatedText, "Xin chào bạn")
        XCTAssertEqual(store.messages[0].state, .done)
    }

    func testUpdateTranslationProgressDoesNothingWithoutInProgressBubble() {
        var store = ConversationStore()
        store.updateTranslationProgress("Xin")
        XCTAssertTrue(store.messages.isEmpty)
    }
}
