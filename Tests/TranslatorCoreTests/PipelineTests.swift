import XCTest
@testable import TranslatorCore

/// テスト用の偽物の翻訳器。「[vi]こんにちは」のように印をつけて返すだけ。
struct FakeTranslator: Translating {
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        "[\(target.languageCode)]\(text)"
    }
}

/// 何を読み上げたか記録するだけの偽物の合成器。
actor RecordingSynthesizer: SpeechSynthesizing {
    var spoken: [(String, Language, VoiceRole)] = []
    func speak(_ text: String, language: Language, voice: VoiceRole) async throws {
        spoken.append((text, language, voice))
    }
    func stop() async {}
}

struct SilentRecognizer: SpeechRecognizing {
    func transcripts(candidates: [Language]) -> AsyncThrowingStream<Transcript, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func stop() async {}
}

/// 部分結果→確定結果の順に2つ流すだけの偽物の認識器。
/// run(onTranscript:) が「部分結果も含めて全部」呼ばれることを確かめるのに使う。
struct TwoStepRecognizer: SpeechRecognizing {
    func transcripts(candidates: [Language]) -> AsyncThrowingStream<Transcript, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(Transcript(text: "こんに", language: .japanese, isFinal: false))
            continuation.yield(Transcript(text: "こんにちは", language: .japanese, isFinal: true))
            continuation.finish()
        }
    }
    func stop() async {}
}

/// テストの中だけで使う、認識結果の文字列を集めるための箱。
/// onTranscript は同じ actor の中から順番に呼ばれるだけなので、@unchecked Sendable にしている。
final class TranscriptCollector: @unchecked Sendable {
    var texts: [String] = []
}

final class PipelineTests: XCTestCase {
    func testJapaneseIsSpokenInVietnameseWithVoiceA() async throws {
        let synth = RecordingSynthesizer()
        let pipeline = TranslationPipeline(recognizer: SilentRecognizer(), translator: FakeTranslator(), synthesizer: synth)
        let event = try await pipeline.handle(Transcript(text: "こんにちは", language: .japanese, isFinal: true))
        XCTAssertEqual(event?.translatedText, "[vi]こんにちは")
        XCTAssertEqual(event?.voice, .a)
        let spoken = await synth.spoken
        XCTAssertEqual(spoken.first?.1, .vietnamese)
        XCTAssertEqual(spoken.first?.2, .a)
    }

    func testVietnameseIsSpokenInJapaneseWithVoiceB() async throws {
        let synth = RecordingSynthesizer()
        let pipeline = TranslationPipeline(recognizer: SilentRecognizer(), translator: FakeTranslator(), synthesizer: synth)
        let event = try await pipeline.handle(Transcript(text: "Xin chào", language: .vietnamese, isFinal: true))
        XCTAssertEqual(event?.voice, .b)
        XCTAssertEqual(event?.translatedText, "[ja]Xin chào")
    }

    func testPartialResultsAreIgnored() async throws {
        let synth = RecordingSynthesizer()
        let pipeline = TranslationPipeline(recognizer: SilentRecognizer(), translator: FakeTranslator(), synthesizer: synth)
        let event = try await pipeline.handle(Transcript(text: "こんに", language: .japanese, isFinal: false))
        XCTAssertNil(event)
        let spoken = await synth.spoken
        XCTAssertTrue(spoken.isEmpty)
    }

    func testDetectorOverridesRecognizerLanguage() async throws {
        let synth = RecordingSynthesizer()
        let pipeline = TranslationPipeline(
            recognizer: SilentRecognizer(), translator: FakeTranslator(), synthesizer: synth,
            detector: ScriptLanguageDetector())
        let event = try await pipeline.handle(Transcript(text: "Cảm ơn bạn", language: .japanese, isFinal: true))
        XCTAssertEqual(event?.source.language, .vietnamese)
        XCTAssertEqual(event?.voice, .b)
    }

    func testRunCallsOnTranscriptForPartialAndFinalResults() async throws {
        let synth = RecordingSynthesizer()
        let pipeline = TranslationPipeline(recognizer: TwoStepRecognizer(), translator: FakeTranslator(), synthesizer: synth)
        // onTranscript はループの中で同期的に呼ばれるので、単純な配列に直接ためられる。
        let collected = TranscriptCollector()
        try await pipeline.run(onTranscript: { collected.texts.append($0.text) })
        XCTAssertEqual(collected.texts, ["こんに", "こんにちは"])
    }

    func testScriptDetector() {
        let detector = ScriptLanguageDetector()
        XCTAssertEqual(detector.detect("ありがとう"), .japanese)
        XCTAssertEqual(detector.detect("Tôi là người Việt"), .vietnamese)
        XCTAssertNil(detector.detect("123"))
    }
}
