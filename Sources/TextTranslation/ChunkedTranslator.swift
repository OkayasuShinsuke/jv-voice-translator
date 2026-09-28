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

    /// 長文を文ごとに訳し、訳せた文から順番に1つずつ流す(ストリーム)。
    /// たとえ話:全部の料理ができるのを待たずに、できた皿から順にテーブルへ運ぶイメージ。
    /// 1文目の訳ができた時点で読み上げを始められるので、長文でも「待たされた感じ」が減る。
    ///
    /// 使い方:
    /// ```swift
    /// for try await sentence in translator.translateStream(text, from: .japanese, to: .vietnamese) {
    ///     try await speaker.speak(sentence, language: .vietnamese, voice: .a)
    /// }
    /// ```
    /// - 文は元の順番どおりに流れる。
    /// - 途中で翻訳に失敗したら、そのエラーでストリームが終わる。
    /// - 受け取る側がループを途中で抜けると、残りの翻訳は取り消される。
    public func translateStream(_ text: String, from source: Language, to target: Language) -> AsyncThrowingStream<String, Error> {
        let sentences = SentenceSplitter.split(text)
        let base = self.base
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for sentence in sentences {
                        // 受け取る側がもういらないと言ったら、ここで止める。
                        try Task.checkCancellation()
                        let translated = try await base.translate(sentence, from: source, to: target)
                        continuation.yield(translated)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
