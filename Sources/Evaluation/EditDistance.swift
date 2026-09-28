import Foundation

/// 編集距離(レーベンシュタイン距離)。
/// 「正解の列を、何回の 置換・挿入・削除 で認識結果に変えられるか」を数える。
public enum EditDistance {
    public static func distance<T: Equatable>(_ reference: [T], _ hypothesis: [T]) -> Int {
        if reference.isEmpty { return hypothesis.count }
        if hypothesis.isEmpty { return reference.count }
        var previous = Array(0...hypothesis.count)
        var current = [Int](repeating: 0, count: hypothesis.count + 1)
        for i in 1...reference.count {
            current[0] = i
            for j in 1...hypothesis.count {
                let substitution = previous[j - 1] + (reference[i - 1] == hypothesis[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[hypothesis.count]
    }
}
