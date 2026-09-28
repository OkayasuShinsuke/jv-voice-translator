// 声A・声Bの「設定値」だけを表す、Apple のフレームワークに頼らない部品。
// AVFoundation が無い環境(Linux など)でもビルドとテストができるよう、#if の外に置いている。
import TranslatorCore

/// 声A・声Bの設定。voiceIdentifier を nil にすると、その言語でいちばん高品質な声を自動で選ぶ。
///
/// Codable(JSON に変換できる)なので、そのまま UserDefaults に保存できる。
public struct VoiceProfile: Sendable, Equatable, Codable {
    /// 使う声の ID(例: "com.apple.voice.premium.ja-JP.Kyoko")。nil なら自動で選ぶ。
    public var voiceIdentifier: String?
    /// 話す速さ。0.0(とても遅い)〜1.0(とても速い)。0.5 がふつう。
    public var rate: Float
    /// 声の高さ。0.5(低い)〜2.0(高い)。1.0 がふつう。
    public var pitch: Float

    /// ふつうの速さ。AVSpeechUtteranceDefaultSpeechRate と同じ 0.5。
    public static let defaultRate: Float = 0.5
    /// ふつうの高さ。
    public static let defaultPitch: Float = 1.0
    /// 設定画面のスライダーで動かせる速さの範囲(聞き取りやすい範囲にしぼっている)。
    public static let rateRange: ClosedRange<Float> = 0.2...0.8
    /// 設定画面のスライダーで動かせる高さの範囲(AVSpeechUtterance が受け付ける範囲)。
    public static let pitchRange: ClosedRange<Float> = 0.5...2.0

    public init(voiceIdentifier: String? = nil, rate: Float = VoiceProfile.defaultRate, pitch: Float = VoiceProfile.defaultPitch) {
        self.voiceIdentifier = voiceIdentifier
        self.rate = rate
        self.pitch = pitch
    }

    /// 速さ・高さを範囲内におさめたコピー。壊れた保存データから読んだときの安全策。
    public func clamped() -> VoiceProfile {
        VoiceProfile(
            voiceIdentifier: voiceIdentifier,
            rate: min(max(rate, Self.rateRange.lowerBound), Self.rateRange.upperBound),
            pitch: min(max(pitch, Self.pitchRange.lowerBound), Self.pitchRange.upperBound))
    }
}

// 声A・声Bにまつわる、音声合成で使う情報。
public extension VoiceRole {
    /// 設定画面などで順番に並べるための一覧。
    static var allRoles: [VoiceRole] { [.a, .b] }

    /// この声が「話す」言語。声A = ベトナム語で話す、声B = 日本語で話す。
    var synthesisLanguage: Language {
        switch self {
        case .a: return .vietnamese
        case .b: return .japanese
        }
    }

    /// 画面に出す名前。
    var displayName: String {
        switch self {
        case .a: return "声A(ベトナム語で話す)"
        case .b: return "声B(日本語で話す)"
        }
    }

    /// 試し聞きで読み上げる短い例文。
    var sampleText: String {
        switch self {
        case .a: return "Xin chào, rất vui được gặp bạn. Hôm nay trời đẹp quá."
        case .b: return "こんにちは。お会いできてうれしいです。今日はいい天気ですね。"
        }
    }
}
