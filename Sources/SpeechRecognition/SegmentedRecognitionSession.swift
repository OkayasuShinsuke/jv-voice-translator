// 音声認識の「現場監督」。マイク・言語ごとの認識エンジン・無音での区切り・言語の審判をまとめて動かす。
#if canImport(AVFoundation)
import AVFoundation
import Foundation
import TranslatorCore

// MARK: - 言語ごとの認識エンジンの共通の形

/// 認識エンジンが「今の文はここまで聞こえた」と知らせるときの中身。
struct UtteranceSnapshot: Sendable, Equatable {
    var text: String
    var confidence: Double?
    /// 何番目の文か(区切るたびに 1 増える)。古い文の知らせが遅れて届いたときに見分けるため。
    var utteranceIndex: Int

    static func empty(_ index: Int) -> UtteranceSnapshot {
        UtteranceSnapshot(text: "", confidence: nil, utteranceIndex: index)
    }
}

/// 1つの言語を聞き取るエンジン(SFSpeechRecognizer 版と SpeechAnalyzer 版がある)。
/// 文の区切りはエンジン自身ではなく、外の SilenceSegmenter が決めて `cutUtterance` で伝える。
protocol UtteranceEngine: AnyObject, Sendable {
    var language: Language { get }
    /// 聞き取りの準備をする。途中結果が変わるたびに onUpdate、止まるほどの失敗は onError で知らせる。
    /// onUpdate / onError はエンジン内部の鍵(ロック)を持たない状態で呼ぶこと。
    func start(
        onUpdate: @escaping @Sendable (UtteranceSnapshot) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws
    /// マイクの音を渡す(音声スレッドから呼ばれる)。
    func append(_ buffer: AVAudioPCMBuffer)
    /// 「ここで1文おわり」。この後に届く音は次の文として扱う。
    /// 戻り値は、今の文の最終的な文字を待って返す関数(少し待つとより正確な結果になるため)。
    /// startNext が false なら次の文の準備はしない(止めるとき用)。
    func cutUtterance(startNext: Bool) -> @Sendable () async -> UtteranceSnapshot
    func stop() async
}

extension Language {
    /// 文字をつなぐときの区切り。日本語は空白なし、ベトナム語は空白。
    var textSeparator: String { self == .japanese ? "" : " " }

    /// 空の部分を除いてつなぐ。
    func join(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: textSeparator)
    }
}

/// 確信度の平均(nil は除く)。全部 nil なら nil。
func averageConfidence(_ values: [Double?]) -> Double? {
    let known = values.compactMap { $0 }
    guard !known.isEmpty else { return nil }
    return known.reduce(0, +) / Double(known.count)
}

/// 「1回だけ」を守るための小さな旗。タイムアウトと本来の完了の、先に来たほうだけを通す。
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// 最初の1回だけ true を返す。
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// 「処理 A が終わる」か「timeout 秒たつ」の早いほうまで待つ。
func waitAtMost(_ timeout: TimeInterval, for work: @escaping @Sendable () async -> Void) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let once = OnceFlag()
        Task {
            await work()
            if once.claim() { continuation.resume() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if once.claim() { continuation.resume() }
        }
    }
}

// MARK: - マイク

/// マイクの音を受け取り、音の塊(バッファ)と音量を知らせる。
/// 1つのマイクの音を、日本語用とベトナム語用の両方のエンジンに配るために使う。
final class MicrophoneSource: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var isRunning = false

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer, Float) -> Void) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            onBuffer(buffer, MicrophoneSource.level(of: buffer))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        lock.lock()
        isRunning = true
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let wasRunning = isRunning
        isRunning = false
        lock.unlock()
        guard wasRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }

    /// バッファの音量(dBFS)。最初のチャンネルだけを見る。
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return -160 }
        let samples = UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))
        return SilenceSegmenter.decibels(ofSamples: samples)
    }
}

// MARK: - 現場監督

/// 1回の「聞き取り開始〜停止」を受け持つ。
///
/// 流れ:
/// 1. 候補の言語ごとにエンジンを作る(日本語とベトナム語なら2つ)
/// 2. マイクの音を全エンジンに配り、音量を SilenceSegmenter に知らせる
/// 3. 途中結果は LanguageArbiter で良いほうを選んで isFinal=false で流す
/// 4. SilenceSegmenter が「区切り」と言ったら全エンジンの文を締め切り、
///    審判が選んだ1つだけを isFinal=true で流す(1文につき確定は必ず1回)
final class SegmentedRecognitionSession: @unchecked Sendable {
    typealias EngineFactory = @Sendable (Language) async throws -> UtteranceEngine

    private enum State { case preparing, running, stopped }

    private let languages: [Language]
    private let makeEngine: EngineFactory
    private let arbiter: LanguageArbiter
    private let continuation: AsyncThrowingStream<Transcript, Error>.Continuation
    private let microphone = MicrophoneSource()

