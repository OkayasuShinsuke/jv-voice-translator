import Foundation

/// 長文を文ごとに区切る。長い文章を一度に訳すより、文単位で訳して先に話し始める方が「速く感じる」。
public enum SentenceSplitter {
    /// 日本語の「。!?」、ベトナム語(英字系)の「. ! ?」、改行で区切る。区切り記号は前の文に残す。
    ///
    /// 気をつけていること:
    /// - 小数点(例: "35.5度です。")の "." は文の区切りではないので、区切らない。
    ///   たとえ話:体温の "35.5" を読点のたびに切ってしまうと、"35" と "5度です" のように
    ///   バラバラに訳されてしまう。数字と数字の間の "." だけは特別に無視する。
    /// - 区切り記号のすぐ後に閉じカッコ・閉じ引用符(」』"'）))が続く場合は、そこまで前の文に含める。
    ///   たとえ話:「彼は「はい。」と言った」のような文で、"。" のすぐ後の "」" を置き去りにしない。
    public static func split(_ text: String) -> [String] {
        let terminators: Set<Character> = ["。", "!", "?", "!", "?", ".", "\n"]
        let trailingClosers: Set<Character> = ["」", "』", "”", "\"", "'", "’", ")", ")"]
        let characters = Array(text)
        var sentences: [String] = []
        var current = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            current.append(character)
            if terminators.contains(character) {
                if character == "." && isDecimalPoint(characters, at: index) {
                    // 数字と数字にはさまれた "." は小数点なので、区切らずに次の文字へ進む。
                    index += 1
                    continue
                }
                // 区切り記号のすぐ後に続く閉じカッコ・閉じ引用符も、前の文に含めてしまう。
                var lookahead = index + 1
                while lookahead < characters.count && trailingClosers.contains(characters[lookahead]) {
                    current.append(characters[lookahead])
                    lookahead += 1
                }
                appendTrimmed(current, to: &sentences)
                current = ""
                index = lookahead
                continue
            }
            index += 1
        }
        appendTrimmed(current, to: &sentences)
        return sentences
    }

    /// characters[index] が "." で、その前後が数字(0-9)なら小数点とみなす。
    private static func isDecimalPoint(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0, index + 1 < characters.count else { return false }
        return characters[index - 1].isASCIIDigit && characters[index + 1].isASCIIDigit
    }

    private static func appendTrimmed(_ sentence: String, to sentences: inout [String]) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { sentences.append(trimmed) }
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
