import XCTest
@testable import ConversationKit
import TranslatorCore

/// ChatMessage.accessibilitySummary(VoiceOver 用の読み上げ文)を確認するテスト。
final class ChatMessageAccessibilityTests: XCTestCase {
    func testListeningWithEmptyText() {
        let message = ChatMessage(
            side: .right, originalText: "", spokenLanguage: .japanese, voice: .a, state: .listening)
        XCTAssertEqual(message.accessibilitySummary, "日本語を聞き取り中。まだ何も聞き取れていません")
    }

    func testListeningWithPartialText() {
        let message = ChatMessage(
            side: .right, originalText: "こんに", spokenLanguage: .japanese, voice: .a, state: .listening)
        XCTAssertEqual(message.accessibilitySummary, "日本語を聞き取り中。こんに")
    }

    func testTranslating() {
        let message = ChatMessage(
            side: .left, originalText: "Xin chào", spokenLanguage: .vietnamese, voice: .b, state: .translating)
        XCTAssertEqual(message.accessibilitySummary, "ベトナム語: Xin chào。翻訳中です。")
    }

    func testDoneIncludesOriginalAndTranslated() {
        let message = ChatMessage(
            side: .right, originalText: "こんにちは", translatedText: "Xin chào",
            spokenLanguage: .japanese, voice: .a, state: .done)
        XCTAssertEqual(message.accessibilitySummary, "日本語: こんにちは。訳: Xin chào。タップすると読み上げます。")
    }

    func testFailedIncludesReason() {
        let message = ChatMessage(
            side: .right, originalText: "こんにちは", spokenLanguage: .japanese, voice: .a,
            state: .failed(message: "通信エラー"))
        XCTAssertEqual(message.accessibilitySummary, "日本語: こんにちは。うまく訳せませんでした。理由: 通信エラー")
    }
}