    private let lock = NSLock()
    private var state = State.preparing
    private var segmenter: SilenceSegmenter
    private var engines: [UtteranceEngine] = []
    private var latest: [Language: UtteranceSnapshot] = [:]
    private var utteranceIndex = 0
    private var lastPartial: Transcript?
    private var emitChain: Task<Void, Never>?

    init(
        languages: [Language],
        segmenterConfiguration: SilenceSegmenter.Configuration,
        arbiter: LanguageArbiter,
        continuation: AsyncThrowingStream<Transcript, Error>.Continuation,
        makeEngine: @escaping EngineFactory
    ) {
        self.languages = languages
        self.segmenter = SilenceSegmenter(configuration: segmenterConfiguration)
        self.arbiter = arbiter
        self.continuation = continuation
        self.makeEngine = makeEngine
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func start() {
        Task { await self.run() }
    }

    private func run() async {
        var made: [UtteranceEngine] = []
        var firstError: Error?
        for language in languages {
            do {
                let engine = try await makeEngine(language)
                try await engine.start(
                    onUpdate: { [weak self] snapshot in self?.engineDidUpdate(language, snapshot) },
                    onError: { [weak self] error in
                        guard let self else { return }
                        Task { await self.finish(error: error) }
                    }
                )
                made.append(engine)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        guard !made.isEmpty else {
            await finish(error: firstError ?? SpeechRecognitionError.noAvailableEngine)
            return
        }
        let ready = locked { () -> Bool in
            guard state == .preparing else { return false }
            engines = made
            state = .running
            return true
        }
        guard ready else {
            // 準備中に止められた。
            for engine in made { await engine.stop() }
            return
        }
        do {
            try microphone.start { [weak self] buffer, level in
                self?.didCapture(buffer, level: level)
            }
        } catch {
            await finish(error: error)
        }
    }

    // 音声スレッドから呼ばれる。
    private func didCapture(_ buffer: AVAudioPCMBuffer, level: Float) {
        let targets = locked { () -> [UtteranceEngine] in
            guard state == .running else { return [] }
            if segmenter.observeAudioLevel(level, at: Self.now()) {
                cutLocked(startNext: true)
            }
            return engines
        }
        for engine in targets { engine.append(buffer) }
    }

    private func engineDidUpdate(_ language: Language, _ snapshot: UtteranceSnapshot) {
        let partial = locked { () -> Transcript? in
            // 締め切った後に遅れて届いた古い文の知らせは無視する。
            guard state == .running, snapshot.utteranceIndex == utteranceIndex else { return nil }
            latest[language] = snapshot
            let combined = languages.compactMap { latest[$0]?.text }.joined(separator: "\n")
            if segmenter.observePartialText(combined, at: Self.now()) {
                cutLocked(startNext: true)
                return nil
            }
            guard let best = arbiter.choose(currentCandidates()) else { return nil }
            let transcript = Transcript(text: best.text, language: best.language, isFinal: false, confidence: best.confidence)
            guard transcript != lastPartial else { return nil }
            lastPartial = transcript
            return transcript
        }
        if let partial { continuation.yield(partial) }
    }

    private func currentCandidates() -> [RecognitionCandidate] {
        languages.compactMap { language in
            latest[language].map { RecognitionCandidate(language: language, text: $0.text, confidence: $0.confidence) }
        }
    }

    /// 今の文を締め切る。lock を持った状態で呼ぶこと。
    private func cutLocked(startNext: Bool) {
        let handles = engines.map { engine in (engine.language, engine.cutUtterance(startNext: startNext)) }
        utteranceIndex += 1
        latest = [:]
        lastPartial = nil
        segmenter.reset()
        let previous = emitChain
        let arbiter = self.arbiter
        let continuation = self.continuation
        // 確定は順番どおりに流したいので、前の確定が終わるのを待ってから流す。
        emitChain = Task {
            await previous?.value
            var candidates: [RecognitionCandidate] = []
            for (language, handle) in handles {
                let snapshot = await handle()
                candidates.append(RecognitionCandidate(language: language, text: snapshot.text, confidence: snapshot.confidence))
            }
            guard let chosen = arbiter.choose(candidates) else { return }
            continuation.yield(Transcript(
                text: chosen.text,
                language: chosen.language,
                isFinal: true,
                confidence: chosen.confidence
            ))
        }
    }

    /// 止める。話しかけの文が残っていれば、最後に確定してから止める。
    func stop() async {
        await finish(error: nil)
    }

    private func finish(error: Error?) async {
        let result = locked { () -> (engines: [UtteranceEngine], chain: Task<Void, Never>?)? in
            guard state != .stopped else { return nil }
            if state == .running && error == nil && latest.values.contains(where: { !$0.text.isEmpty }) {
                cutLocked(startNext: false)
            }
            state = .stopped
            let current = engines
            engines = []
            return (current, emitChain)
        }
        guard let result else { return }
        microphone.stop()
        await result.chain?.value
        for engine in result.engines { await engine.stop() }
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}
#endif
