// ワークストリーム① 音声認識:SFSpeechRecognizer 版(iOS 10 からある、実績のある仕組み)。
// iOS 26 の新しい SpeechAnalyzer が使えないときの「予備」としても使う。
#if canImport(Speech) && canImport(AVFoundation)
import AVFoundation
import Foundation
import Speech
import TranslatorCore

/// SFSpeechRecognizer を使った認識器。
///
/// - candidates に1言語を渡すと、その言語だけで聞き取る。
/// - 日本語とベトナム語の両方を渡すと、2つの認識器に同じ音声を聞かせて、
///   LanguageArbiter が文ごとに良いほうを選ぶ(自動言語判定)。
/// - 0.8 秒ほど黙ると(SilenceSegmenter)、その文を isFinal=true で1回だけ流す。
public final class AppleSpeechRecognizer: PausableSpeechRecognizing, @unchecked Sendable {
    private let base: AutoLanguageRecognizer

    /// true なら端末内だけで認識する(通信なし・無料)。対応していない言語では自動で false 扱い。
    public var preferOnDevice: Bool {
        get { base.preferOnDevice }
        set { base.preferOnDevice = newValue }
    }

    public init(
        preferOnDevice: Bool = true,
        segmenterConfiguration: SilenceSegmenter.Configuration = SilenceSegmenter.Configuration(),
        arbiter: LanguageArbiter = .standard
    ) {
        base = AutoLanguageRecognizer(
            engine: .sfSpeech,
            preferOnDevice: preferOnDevice,
            segmenterConfiguration: segmenterConfiguration,
            arbiter: arbiter
        )
    }

    /// 音声認識の使用許可をたずねる(初回だけ確認画面が出る)。
    public static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public func transcripts(candidates: [Language]) -> AsyncThrowingStream<Transcript, Error> {
        base.transcripts(candidates: candidates)
    }

    public func stop() async {
        await base.stop()
    }

    public func pause() async {
        await base.pause()
    }

    public func resume() async {
        await base.resume()
    }
}

/// SFSpeechRecognizer で1言語を聞き取るエンジン。
///
/// 文を区切るたびに「認識の依頼(request/task)」を新しく作り直す。
/// 古い依頼には「音はここまで」と伝え(endAudio)、確信度つきの最終結果を少しだけ待つ。
final class SFSpeechUtteranceEngine: UtteranceEngine, @unchecked Sendable {
    /// 1つの認識の依頼(1文ぶん、または1文の途中まで)。
    private final class Slot {
        let request: SFSpeechAudioBufferRecognitionRequest
        let startedAt: TimeInterval
        var task: SFSpeechRecognitionTask?
        var latest = UtteranceSnapshot.empty(0)
        var isDone = false
        var waiters: [CheckedContinuation<Void, Never>] = []

        init(request: SFSpeechAudioBufferRecognitionRequest, startedAt: TimeInterval) {
            self.request = request
            self.startedAt = startedAt
        }
    }

    let language: Language
    private let recognizer: SFSpeechRecognizer
    private let preferOnDevice: Bool
    /// 区切ったあと、最終結果をどれだけ待つか(秒)。長いと正確・短いと速い。
    private let finalizationTimeout: TimeInterval

    private let lock = NSLock()
    private var active: Slot?
    /// 1文の途中で依頼が勝手に終わったとき(1分の上限など)の、それまでの文字。
    private var committedTexts: [String] = []
    private var committedConfidences: [Double?] = []
    private var utteranceIndex = 0
    private var stopped = false
    private var quickFailures = 0
    private var onUpdate: (@Sendable (UtteranceSnapshot) -> Void)?
    private var onError: (@Sendable (Error) -> Void)?

