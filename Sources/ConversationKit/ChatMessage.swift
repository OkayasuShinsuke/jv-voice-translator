import Foundation
import TranslatorCore

// ワークストリーム⑥ UI(LINE風のチャット画面)。
// このファイルには Apple のフレームワーク(SwiftUI など)を一切使わない。
// 「画面に何を出すか」というデータの形だけを決めることで、Mac やパソコンの Swift でも
// テストできるようにしている(実際の見た目の絵は Apps/iOS/Chat/ の中で描く)。

/// 吹き出しをどちら側(左右)に出すか。
///
/// LINEのように、自分が話した言葉は右側、相手が話した言葉は左側に出す。
/// このアプリでは「日本語を話した人」を右、「ベトナム語を話した人」を左、と決めている。
public enum ChatSide: String, Codable, Sendable, Equatable {
    case left
    case right
}

/// 1つの吹き出しが今どの段階にあるかを表す。
///
/// - listening: まだ話している途中(認識結果が確定していない)。
/// - translating: 話し終わって、今まさに翻訳している最中。
/// - done: 翻訳が終わって、読み上げ待ち・読み上げ済み。
/// - failed: 途中で失敗した(理由をメッセージで持つ)。
public enum ChatMessageState: Codable, Sendable, Equatable {
    case listening
    case translating
    case done
    case failed(message: String)
}

/// チャット画面に出す「1つの吹き出し」のデータ。
///
/// たとえるなら、LINEのトーク画面に並ぶ1つ1つの四角い吹き出しそのもの。
/// 元の言葉(originalText)と、訳した言葉(translatedText)の両方を1つの吹き出しにまとめて持つ。
public struct ChatMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// 吹き出しを左右どちらに出すか。
    public var side: ChatSide
    /// 話した元の言葉。
    public var originalText: String
    /// 訳した言葉。まだ訳し終わっていないときは nil。
    public var translatedText: String?
    /// 話した言語。
    public var spokenLanguage: Language
    /// 読み上げに使う声(声A・声B)。
    public var voice: VoiceRole
    /// この吹き出しができた時刻。画面に「HH:mm」で出す。
    public var date: Date
    /// 今どの段階か。
    public var state: ChatMessageState

    public init(
        id: UUID = UUID(),
        side: ChatSide,
        originalText: String,
        translatedText: String? = nil,
        spokenLanguage: Language,
        voice: VoiceRole,
        date: Date = Date(),
        state: ChatMessageState
    ) {
        self.id = id
        self.side = side
        self.originalText = originalText
        self.translatedText = translatedText
        self.spokenLanguage = spokenLanguage
        self.voice = voice
        self.date = date
        self.state = state
    }

    /// 話した言語から、吹き出しをどちら側に出すかを決める。
    /// 日本語を話した人 → 右側、ベトナム語を話した人 → 左側。
    public static func side(for language: Language) -> ChatSide {
        language == .japanese ? .right : .left
    }
}
