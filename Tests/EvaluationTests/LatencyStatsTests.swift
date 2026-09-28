import XCTest
@testable import Evaluation

final class LatencyStatsTests: XCTestCase {
    func testEmptyIsNil() {
        XCTAssertNil(LatencyStats([]))
    }

    func testSingleValue() throws {
        let stats = try XCTUnwrap(LatencyStats([0.2]))
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.mean, 0.2, accuracy: 1e-12)
        XCTAssertEqual(stats.p50, 0.2, accuracy: 1e-12)
        XCTAssertEqual(stats.p90, 0.2, accuracy: 1e-12)
    }

    func testMeanAndPercentiles() throws {
        // 並び順がバラバラでも、内部で小さい順に並べてから計算する。
        let stats = try XCTUnwrap(LatencyStats([4, 1, 3, 2]))
        XCTAssertEqual(stats.count, 4)
        XCTAssertEqual(stats.mean, 2.5, accuracy: 1e-12)
        XCTAssertEqual(stats.p50, 2.5, accuracy: 1e-12)   // 2 と 3 の真ん中
        XCTAssertEqual(stats.p90, 3.7, accuracy: 1e-12)   // 位置 0.9 × 3 = 2.7 → 3 + 0.7 × (4 - 3)
        XCTAssertEqual(stats.minimum, 1)
        XCTAssertEqual(stats.maximum, 4)
    }

    func testPercentileOfTenValues() {
        let sorted = (1...10).map(Double.init)
        XCTAssertEqual(LatencyStats.percentile(sorted: sorted, 0), 1, accuracy: 1e-12)
        XCTAssertEqual(LatencyStats.percentile(sorted: sorted, 50), 5.5, accuracy: 1e-12)
        XCTAssertEqual(LatencyStats.percentile(sorted: sorted, 90), 9.1, accuracy: 1e-12)
        XCTAssertEqual(LatencyStats.percentile(sorted: sorted, 100), 10, accuracy: 1e-12)
        XCTAssertEqual(LatencyStats.percentile(sorted: [], 50), 0)
    }
}
