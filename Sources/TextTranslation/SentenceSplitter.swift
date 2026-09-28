import Foundation

/// 長文を文ごとに区切る。長い文章を一度に訳すより、文単位で訳して先に話し始める方が「速く感じる」。
public enum SentenceSplitter {
    /// 日本語の「。!?」、ベトナム語(英字系)の「. ! ?」、改行で区切る。区切り記号は前の文に残す。
    public static func split(_ text: String) -> [String] {
        let terminators: Set<Character> = ["。", "!", "?", "!", "?", ".", "\n"]
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if terminators.contains(character) {
                appendTrimmed(current, to: &sentences)
                current = ""
            }
        }
        appendTrimmed(current, to: &sentences)
        return sentences
    }

    private static func appendTrimmed(_ sentence: String, to sentences: inout [String]) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { sentences.append(trimmed) }
    }
}
