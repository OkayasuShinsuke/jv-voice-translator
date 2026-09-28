import XCTest
import TranslatorCore
@testable import SpeechRecognition

/// 日本語とベトナム語の結果から1つを選ぶ LanguageArbiter のテスト。
final class LanguageArbiterTests: XCTestCase {
    /// いつも同じ言語を答える、テスト用の判定器。
    struct FixedDetector: LanguageDetecting {
        let answer: Language?
        func detect(_ text: String) -> Language? { answer }
    }

    func test確信度が高いほうを選ぶ() {
        let arbiter = LanguageArbiter(detectors: [])
        let chosen = arbiter.choose([
            RecognitionCandidate(language: .japanese, text: "ありがとう", confidence: 0.4),
            RecognitionCandidate(language: .vietnamese, text: "cảm ơn", confidence: 0.9),
        ])
        XCTAssertEqual(chosen?.language, .vietnamese)
        XCTAssertEqual(chosen?.text, "cảm ơn")
    }

    func test空の候補は選ばない() {
        let arbiter = LanguageArbiter()
        let chosen = arbiter.choose([
            RecognitionCandidate(language: .japanese, text: "  ", confidence: 0.99),
            RecognitionCandidate(language: .vietnamese, text: "xin chào", confidence: 0.1),
        ])
        XCTAssertEqual(chosen?.language, .vietnamese)
    }

    func test全部空ならnil() {
        let arbiter = LanguageArbiter()
        XCTAssertNil(arbiter.choose([]))
        XCTAssertNil(arbiter.choose([RecognitionCandidate(language: .japanese, text: "")]))
    }

    func test文字種判定で確信度の差をひっくり返せる() {
        // ベトナム語の認識器が日本語を聞くと、声調記号の無いローマ字のような文字を出しやすい。
        // 文字種判定ではベトナム語と判定されないので、日本語側に点が入る。
        let arbiter = LanguageArbiter(detectors: [ScriptLanguageDetector()])
        let chosen = arbiter.choose([
            RecognitionCandidate(language: .japanese, text: "おはようございます", confidence: 0.6),
            RecognitionCandidate(language: .vietnamese, text: "o ha yo go zai mat", confidence: 0.7),
        ])
        XCTAssertEqual(chosen?.language, .japanese)
    }

    func test判定器が違う言語と言えば減点する() {
        let arbiter = LanguageArbiter(detectors: [FixedDetector(answer: .japanese)], detectorWeight: 0.25)
        let ja = RecognitionCandidate(language: .japanese, text: "a", confidence: 0.5)
        let vi = RecognitionCandidate(language: .vietnamese, text: "a", confidence: 0.5)
        XCTAssertEqual(arbiter.score(ja), 0.75, accuracy: 0.0001)
        XCTAssertEqual(arbiter.score(vi), 0.25, accuracy: 0.0001)
    }

    func test確信度が無いときは真ん中の値を使う() {
        let arbiter = LanguageArbiter(detectors: [])
        let candidate = RecognitionCandidate(language: .japanese, text: "はい", confidence: nil)
        XCTAssertEqual(arbiter.score(candidate), 0.5, accuracy: 0.0001)
    }

    func test同点なら先の候補を選ぶ() {
        let arbiter = LanguageArbiter(detectors: [])
        let chosen = arbiter.choose([
            RecognitionCandidate(language: .vietnamese, text: "một", confidence: 0.5),
            RecognitionCandidate(language: .japanese, text: "いち", confidence: 0.5),
        ])
        XCTAssertEqual(chosen?.language, .vietnamese)
    }

    func test選んだ文字の前後の空白を取る() {
        let arbiter = LanguageArbiter()
        let chosen = arbiter.choose([RecognitionCandidate(language: .japanese, text: " こんにちは \n", confidence: 0.8)])
        XCTAssertEqual(chosen, RecognitionCandidate(language: .japanese, text: "こんにちは", confidence: 0.8))
    }
}
