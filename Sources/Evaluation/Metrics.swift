import Foundation

/// ワークストリーム④ 正確性の評価で使う指標。
public enum Metrics {
    /// WER(単語誤り率)。ベトナム語の音声認識に使う(空白で単語が区切られるため)。0 が完璧。
    public static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let ref = words(reference)
        let hyp = words(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(EditDistance.distance(ref, hyp)) / Double(ref.count)
    }

    /// CER(文字誤り率)。日本語の音声認識に使う(日本語は単語の区切りがないため)。0 が完璧。
    public static func characterErrorRate(reference: String, hypothesis: String) -> Double {
        let ref = characters(reference)
        let hyp = characters(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(EditDistance.distance(ref, hyp)) / Double(ref.count)
    }

    /// chrF(文字 n-gram の F スコア)。翻訳の良さを 0〜100 で表す。100 が完璧。
    /// 日本語にもベトナム語にも使え、辞書やモデル不要で計算できる。
    public static func chrF(reference: String, hypothesis: String, maxN: Int = 6, beta: Double = 2) -> Double {
        let ref = characters(reference)
        let hyp = characters(hypothesis)
        var precisions: [Double] = []
        var recalls: [Double] = []
        for n in 1...maxN {
            let refGrams = ngrams(ref, n)
            let hypGrams = ngrams(hyp, n)
            let refTotal = refGrams.values.reduce(0, +)
            let hypTotal = hypGrams.values.reduce(0, +)
            guard refTotal > 0, hypTotal > 0 else { continue }
            let matches = hypGrams.reduce(0) { $0 + min($1.value, refGrams[$1.key] ?? 0) }
            precisions.append(Double(matches) / Double(hypTotal))
            recalls.append(Double(matches) / Double(refTotal))
        }
        guard !precisions.isEmpty else { return ref == hyp ? 100 : 0 }
        let precision = precisions.reduce(0, +) / Double(precisions.count)
        let recall = recalls.reduce(0, +) / Double(recalls.count)
        guard precision + recall > 0 else { return 0 }
        let beta2 = beta * beta
        return 100 * (1 + beta2) * precision * recall / (beta2 * precision + recall)
    }

    static func words(_ text: String) -> [String] {
        normalize(text).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func characters(_ text: String) -> [Character] {
        Array(normalize(text).filter { !$0.isWhitespace })
    }

    /// 大文字小文字と句読点の違いは誤りに数えない。
    static func normalize(_ text: String) -> String {
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        let kept = text.lowercased().unicodeScalars.filter { !punctuation.contains($0) }
        return String(String.UnicodeScalarView(kept))
    }

    private static func ngrams(_ chars: [Character], _ n: Int) -> [String: Int] {
        guard chars.count >= n else { return [:] }
        var counts: [String: Int] = [:]
        for i in 0...(chars.count - n) {
            counts[String(chars[i..<(i + n)]), default: 0] += 1
        }
        return counts
    }
}
