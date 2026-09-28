import Foundation

/// 1回分の翻訳の記録。評価(ワークストリーム④)でも使う。
public struct TranslationEvent: Codable, Sendable, Equatable {
    public var source: Transcript
    public var translatedText: String
    public var voice: VoiceRole
    /// 確定した認識結果が出てから、翻訳が終わるまでの秒数。
    public var translationLatency: TimeInterval

    public init(source: Transcript, translatedText: String, voice: VoiceRole, translationLatency: TimeInterval) {
        self.source = source
        self.translatedText = translatedText
        self.voice = voice
        self.translationLatency = translationLatency
    }
}

/// 「聞く → 訳す → 話す」をつなぐベルトコンベア。
/// 部品(認識・翻訳・合成)は外から渡すので、iPhone単体でもMac連携でも同じコードで動く。
public actor TranslationPipeline {
    private let recognizer: SpeechRecognizing
    private let translator: Translating
    private let synthesizer: SpeechSynthesizing
    private let detector: LanguageDetecting?

    public init(
        recognizer: SpeechRecognizing,
        translator: Translating,
        synthesizer: SpeechSynthesizing,
        detector: LanguageDetecting? = nil
    ) {
        self.recognizer = recognizer
        self.translator = translator
        self.synthesizer = synthesizer
        self.detector = detector
    }

    /// 確定した1文を処理する。テストしやすいよう、ストリームとは分けてある。
    @discardableResult
    public func handle(_ transcript: Transcript) async throws -> TranslationEvent? {
        let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard transcript.isFinal, !text.isEmpty else { return nil }

        let spoken = detector?.detect(text) ?? transcript.language
        let target = spoken.counterpart
        let voice = VoiceRole.forSpoken(spoken)

        let start = Date()
        let translated = try await translator.translate(text, from: spoken, to: target)
        let latency = Date().timeIntervalSince(start)

        try await synthesizer.speak(translated, language: target, voice: voice)

        var source = transcript
        source.text = text
        source.language = spoken
        return TranslationEvent(source: source, translatedText: translated, voice: voice, translationLatency: latency)
    }

    /// マイクから聞き続け、確定した文ごとに翻訳して読み上げる。
    public func run(onEvent: @Sendable (TranslationEvent) -> Void = { _ in }) async throws {
        for try await transcript in recognizer.transcripts(candidates: Language.allCases) {
            if let event = try await handle(transcript) {
                onEvent(event)
            }
        }
    }

    public func stop() async {
        await recognizer.stop()
        await synthesizer.stop()
    }
}
