import Foundation
import TranslatorCore

/// 会話の吹き出しを順番に並べて管理する「ノート」。
///
/// たとえるなら、LINEのトーク履歴そのもの。
/// マイクが拾った「話している途中」の文字(部分結果)から始まり、
/// 「話し終わった」「訳し終わった」と進むにつれて、同じ1つの吹き出しの中身を書き換えていく。
/// 新しい吹き出しを増やしすぎないので、画面がガタガタ増えたりしない。
///
/// 値型(struct)にしているので、SwiftUI の `@State` にそのまま入れて使える。
public struct ConversationStore: Sendable, Equatable {
    /// 古い順に並んだ吹き出しの一覧。
    public private(set) var messages: [ChatMessage] = []
    /// 保持する吹き出しの最大数。これを超えたら、いちばん古いものから消す。
    public var maxCount: Int
    /// 「今どの吹き出しが話している途中・翻訳中か」を覚えておくための印。
    private var inProgressID: UUID?

    public init(maxCount: Int = 200) {
        self.maxCount = maxCount
    }

    /// 話している途中の認識結果(部分結果)で、吹き出しを作る・更新する。
    ///
    /// 何度呼んでも、話し終わるまでは同じ1つの吹き出しの文字が書き換わるだけで、
    /// 吹き出しが増えていくことはない。
    public mutating func updatePartial(_ transcript: Transcript) {
        let side = ChatMessage.side(for: transcript.language)
        if let index = indexOfInProgress() {
            messages[index].originalText = transcript.text
            messages[index].spokenLanguage = transcript.language
            messages[index].side = side
            messages[index].voice = VoiceRole.forSpoken(transcript.language)
            messages[index].state = .listening
        } else {
            let message = ChatMessage(
                side: side,
                originalText: transcript.text,
                spokenLanguage: transcript.language,
                voice: VoiceRole.forSpoken(transcript.language),
                state: .listening)
            inProgressID = message.id
            append(message)
        }
    }

    /// 話し終わった(確定した)ときに呼ぶ。吹き出しを「翻訳中」の見た目に変える。
    public mutating func finalize(_ transcript: Transcript) {
        let side = ChatMessage.side(for: transcript.language)
        if let index = indexOfInProgress() {
            messages[index].originalText = transcript.text
            messages[index].spokenLanguage = transcript.language
            messages[index].side = side
            messages[index].voice = VoiceRole.forSpoken(transcript.language)
            messages[index].state = .translating
        } else {
            let message = ChatMessage(
                side: side,
                originalText: transcript.text,
                spokenLanguage: transcript.language,
                voice: VoiceRole.forSpoken(transcript.language),
                state: .translating)
            inProgressID = message.id
            append(message)
        }
    }

    /// 翻訳が文ごとに進んでいる途中で呼ぶ(1文目ができた時点など)。
    /// 「翻訳中」の吹き出しの訳の部分だけを、その時点までのつながった訳で書き換える。
    /// 今「翻訳中」の吹き出しが無ければ何もしない(finalize より前に呼ばれた等、想定外の順番を無視する)。
    public mutating func updateTranslationProgress(_ translatedTextSoFar: String) {
        guard let index = indexOfInProgress() else { return }
        messages[index].translatedText = translatedTextSoFar
    }

    /// 翻訳が終わったときに呼ぶ。今「話している途中・翻訳中」の吹き出しがあればそれを完成させ、
    /// 無ければ(部分結果を経ずにいきなり結果が来た場合)新しい吹き出しを追加する。
    public mutating func complete(with event: TranslationEvent) {
        let side = ChatMessage.side(for: event.source.language)
        if let index = indexOfInProgress() {
            messages[index].originalText = event.source.text
            messages[index].translatedText = event.translatedText
            messages[index].spokenLanguage = event.source.language
            messages[index].voice = event.voice
            messages[index].side = side
            messages[index].state = .done
            inProgressID = nil
        } else {
            let message = ChatMessage(
                side: side,
                originalText: event.source.text,
                translatedText: event.translatedText,
                spokenLanguage: event.source.language,
                voice: event.voice,
                state: .done)
            append(message)
        }
    }

    /// 途中で失敗したときに呼ぶ。
    public mutating func fail(_ errorMessage: String, transcript: Transcript? = nil) {
        if let index = indexOfInProgress() {
            if let transcript {
                messages[index].originalText = transcript.text
                messages[index].spokenLanguage = transcript.language
                messages[index].side = ChatMessage.side(for: transcript.language)
            }
            messages[index].state = .failed(message: errorMessage)
            inProgressID = nil
        } else if let transcript {
            let message = ChatMessage(
                side: ChatMessage.side(for: transcript.language),
                originalText: transcript.text,
                spokenLanguage: transcript.language,
                voice: VoiceRole.forSpoken(transcript.language),
                state: .failed(message: errorMessage))
            append(message)
        }
    }

    /// 会話をすべて消して、まっさらに戻す。
    public mutating func clear() {
        messages.removeAll()
        inProgressID = nil
    }

    private func indexOfInProgress() -> Int? {
        guard let id = inProgressID else { return nil }
        return messages.firstIndex { $0.id == id }
    }

    /// 吹き出しを末尾に追加し、上限を超えたら古いものから消す。
    private mutating func append(_ message: ChatMessage) {
        messages.append(message)
        guard maxCount > 0 else { return }
        while messages.count > maxCount {
            let removed = messages.removeFirst()
            if removed.id == inProgressID {
                inProgressID = nil
            }
        }
    }
}
