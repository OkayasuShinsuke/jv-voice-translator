import Foundation
import TranslatorCore

/// 長文を文ごとに分けて、別の翻訳器(base)で訳してからつなぎ直す包み紙。
/// どの翻訳エンジンにもかぶせられるので、長文対策をエンジンと切り離して改良できる。
public struct ChunkedTranslator: Translating {
    private let base: Translating

    public init(base: Translating) {
        self.base = base
    }

    public func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        let sentences = SentenceSplitter.split(text)
        guard sentences.count > 1 else {
            return try await base.translate(text, from: source, to: target)
        }
        var results: [String] = []
        for sentence in sentences {
            results.append(try await base.translate(sentence, from: source, to: target))
        }
        // 日本語は文の間に空白を入れない。ベトナム語は空白でつなぐ。
        return results.joined(separator: target == .japanese ? "" : " ")
    }
}
