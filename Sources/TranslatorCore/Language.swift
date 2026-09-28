import Foundation

/// このアプリが扱う言語。今は日本語とベトナム語の2つだけ。
public enum Language: String, Codable, Sendable, CaseIterable {
    case japanese = "ja-JP"
    case vietnamese = "vi-VN"

    /// 翻訳先の言語(日本語ならベトナム語、ベトナム語なら日本語)。
    public var counterpart: Language {
        switch self {
        case .japanese: return .vietnamese
        case .vietnamese: return .japanese
        }
    }

    /// BCP-47 の言語コード(例: "ja")。
    public var languageCode: String {
        String(rawValue.prefix(2))
    }

    /// 文を1つにつなげるときの区切り。日本語は詰めて書き、ベトナム語は単語の間に空白が要るので空白でつなぐ。
    public var sentenceJoiner: String {
        self == .japanese ? "" : " "
    }
}

/// 読み上げに使う声。
/// 声A = 日本語を聞いてベトナム語で話す声、声B = ベトナム語を聞いて日本語で話す声。
public enum VoiceRole: String, Codable, Sendable {
    case a
    case b

    /// 「話された言語」から、どちらの声で返すかを決める。
    public static func forSpoken(_ language: Language) -> VoiceRole {
        language == .japanese ? .a : .b
    }
}
