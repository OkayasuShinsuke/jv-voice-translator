import XCTest
import TranslatorCore
@testable import SpeechRecognition

/// SpeechRecognitionError の日本語メッセージ(errorDescription / recoverySuggestion)を確認するテスト。
/// 画面のアラートにそのまま出す文なので、nil にならないこと・空文字でないことを確かめる。
final class SpeechRecognitionErrorTests: XCTestCase {
    func testNotAuthorizedHasMessageAndSettingsGuidance() {
        let error = SpeechRecognitionError.notAuthorized
        XCTAssertEqual(error.errorDescription, "マイクや音声認識が許可されていません。")
        XCTAssertEqual(
            error.recoverySuggestion,
            "「設定」アプリ →「JV Translator」→「マイク」と「音声認識」を両方ともオンにしてください。")
    }

    func testUnsupportedLanguageMentionsLanguageName() {
        let ja = SpeechRecognitionError.unsupportedLanguage(.japanese)
        XCTAssertEqual(ja.errorDescription, "日本語の音声認識が、この端末では使えません。")

        let vi = SpeechRecognitionError.unsupportedLanguage(.vietnamese)
        XCTAssertEqual(vi.errorDescription, "ベトナム語の音声認識が、この端末では使えません。")
    }

    func testRepeatedFailuresMentionsLanguageName() {
        let error = SpeechRecognitionError.repeatedFailures(.vietnamese)
        XCTAssertEqual(error.errorDescription, "ベトナム語の聞き取りがうまくいかない状態が続いたので、いったん止めました。")
    }

    func testAllCasesHaveNonEmptyMessages() {
        let errors: [SpeechRecognitionError] = [
            .notAuthorized,
            .unsupportedLanguage(.japanese),
            .speechAnalyzerUnavailable,
            .noAvailableEngine,
            .repeatedFailures(.japanese),
        ]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty, "\(error) に説明文が無い")
            XCTAssertFalse((error.recoverySuggestion ?? "").isEmpty, "\(error) に対処法が無い")
        }
    }
}
