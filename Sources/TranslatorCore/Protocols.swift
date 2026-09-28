import Foundation

// ここにある4つのプロトコルが、4つのワークストリームの「差し込み口」。
// 各チームはこの形さえ守れば、中身(Apple純正・Whisper・Mac経由など)を自由に入れ替えられる。

/// 音声認識の途中結果・確定結果。
public struct Transcript: Codable, Sendable, Equatable {
    public var text: String
    public var language: Language
    public var isFinal: Bool
    /// 0.0〜1.0。エンジンが出さない場合は nil。
    public var confidence: Double?

    public init(text: String, language: Language, isFinal: Bool, confidence: Double? = nil) {
        self.text = text
        self.language = language
        self.isFinal = isFinal
        self.confidence = confidence
    }
}

/// ワークストリーム① 音声認識。マイク音声を文字にする。
public protocol SpeechRecognizing: Sendable {
    /// 聞き取りを始め、途中結果と確定結果を順に流す。
    /// candidates に複数言語を渡すと、話された言語を自動判定する。
    func transcripts(candidates: [Language]) -> AsyncThrowingStream<Transcript, Error>
    func stop() async
}

/// ワークストリーム② 翻訳。
public protocol Translating: Sendable {
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String
}

/// ワークストリーム③ 音声合成。
public protocol SpeechSynthesizing: Sendable {
    func speak(_ text: String, language: Language, voice: VoiceRole) async throws
    func stop() async
}

/// 認識結果の言語が曖昧なときに、文字から言語を推定する。
public protocol LanguageDetecting: Sendable {
    func detect(_ text: String) -> Language?
}
