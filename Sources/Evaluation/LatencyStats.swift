import Foundation

/// 遅延(秒)の統計。
/// 平均だけだと「たまにすごく遅い」が隠れてしまうので、中央値(p50)と p90 も見る。
/// - p50:半分のサンプルはこれより速い(ふつうの体感)
/// - p90:9割のサンプルはこれより速い(遅いときの体感)
public struct LatencyStats: Codable, Sendable, Equatable {
    public var count: Int
    public var mean: TimeInterval
    public var p50: TimeInterval
    public var p90: TimeInterval
    public var minimum: TimeInterval
    public var maximum: TimeInterval

    public init(count: Int, mean: TimeInterval, p50: TimeInterval, p90: TimeInterval, minimum: TimeInterval, maximum: TimeInterval) {
        self.count = count
        self.mean = mean
        self.p50 = p50
        self.p90 = p90
        self.minimum = minimum
        self.maximum = maximum
    }

    /// 遅延の一覧から統計を作る。空なら nil。
    public init?(_ values: [TimeInterval]) {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        self.count = sorted.count
        self.mean = sorted.reduce(0, +) / Double(sorted.count)
        self.p50 = LatencyStats.percentile(sorted: sorted, 50)
        self.p90 = LatencyStats.percentile(sorted: sorted, 90)
        self.minimum = sorted[0]
        self.maximum = sorted[sorted.count - 1]
    }

    /// パーセンタイル(0〜100)。小さい順に並べた配列を渡す。
    /// となり合う2つの値の間を直線で補う方式(表計算ソフトの PERCENTILE.INC と同じ)。
    /// 例:[1, 2, 3, 4] の p50 は 2.5。
    public static func percentile(sorted: [Double], _ percent: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        if sorted.count == 1 { return sorted[0] }
        let clamped = Swift.min(Swift.max(percent, 0), 100)
        let rank = clamped / 100 * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        let fraction = rank - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}
