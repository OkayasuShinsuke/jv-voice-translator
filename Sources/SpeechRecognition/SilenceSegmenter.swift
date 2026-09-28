import Foundation

/// 「話し終わり(無音)」を見つけて、文を確定させるタイミングを決める係。
///
/// たとえるなら、会議の書記さんです。話し手が 0.8 秒ほど黙ったら
/// 「ここで1文おわり」と判断して、メモを清書(確定)します。
///
/// この型は Apple のフレームワークを使わない「純粋な計算だけ」の部品なので、
/// マイクが無くてもテストで動きを確かめられます。
///
/// 使い方:
/// 1. マイクの音量(デシベル)が届くたびに `observeAudioLevel(_:at:)` を呼ぶ
/// 2. 認識の途中結果(文字)が届くたびに `observePartialText(_:at:)` を呼ぶ
/// 3. どちらかが `true` を返したら「今の文を確定してよい」という合図。
///    合図を出すと中身は自動でリセットされるので、同じ文で2回 `true` になることはない。
public struct SilenceSegmenter: Sendable {
    /// 区切り方の設定。
    public struct Configuration: Sendable, Equatable {
        /// この秒数だけ「音が小さく、文字も増えない」状態が続いたら文を確定する。
        public var silenceDuration: TimeInterval
        /// これより小さい音量(dBFS)は「無音」とみなす。0 が最大で、-160 がほぼ完全な無音。
        public var silenceThresholdDecibels: Float
        /// 周りがうるさくて「無音」にならなくても、文字がこの秒数変わらなければ確定する。
        /// nil ならこの仕組みを使わない。
        public var stableTextTimeout: TimeInterval?
        /// 1つの文がこの秒数を超えたら、話し続けていても区切る(長すぎる文で翻訳が遅れないように)。
        /// nil なら上限なし。
        public var maxUtteranceDuration: TimeInterval?

        public init(
            silenceDuration: TimeInterval = 0.8,
            silenceThresholdDecibels: Float = -45,
            stableTextTimeout: TimeInterval? = 2.0,
            maxUtteranceDuration: TimeInterval? = 20
        ) {
            self.silenceDuration = silenceDuration
            self.silenceThresholdDecibels = silenceThresholdDecibels
            self.stableTextTimeout = stableTextTimeout
            self.maxUtteranceDuration = maxUtteranceDuration
        }
    }

    public let configuration: Configuration

    /// いま確定を待っている文(途中結果のいちばん新しいもの)。空なら「まだ何も話されていない」。
    public private(set) var pendingText = ""
    /// 今の文の最初の文字が届いた時刻。
    private var utteranceStart: TimeInterval?
    /// 文字が最後に変わった時刻。
    private var lastTextChange: TimeInterval = 0
    /// 最後に「無音ではない音」が聞こえた時刻。
    private var lastLoudSound: TimeInterval?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// 確定を待っている文があるか。
    public var hasPendingSpeech: Bool { !pendingText.isEmpty }

    /// マイクの音量を知らせる。`true` が返ったら文を確定する合図。
    /// - Parameters:
    ///   - decibels: 音量(dBFS)。`SilenceSegmenter.decibels(ofSamples:)` で計算できる。
    ///   - time: 時刻(秒)。単調に増える時計なら何でもよい。
    public mutating func observeAudioLevel(_ decibels: Float, at time: TimeInterval) -> Bool {
        if decibels > configuration.silenceThresholdDecibels {
            lastLoudSound = max(lastLoudSound ?? time, time)
        }
        return finalizeIfNeeded(at: time)
    }

    /// 認識の途中結果(文字)を知らせる。`true` が返ったら文を確定する合図。
    public mutating func observePartialText(_ text: String, at time: TimeInterval) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != pendingText {
            if pendingText.isEmpty { utteranceStart = time }
            pendingText = trimmed
            lastTextChange = time
        }
        return finalizeIfNeeded(at: time)
    }

    /// 音も文字も届かないときに、時間の経過だけで判定したい場合に呼ぶ。
    public mutating func tick(at time: TimeInterval) -> Bool {
        finalizeIfNeeded(at: time)
    }

    /// 今の文を捨てて、最初からやり直す。
    public mutating func reset() {
        pendingText = ""
        utteranceStart = nil
        lastTextChange = 0
    }

    /// 状態を変えずに「今確定すべきか」だけを調べる。
    public func shouldFinalize(at time: TimeInterval) -> Bool {
        guard !pendingText.isEmpty, let start = utteranceStart else { return false }
        // 「最後に何かが起きた時刻」= 文字が変わった時刻と、音が聞こえた時刻の遅いほう。
        let lastActivity = max(lastTextChange, lastLoudSound ?? lastTextChange)
        if time - lastActivity >= configuration.silenceDuration { return true }
        if let timeout = configuration.stableTextTimeout, time - lastTextChange >= timeout { return true }
        if let limit = configuration.maxUtteranceDuration, time - start >= limit { return true }
        return false
    }

    private mutating func finalizeIfNeeded(at time: TimeInterval) -> Bool {
        guard shouldFinalize(at: time) else { return false }
        reset()
        return true
    }

    // MARK: - 音量の計算

    /// 振幅(RMS、0〜1)をデシベル(dBFS)に変換する。0 以下は -160 とする。
    public static func decibels(rms: Float) -> Float {
        guard rms > 0 else { return -160 }
        return max(-160, 20 * log10(rms))
    }

    /// 音のサンプル(-1〜1 の小数の並び)から、平均的な音量(dBFS)を計算する。
    public static func decibels<S: Sequence>(ofSamples samples: S) -> Float where S.Element == Float {
        var sumOfSquares: Float = 0
        var count = 0
        for sample in samples {
            sumOfSquares += sample * sample
            count += 1
        }
        guard count > 0 else { return -160 }
        return decibels(rms: (sumOfSquares / Float(count)).squareRoot())
    }
}
