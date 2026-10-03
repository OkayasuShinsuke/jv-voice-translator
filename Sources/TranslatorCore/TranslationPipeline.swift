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
    /// 翻訳・読み上げの最中かどうか。true の間にマイクが拾った音(自分の読み上げ自身など)は、
    /// 会話に新しい吹き出しとして混ざらないよう `run` が無視する。
    private var isHandling = false

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
    ///
    /// - Parameter onChunk: 翻訳が文ごとに進むたびに、その時点までの訳文(つながった状態)を渡す。
    ///   渡した翻訳器が `StreamingTranslating` に対応していない場合は、全文が訳し終わった時点で1回だけ呼ばれる。
    @discardableResult
    public func handle(
        _ transcript: Transcript,
        onChunk: @Sendable (String) -> Void = { _ in }
    ) async throws -> TranslationEvent? {
        let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard transcript.isFinal, !text.isEmpty else { return nil }

        let spoken = detector?.detect(text) ?? transcript.language
        let target = spoken.counterpart
        let voice = VoiceRole.forSpoken(spoken)

        let start = Date()
        let translated: String
        if let streaming = translator as? StreamingTranslating {
            // 1文ずつ訳せた順に読み上げる。長文でも「全部訳し終わるまで無言」にならない。
            translated = try await speakAsTranslated(streaming, text: text, from: spoken, to: target, voice: voice, onChunk: onChunk)
        } else {
            translated = try await translator.translate(text, from: spoken, to: target)
            onChunk(translated)
            try await synthesizer.speak(translated, language: target, voice: voice)
        }
        let latency = Date().timeIntervalSince(start)

        var source = transcript
        source.text = text
        source.language = spoken
        return TranslationEvent(source: source, translatedText: translated, voice: voice, translationLatency: latency)
    }

    /// ストリーム翻訳器から1文ずつ受け取り、届いた順に読み上げながら全体をつなげていく。
    private func speakAsTranslated(
        _ translator: StreamingTranslating,
        text: String,
        from source: Language,
        to target: Language,
        voice: VoiceRole,
        onChunk: @Sendable (String) -> Void
    ) async throws -> String {
        var joined = ""
        for try await sentence in translator.translateStream(text, from: source, to: target) {
            joined = joined.isEmpty ? sentence : joined + target.sentenceJoiner + sentence
            onChunk(joined)
            try await synthesizer.speak(sentence, language: target, voice: voice)
        }
        return joined
    }

    /// マイクから聞き続け、確定した文ごとに翻訳して読み上げる。
    ///
    /// - Parameters:
    ///   - onTranscript: 認識結果が出るたびに(まだ話している途中の部分結果も、確定した結果も)呼ばれる。
    ///     画面に「今しゃべっている途中の文字」をリアルタイムに出したいとき(UI用)に使う。
    ///   - onTranslationChunk: 確定した文の翻訳が進むたびに、その時点までの訳文を渡す。1文目ができた時点で呼ばれる。
    ///   - onEvent: 翻訳(と読み上げ)が終わった確定文ごとに呼ばれる。
    ///   - onError: 翻訳または読み上げが失敗したときに、原因のエラーと元の確定文とともに呼ばれる。
    ///     呼ばれなければ画面側は何も気づけず、吹き出しが「翻訳中…」のまま固まって見える。
    ///
    /// たとえ話:マイクが拾った音は次々に手紙(transcript)として届くが、1通処理している間に届いた
    /// 手紙(自分の声が返ってきたものなど)はその場で捨てたい。もし手紙を受け取る係が1通処理し終わる
    /// まで次の手紙を受け取れないとしたら、処理が終わった瞬間にはもう「処理中フラグ」が下りているので
    /// 結局その手紙も読んでしまう。それを防ぐため、1通ごとの処理(`handle`)は裏の作業として並行に
    /// 走らせ、受け取る係(このループ)はマイクの手紙受け取りに専念する。
    ///
    /// たとえ話(エラー):郵便配達中に1通の手紙が壊れて届かなくても、配達員はだまって次の手紙を
    /// 配り続けてはいけない。「この手紙は届きませんでした」と受取人(画面)に一言伝えて初めて、
    /// 受取人は「あ、さっきの話、訳せなかったんだ」と気づける。
    public func run(
        onTranscript: @escaping @Sendable (Transcript) -> Void = { _ in },
        onTranslationChunk: @escaping @Sendable (String) -> Void = { _ in },
        onEvent: @escaping @Sendable (TranslationEvent) -> Void = { _ in },
        onError: @escaping @Sendable (Transcript, Error) -> Void = { _, _ in }
    ) async throws {
        // 認識器が一時停止に対応していれば、読み上げ中は実際にマイクの聞き取りを止める。
        // 対応していなければ nil のままで、これまでどおり isHandling フラグでの無視だけになる。
        let pausable = recognizer as? PausableSpeechRecognizing
        var pendingHandling: [Task<Void, Never>] = []
        for try await transcript in recognizer.transcripts(candidates: Language.allCases) {
            // 翻訳・読み上げの最中に届いた音(自分の声が返ってきたもの等)は、次の話として扱わない。
            if isHandling { continue }
            onTranscript(transcript)
            guard transcript.isFinal else { continue }

            isHandling = true
            await pausable?.pause()
            pendingHandling.append(Task {
                do {
                    if let event = try await self.handle(transcript, onChunk: onTranslationChunk) {
                        onEvent(event)
                    }
                } catch {
                    // 以前はここを `try?` で握りつぶしていたため、翻訳や読み上げが失敗しても
                    // 画面側は永遠に気づけず、吹き出しが「翻訳中…」のまま固まっていた。
                    onError(transcript, error)
                }
                await self.finishHandling(pausable)
            })
        }
        // ストリームが終わっても、最後に走らせた処理が終わるまでは run() を終わらせない。
        for task in pendingHandling {
            await task.value
        }
    }

    /// 1通分の処理(handle)が終わったときに呼ぶ。次の手紙を受け付けられるようにし、
    /// 一時停止していたマイクの聞き取りも再開する。
    private func finishHandling(_ pausable: PausableSpeechRecognizing?) async {
        isHandling = false
        await pausable?.resume()
    }

    public func stop() async {
        await recognizer.stop()
        await synthesizer.stop()
    }
}
