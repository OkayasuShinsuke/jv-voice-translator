import XCTest
@testable import Evaluation

final class MetricsTests: XCTestCase {
    func testEditDistance() {
        XCTAssertEqual(EditDistance.distance(Array("kitten"), Array("sitting")), 3)
        XCTAssertEqual(EditDistance.distance([String](), ["a"]), 1)
    }

    func testWordErrorRate() {
        // 4単語中1単語が違う → 25%
        XCTAssertEqual(Metrics.wordErrorRate(reference: "tôi là sinh viên", hypothesis: "tôi là học viên"), 0.25, accuracy: 1e-9)
        XCTAssertEqual(Metrics.wordErrorRate(reference: "Xin chào!", hypothesis: "xin chào"), 0)
    }

    func testCharacterErrorRate() {
        // 5文字中1文字が違う → 20%
        XCTAssertEqual(Metrics.characterErrorRate(reference: "こんにちは", hypothesis: "こんばちは"), 0.2, accuracy: 1e-9)
    }

    func testChrF() {
        XCTAssertEqual(Metrics.chrF(reference: "ありがとう", hypothesis: "ありがとう"), 100, accuracy: 1e-9)
        XCTAssertEqual(Metrics.chrF(reference: "ありがとう", hypothesis: "さよなら"), 0, accuracy: 1e-9)
        let partial = Metrics.chrF(reference: "Cảm ơn bạn nhiều", hypothesis: "Cảm ơn bạn")
        XCTAssertGreaterThan(partial, 0)
        XCTAssertLessThan(partial, 100)
    }
}
