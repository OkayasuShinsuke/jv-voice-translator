import TranslatorCore

// ワークストリーム⑥ UI:VoiceOver(画面を読み上げてくれる、iPhoneのアクセシビリティ機能)向けの
// 説明文を作る係。SwiftUI を使わない「ただの文字列づくり」なので、Mac やパソコンの Swift でも
// テストできる(見た目に貼り付けるだけの場所は Apps/iOS/Chat/ChatBubble.swift)。
//
// たとえ話:吹き出しの中には「元の言葉」「翻訳中…」「訳した言葉」のように、複数の Text が
// バラバラに並んでいる。VoiceOver は何も指定しないと、それを1つずつ別々に読み上げてしまい、
// 目が見えない・見えにくい利用者には聞き取りづらい。ここでは吹き出し1つぶんを
// 「ひとまとまりの説明」として1文にまとめる。
public extension ChatMessage {
    /// VoiceOver で読み上げるための、吹き出し1つぶんの説明文。
    var accessibilitySummary: String {
        let language = spokenLanguage.accessibilityName
        switch state {
        case .listening:
            let text = originalText.isEmpty ? "まだ何も聞き取れていません" : originalText
            return "\(language)を聞き取り中。\(text)"
        case .translating:
            return "\(language): \(originalText)。翻訳中です。"
        case .done:
            let translated = translatedText ?? ""
            return "\(language): \(originalText)。訳: \(translated)。タップすると読み上げます。"
        case .failed(let errorMessage):
            return "\(language): \(originalText)。うまく訳せませんでした。理由: \(errorMessage)"
        }
    }
}

private extension Language {
    /// VoiceOver で読み上げるための、言語の日本語名。
    var accessibilityName: String {
        switch self {
        case .japanese: return "日本語"
        case .vietnamese: return "ベトナム語"
        }
    }
}