    init(language: Language, preferOnDevice: Bool, finalizationTimeout: TimeInterval = 0.6) throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue)),
              recognizer.isAvailable else {
            throw SpeechRecognitionError.unsupportedLanguage(language)
        }
        self.language = language
        self.recognizer = recognizer
        self.preferOnDevice = preferOnDevice
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
        locked {
            self.onUpdate = onUpdate
            self.onError = onError
        }
        let slot = makeSlot()
        locked { active = slot }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let request = locked { active?.request }
        request?.append(buffer)
    }

    func cutUtterance(startNext: Bool) -> @Sendable () async -> UtteranceSnapshot {
        // 次の文の依頼を先に作っておき、音を1つも取りこぼさないように入れ替える。
        let next = startNext ? makeSlot() : nil
        let (old, texts, confidences) = locked { () -> (Slot?, [String], [Double?]) in
            let old = active
            let texts = committedTexts
            let confidences = committedConfidences
            active = stopped ? nil : next
            committedTexts = []
            committedConfidences = []
            utteranceIndex += 1
            return (old, texts, confidences)
        }
        if isStopped(), let next { next.task?.cancel() }
        old?.request.endAudio()
        let language = self.language
        let timeout = finalizationTimeout
        return { [self] in
            var allTexts = texts
            var allConfidences = confidences
            if let old {
                await waitAtMost(timeout) { await self.waitUntilDone(old) }
                let last = self.locked { old.latest }
                allTexts.append(last.text)
                allConfidences.append(last.confidence)
                self.markDone(old, cancel: true)
            }
            return UtteranceSnapshot(
                text: language.join(allTexts),
                confidence: averageConfidence(allConfidences),
                utteranceIndex: 0
            )
        }
    }

    func stop() async {
        let slot = locked { () -> Slot? in
            stopped = true
            let slot = active
            active = nil
            return slot
        }
        if let slot { markDone(slot, cancel: true) }
    }

    private func isStopped() -> Bool {
        locked { stopped }
    }

    // MARK: - 依頼(Slot)の管理

    private func makeSlot() -> Slot {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        let slot = Slot(request: request, startedAt: ProcessInfo.processInfo.systemUptime)
        let task = recognizer.recognitionTask(with: request) { [weak self, weak slot] result, error in
            guard let self, let slot else { return }
            if let result {
                self.slot(slot, didReceive: result)
            }
            if error != nil || result?.isFinal == true {
                self.slotDidEnd(slot)
            }
        }
        locked { slot.task = task }
        return slot
    }

    private func slot(_ slot: Slot, didReceive result: SFSpeechRecognitionResult) {
        let best = result.bestTranscription
        // 途中結果の確信度はいつも 0 なので、0 だけなら「不明(nil)」とする。
        let confidences = best.segments.map { Double($0.confidence) }
        let confidence: Double? = confidences.contains(where: { $0 > 0 })
            ? confidences.reduce(0, +) / Double(confidences.count)
            : nil
        let update = locked { () -> (UtteranceSnapshot, (@Sendable (UtteranceSnapshot) -> Void)?)? in
            slot.latest = UtteranceSnapshot(text: best.formattedString, confidence: confidence, utteranceIndex: utteranceIndex)
            if !best.formattedString.isEmpty { quickFailures = 0 }
            // 今の文の依頼からの知らせだけを外に伝える。
            guard active === slot else { return nil }
            let text = language.join(committedTexts + [best.formattedString])
            let merged = UtteranceSnapshot(
                text: text,
                confidence: averageConfidence(committedConfidences + [confidence]),
                utteranceIndex: utteranceIndex
            )
            return (merged, onUpdate)
        }
        if let update, let callback = update.1 {
            callback(update.0)
        }
    }

    /// 依頼が終わった(最終結果が出た、またはエラー)。
    private func slotDidEnd(_ slot: Slot) {
        let now = ProcessInfo.processInfo.systemUptime
        // 区切っていないのに依頼が勝手に終わった場合(1分の上限・無音が長すぎた等)は、
        // それまでの文字を取っておき、新しい依頼で聞き取りを続ける。
        let restart = locked { () -> Bool in
            guard active === slot, !stopped else { return false }
            committedTexts.append(slot.latest.text)
            committedConfidences.append(slot.latest.confidence)
            if slot.latest.text.isEmpty && now - slot.startedAt < 0.5 {
                quickFailures += 1
            } else {
                quickFailures = 0
            }
            active = nil
            return true
        }
        markDone(slot, cancel: false)
        guard restart else { return }

        let failures = locked { quickFailures }
        if failures >= 5 {
            let callback = locked { onError }
            callback?(SpeechRecognitionError.repeatedFailures(language))
            return
        }
        let next = makeSlot()
        let replaced = locked { () -> Bool in
            guard active == nil, !stopped else { return false }
            active = next
            return true
        }
        if !replaced { next.task?.cancel() }
    }

    private func waitUntilDone(_ slot: Slot) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyDone = locked { () -> Bool in
                if slot.isDone { return true }
                slot.waiters.append(continuation)
                return false
            }
            if alreadyDone { continuation.resume() }
        }
    }

    private func markDone(_ slot: Slot, cancel: Bool) {
        let (waiters, task) = locked { () -> ([CheckedContinuation<Void, Never>], SFSpeechRecognitionTask?) in
            let waiters = slot.waiters
            slot.waiters = []
            slot.isDone = true
            return (waiters, slot.task)
        }
        for waiter in waiters { waiter.resume() }
        if cancel { task?.cancel() }
    }
}
#endif
