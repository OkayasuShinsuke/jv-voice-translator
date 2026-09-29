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

    func testStreamingTranslatorSpeaksEachSentenceAsItArrivesAndJoinsChunks() async throws {
        let synth = RecordingSynthesizer()
        let pipeline = TranslationPipeline(
            recognizer: SilentRecognizer(), translator: FakeStreamingTranslator(), synthesizer: synth)
        let collector = TranscriptCollector()
        let event = try await pipeline.handle(
            Transcript(text: "あ。い。", language: .japanese, isFinal: true),
            onChunk: { collector.texts.append($0) })

        // 文ごとに2回、読み上げが呼ばれている(1文目ができた時点で読み上げを始められる)。
        let spoken = await synth.spoken
        XCTAssertEqual(spoken.map(\.0), ["[vi]あ。", "[vi]い。"])
        // onChunk には「今までにつながった訳」が段階的に渡される。
        XCTAssertEqual(collector.texts, ["[vi]あ。", "[vi]あ。 [vi]い。"])
        XCTAssertEqual(event?.translatedText, "[vi]あ。 [vi]い。")
    }

    func testRunIgnoresTranscriptsThatArriveWhileHandlingAPreviousOne() async throws {
        let synth = RecordingSynthesizer()
        // 1文目を処理している間(SlowTranslatorがわざと少し待つ間)に、2文目が届く状況を再現する。
        let recognizer = ScriptedRecognizer(events: [
            (Transcript(text: "こんにちは", language: .japanese, isFinal: true), 0),
            (Transcript(text: "ただいま(自分の声が返ってきたもの)", language: .japanese, isFinal: true), 0.05),
        ])
        let pipeline = TranslationPipeline(recognizer: recognizer, translator: SlowTranslator(delay: 0.2), synthesizer: synth)
        let events = EventCollector()
        try await pipeline.run(onEvent: { events.items.append($0) })

        // 2文目は1文目の処理中に届いたので無視され、確定イベントは1回だけになる。
        XCTAssertEqual(events.items.count, 1)
        XCTAssertEqual(events.items.first?.source.text, "こんにちは")
    }

    func testPausableRecognizerIsPausedWhileHandlingAndResumedAfter() async throws {
        let synth = RecordingSynthesizer()
        let recognizer = PausableFakeRecognizer(events: [
            (Transcript(text: "こんにちは", language: .japanese, isFinal: true), 0),
        ])
        let pipeline = TranslationPipeline(recognizer: recognizer, translator: SlowTranslator(delay: 0.05), synthesizer: synth)
        try await pipeline.run()

        // 処理中は一時停止し、終わったら再開している(この順番どおりに1回ずつ)。
        let calls = await recognizer.calls
        XCTAssertEqual(calls, ["pause", "resume"])
    }
}

/// 文ごとに訳し、1文ずつ流す偽物のストリーム翻訳器。
struct FakeStreamingTranslator: StreamingTranslating {
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        "[\(target.languageCode)]\(text)"
    }

    func translateStream(_ text: String, from source: Language, to target: Language) -> AsyncThrowingStream<String, Error> {
        let sentences = text.split(separator: "。").map { "\($0)。" }
        return AsyncThrowingStream { continuation in
            for sentence in sentences {
                continuation.yield("[\(target.languageCode)]\(sentence)")
            }
            continuation.finish()
        }
    }
}

/// 訳すのにわざと時間がかかる偽物の翻訳器。echo(自分の声の拾い直し)を再現するテスト専用。
struct SlowTranslator: Translating {
    let delay: TimeInterval
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return "[\(target.languageCode)]\(text)"
    }
}

/// 決まった時間差でイベントを流す偽物の認識器。テストで「処理中に次が届く」状況を再現するために使う。
struct ScriptedRecognizer: SpeechRecognizing {
    let events: [(Transcript, TimeInterval)]

    func transcripts(candidates: [Language]) -> AsyncThrowingStream<Transcript, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for (transcript, delay) in events {
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    continuation.yield(transcript)
                }
                continuation.finish()
            }
        }
    }

    func stop() async {}
}

/// テストの中だけで使う、確定イベントを集めるための箱(TranscriptCollector と同じ理由で @unchecked Sendable)。
final class EventCollector: @unchecked Sendable {
    var items: [TranslationEvent] = []
}

/// 一時停止・再開が呼ばれた順番を記録する、偽物の一時停止対応認識器。
actor PausableFakeRecognizer: PausableSpeechRecognizing {
    private let events: [(Transcript, TimeInterval)]
    private(set) var calls: [String] = []

    init(events: [(Transcript, TimeInterval)]) {
        self.events = events
    }

    nonisolated func transcripts(candidates: [Language]) -> AsyncThrowingStream<Transcript, Error> {
        let events = self.events
        return AsyncThrowingStream { continuation in
            Task {
                for (transcript, delay) in events {
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    continuation.yield(transcript)
                }
                continuation.finish()
            }
        }
    }

    func stop() async {}

    func pause() async { calls.append("pause") }
    func resume() async { calls.append("resume") }
}
