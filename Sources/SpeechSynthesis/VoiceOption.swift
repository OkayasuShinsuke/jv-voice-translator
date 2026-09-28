// 「選べる声」1つぶんの情報。AVFoundation の型をそのまま使うとテストしにくいので、
// 画面やテストではこの素の Swift の型を使い、AVFoundation からの変換は VoiceCatalog が担当する。

/// 声の品質。数字が大きいほど自然に聞こえる。
public enum VoiceQuality: Int, Sendable, Codable, Comparable, CaseIterable {
    case standard = 1
    case enhanced = 2
    case premium = 3

    /// 画面に出すラベル。
    public var label: String {
        switch self {
        case .standard: return "標準"
        case .enhanced: return "Enhanced"
        case .premium: return "Premium"
        }
    }

    public static func < (lhs: VoiceQuality, rhs: VoiceQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 端末に入っている声1つぶん。
public struct VoiceOption: Sendable, Hashable, Identifiable, Codable {
    /// 声の ID。VoiceProfile.voiceIdentifier に保存する値。
    public var identifier: String
    /// 声の名前(例: "Kyoko")。
    public var name: String
    /// 言語コード(例: "ja-JP")。
    public var languageCode: String
    public var quality: VoiceQuality

    public var id: String { identifier }

    /// 画面に出す文字(例: "Kyoko(Premium)")。
    public var displayName: String { "\(name)(\(quality.label))" }

    public init(identifier: String, name: String, languageCode: String, quality: VoiceQuality) {
        self.identifier = identifier
        self.name = name
        self.languageCode = languageCode
        self.quality = quality
    }

    /// 高品質な声が上に来るように並べる(同じ品質なら名前順)。
    public static func sortedByQuality(_ options: [VoiceOption]) -> [VoiceOption] {
        options.sorted { lhs, rhs in
            if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.identifier < rhs.identifier
        }
    }
}
