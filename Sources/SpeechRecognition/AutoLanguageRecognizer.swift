// ワークストリーム① 音声認識:日本語とベトナム語を自動で聞き分ける認識器(おすすめ)。
import Foundation
import TranslatorCore
#if canImport(Speech) && canImport(AVFoundation)
import AVFoundation
import Speech
#endif

extension LanguageArbiter {
    /// ふだん使う審判。文字種判定と、使えれば Apple の NaturalLanguage による判定を組み合わせる。
    public static var standard: LanguageArbiter {
        #if canImport(NaturalLanguage)
        return LanguageArbiter(detectors: [ScriptLanguageDetector(), NaturalLanguageDetector()])
        #else
        return LanguageArbiter(detectors: [ScriptLanguageDetector()])
        #endif
    }
}

#if canImport(Speech) && canImport(AVFoundation)
/// 日本語とベトナム語を自動で聞き分ける認識器。
///
/// たとえるなら、日本語担当とベトナム語担当の2人の通訳者に同じ話を同時に聞いてもらい、
/// 話し手が 0.8 秒黙るたびに、審判(LanguageArbiter)が「今の文はどちらの言語だったか」を決めて、
/// 採用したほうのメモだけを1回だけ渡す仕組みです。
///
/// 使う認識の仕組みは言語ごとに自動で選ぶ:
/// - iOS 26 以降でその言語に対応していれば SpeechAnalyzer(新しくて速い)
/// - そうでなければ SFSpeechRecognizer(AppleSpeechRecognizer と同じ仕組み)
public final class AutoLanguageRecognizer: PausableSpeechRecognizing, @unchecked Sendable {
    /// どの認識の仕組みを使うか。
    public enum EnginePreference: Sendable, Equatable {
        /// SpeechAnalyzer が使えればそれを、だめなら SFSpeechRecognizer を使う。
        case automatic
        /// SpeechAnalyzer だけを使う(使えない言語はエラー)。比較・評価用。
        case speechAnalyzer
        /// SFSpeechRecognizer だけを使う。比較・評価用。
        case sfSpeech
    }

    private let lock = NSLock()
    private var _engine: EnginePreference
    private var _preferOnDevice: Bool
    private var _segmenterConfiguration: SilenceSegmenter.Configuration
    private var _arbiter: LanguageArbiter
    private var session: SegmentedRecognitionSession?

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    public var engine: EnginePreference {
        get { locked { _engine } }
        set { locked { _engine = newValue } }
    }

    /// true なら SFSpeechRecognizer を端末内だけで動かす(対応している言語のみ)。
    public var preferOnDevice: Bool {
        get { locked { _preferOnDevice } }
        set { locked { _preferOnDevice = newValue } }
    }

    /// 無音での文の区切り方(既定は 0.8 秒)。次の聞き取り開始から反映される。
    public var segmenterConfiguration: SilenceSegmenter.Configuration {
        get { locked { _segmenterConfiguration } }
        set { locked { _segmenterConfiguration = newValue } }
    }

    public var arbiter: LanguageArbiter {
        get { locked { _arbiter } }
        set { locked { _arbiter = newValue } }
    }

    public init(
        engine: EnginePreference = .automatic,
        preferOnDevice: Bool = true,
        segmenterConfiguration: SilenceSegmenter.Configuration = SilenceSegmenter.Configuration(),
        arbiter: LanguageArbiter = .standard
    ) {
        _engine = engine
        _preferOnDevice = preferOnDevice
        _segmenterConfiguration = segmenterConfiguration
        _arbiter = arbiter
    }

    /// 音声認識の使用許可をたずねる(初回だけ確認画面が出る)。
    public static func requestAuthorization() async -> Bool {
        await AppleSpeechRecognizer.requestAuthorization()
    }

    /// candidates の言語で聞き取りを始める。空なら日本語とベトナム語の両方。
    public func transcripts(candidates: [Language]) -> AsyncThrowingStream<Transcript, Error> {
        var languages: [Language] = []
        for language in (candidates.isEmpty ? Language.allCases : candidates) where !languages.contains(language) {
            languages.append(language)
        }
        let (engine, preferOnDevice, configuration, arbiter) = locked {
            (_engine, _preferOnDevice, _segmenterConfiguration, _arbiter)
        }
        return AsyncThrowingStream { continuation in
            let session = SegmentedRecognitionSession(
                languages: languages,
                segmenterConfiguration: configuration,
                arbiter: arbiter,
                continuation: continuation,
                makeEngine: { language in
                    try await AutoLanguageRecognizer.makeEngine(for: language, preference: engine, preferOnDevice: preferOnDevice)
                }
            )
            let previous = self.locked { () -> SegmentedRecognitionSession? in
                let previous = self.session
                self.session = session
                return previous
            }
            if let previous {
                Task { await previous.stop() }
            }
            continuation.onTermination = { _ in
                Task { await session.stop() }
            }
            session.start()
        }
    }

    public func stop() async {
        let current = locked { () -> SegmentedRecognitionSession? in
            let current = session
            session = nil
            return current
        }
        await current?.stop()
    }

    /// 聞き取りを一時停止する(自分の読み上げの最中など)。マイクは動いたままだが、認識は進まなくなる。
    public func pause() async {
        locked { session }?.pause()
    }

    /// 一時停止していた聞き取りを再開する。
    public func resume() async {
        locked { session }?.resume()
    }

    /// 言語ごとに、使える認識の仕組みを選んでエンジンを作る。
    static func makeEngine(
        for language: Language,
        preference: EnginePreference,
        preferOnDevice: Bool
    ) async throws -> UtteranceEngine {
        if preference != .sfSpeech {
            if #available(iOS 26.0, macOS 26.0, *) {
                do {
                    return try await SpeechAnalyzerUtteranceEngine.make(language: language)
                } catch {
                    // 非対応の言語・言語データのダウンロード失敗など。予備の仕組みに切り替える。
                    if preference == .speechAnalyzer { throw error }
                }
            } else if preference == .speechAnalyzer {
                throw SpeechRecognitionError.speechAnalyzerUnavailable
            }
        }
        return try SFSpeechUtteranceEngine(language: language, preferOnDevice: preferOnDevice)
    }
}
#endif
