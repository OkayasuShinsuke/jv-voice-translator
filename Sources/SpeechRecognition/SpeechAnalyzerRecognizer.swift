// ワークストリーム① 音声認識:iOS 26 の新しい SpeechAnalyzer / SpeechTranscriber 版。
// SFSpeechRecognizer より速く正確で、長い話にも強いとされる(端末内処理・無料)。
//
// ※ iOS 26 で入った新しい仕組みなので、書き方(API)が今後変わる可能性がある。
//   コンパイルエラーが出たときに直しやすいよう、このファイルだけに閉じ込めてある。
#if canImport(Speech) && canImport(AVFoundation)
import AVFoundation
import CoreMedia
import Foundation
import Speech
import TranslatorCore

/// SpeechAnalyzer(iOS 26 以降)を使う認識器。
///
/// - その言語が SpeechAnalyzer で使えないときは、自動で SFSpeechRecognizer(AppleSpeechRecognizer と同じ仕組み)に切り替える。
/// - candidates に日本語とベトナム語の両方を渡すと、自動言語判定をする。
/// - 0.8 秒ほど黙ると、その文を isFinal=true で1回だけ流す。
@available(iOS 26.0, macOS 26.0, *)
public final class SpeechAnalyzerRecognizer: SpeechRecognizing, @unchecked Sendable {
    private let base: AutoLanguageRecognizer

    public init(
        segmenterConfiguration: SilenceSegmenter.Configuration = SilenceSegmenter.Configuration(),
        arbiter: LanguageArbiter = .standard
    ) {
        base = AutoLanguageRecognizer(
            engine: .automatic,
            segmenterConfiguration: segmenterConfiguration,
            arbiter: arbiter
        )
    }

    /// その言語を SpeechAnalyzer で認識できるか(できなければ SFSpeechRecognizer が使われる)。
    public static func supports(_ language: Language) async -> Bool {
        await SpeechAnalyzerUtteranceEngine.supportedLocale(for: language) != nil
    }

    public func transcripts(candidates: [Language]) -> AsyncThrowingStream<Transcript, Error> {
        base.transcripts(candidates: candidates)
    }

    public func stop() async {
        await base.stop()
    }
}

/// SpeechAnalyzer + SpeechTranscriber で1言語を聞き取るエンジン。
///
/// SpeechTranscriber は「仮の結果(volatile)」と「確定した結果(final)」を出す。
/// 文の区切りは SilenceSegmenter が決めるので、区切った時刻より前の音の結果はその文に、
/// 後の音の結果は次の文に振り分ける(音声の時刻 = 何秒目の音か で判断する)。
@available(iOS 26.0, macOS 26.0, *)
final class SpeechAnalyzerUtteranceEngine: UtteranceEngine, @unchecked Sendable {
    /// 1文ぶんの結果をためておく箱。
    private final class UtteranceBox {
        var finals: [String] = []
        var finalConfidences: [Double?] = []
        var volatileText = ""
        var volatileConfidence: Double?

        func snapshot(language: Language, index: Int) -> UtteranceSnapshot {
            UtteranceSnapshot(
                text: language.join(finals + [volatileText]),
                confidence: averageConfidence(finalConfidences + (volatileText.isEmpty ? [] : [volatileConfidence])),
                utteranceIndex: index
            )
        }
    }

    /// 区切ったあと、最終結果が出るのを待っている文。
    private struct Closing {
        let boundary: Double
        let box: UtteranceBox
    }

    let language: Language
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let analyzerFormat: AVAudioFormat?
    private let finalizationTimeout: TimeInterval

    private let lock = NSLock()
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    /// これまでに渡した音の長さ(秒)。
    private var fedSeconds: Double = 0
    private var current = UtteranceBox()
    private var closings: [Closing] = []
    /// この時刻より前の音の結果は、もう確定済みなので捨てる。
    private var droppedBefore: Double = 0
    private var utteranceIndex = 0
    private var resultsTask: Task<Void, Never>?
    private var onUpdate: (@Sendable (UtteranceSnapshot) -> Void)?
    private var onError: (@Sendable (Error) -> Void)?

