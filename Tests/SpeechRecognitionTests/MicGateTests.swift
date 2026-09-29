import XCTest
@testable import SpeechRecognition

final class MicGateTests: XCTestCase {
    func test最初は一時停止していない() {
        let gate = MicGate()
        XCTAssertFalse(gate.isPaused)
        XCTAssertTrue(gate.shouldForwardAudio)
    }

    func testPauseすると音を渡さなくなる() {
        var gate = MicGate()
        gate.pause()
        XCTAssertTrue(gate.isPaused)
        XCTAssertFalse(gate.shouldForwardAudio)
    }

    func testResumeすると音を渡すようになる() {
        var gate = MicGate()
        gate.pause()
        gate.resume()
        XCTAssertFalse(gate.isPaused)
        XCTAssertTrue(gate.shouldForwardAudio)
    }

    func test何度pauseしても状態は変わらない() {
        var gate = MicGate()
        gate.pause()
        gate.pause()
        XCTAssertTrue(gate.isPaused)
    }
}