    /// その言語に対応する SpeechTranscriber のロケール。使えなければ nil。
    static func supportedLocale(for language: Language) async -> Locale? {
        guard SpeechTranscriber.isAvailable else { return nil }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.rawValue))
    }

    /// エンジンを作る。必要なら言語データをダウンロードする(無料・初回のみ)。
    static func make(language: Language, finalizationTimeout: TimeInterval = 0.6) async throws -> SpeechAnalyzerUtteranceEngine {
        guard let locale = await supportedLocale(for: language) else {
            throw SpeechRecognitionError.unsupportedLanguage(language)
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.transcriptionConfidence]
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        return SpeechAnalyzerUtteranceEngine(
            language: language,
            transcriber: transcriber,
            analyzerFormat: format,
            finalizationTimeout: finalizationTimeout
        )
    }

    private init(language: Language, transcriber: SpeechTranscriber, analyzerFormat: AVAudioFormat?, finalizationTimeout: TimeInterval) {
        self.language = language
        self.transcriber = transcriber
        self.analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzerFormat = analyzerFormat
        self.finalizationTimeout = finalizationTimeout
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func start(
        onUpdate: @escaping @Sendable (UtteranceSnapshot) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws {
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        locked {
            self.onUpdate = onUpdate
            self.onError = onError
            self.inputBuilder = builder
        }
        let transcriber = self.transcriber
        let task = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.handle(result)
                }
            } catch {
                self?.reportError(error)
            }
        }
        locked { resultsTask = task }
        try await analyzer.start(inputSequence: stream)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer) else { return }
        let builder = locked { () -> AsyncStream<AnalyzerInput>.Continuation? in
            fedSeconds += Double(converted.frameLength) / converted.format.sampleRate
            return inputBuilder
        }
        builder?.yield(AnalyzerInput(buffer: converted))
    }

    func cutUtterance(startNext: Bool) -> @Sendable () async -> UtteranceSnapshot {
        let (closing, index) = locked { () -> (Closing, Int) in
            let closing = Closing(boundary: fedSeconds, box: current)
            closings.append(closing)
            current = UtteranceBox()
            utteranceIndex += 1
            return (closing, utteranceIndex)
        }
        let analyzer = self.analyzer
        let language = self.language
        let timeout = finalizationTimeout
        return { [self] in
            // 区切った時刻までの結果を確定させ、少しだけ待つ。
            let time = CMTime(seconds: closing.boundary, preferredTimescale: 48_000)
            await waitAtMost(timeout) {
                try? await analyzer.finalize(through: time)
                // 確定結果が届くまでのわずかな時間の余裕。
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return self.locked { () -> UtteranceSnapshot in
                closings.removeAll { $0.box === closing.box }
                droppedBefore = max(droppedBefore, closing.boundary)
                return closing.box.snapshot(language: language, index: index - 1)
            }
        }
    }

    func stop() async {
        let (builder, task) = locked { () -> (AsyncStream<AnalyzerInput>.Continuation?, Task<Void, Never>?) in
            let builder = inputBuilder
            inputBuilder = nil
            let task = resultsTask
            resultsTask = nil
            return (builder, task)
        }
        builder?.finish()
        await analyzer.cancelAndFinishNow()
        task?.cancel()
    }

    private func reportError(_ error: Error) {
        let callback = locked { onError }
        callback?(error)
    }

    // MARK: - 結果の振り分け

    private func handle(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        let start = result.range.start.seconds
        let confidence = Self.confidence(of: result.text)
        let update = locked { () -> (UtteranceSnapshot, (@Sendable (UtteranceSnapshot) -> Void)?)? in
            // 少しの誤差は許す(区切りちょうどの結果は次の文に入れる)。
            let startTime = start.isFinite ? start + 0.01 : Double.infinity
            let box: UtteranceBox
            var isCurrent = false
            if let closing = closings.first(where: { startTime < $0.boundary }) {
                box = closing.box
            } else if startTime < droppedBefore {
                return nil  // もう確定して流した文の結果なので捨てる。
            } else {
                box = current
                isCurrent = true
            }
            if result.isFinal {
                box.finals.append(text)
                box.finalConfidences.append(confidence)
                box.volatileText = ""
                box.volatileConfidence = nil
            } else {
                box.volatileText = text
                box.volatileConfidence = confidence
            }
            guard isCurrent else { return nil }
            return (box.snapshot(language: language, index: utteranceIndex), onUpdate)
        }
        if let update, let callback = update.1 {
            callback(update.0)
        }
    }

    /// 結果の文字についている確信度の平均。付いていなければ nil。
    private static func confidence(of text: AttributedString) -> Double? {
        var values: [Double] = []
        for run in text.runs {
            if let value = run.transcriptionConfidence {
                values.append(value)
            }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - 音の形式の変換

    /// マイクの音(例: 48kHz)を、SpeechAnalyzer が求める形式(例: 16kHz)に変換する。
    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let outputFormat = analyzerFormat else { return buffer }
        let inputFormat = buffer.format
        if inputFormat == outputFormat { return buffer }

        let converter = locked { () -> AVAudioConverter? in
            if self.converter == nil || converterInputFormat != inputFormat {
                self.converter = AVAudioConverter(from: inputFormat, to: outputFormat)
                converterInputFormat = inputFormat
            }
            return self.converter
        }
        guard let converter else { return nil }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        let once = OnceFlag()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if once.claim() {
                inputStatus.pointee = .haveData
                return buffer
            }
            inputStatus.pointee = .noDataNow
            return nil
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
#endif
