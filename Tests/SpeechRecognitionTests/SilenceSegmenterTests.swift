import XCTest
@testable import SpeechRecognition

/// 無音で文を区切る SilenceSegmenter のテスト。時刻は秒で、自分で進める。
final class SilenceSegmenterTests: XCTestCase {
    let loud: Float = -20   // 話している音量
    let quiet: Float = -60  // 無音

    func test既定の無音は0点8秒() {
        XCTAssertEqual(SilenceSegmenter.Configuration().silenceDuration, 0.8)
    }

    func test何も話されていなければ確定しない() {
        var segmenter = SilenceSegmenter()
        for step in 0..<50 {
            XCTAssertFalse(segmenter.observeAudioLevel(quiet, at: Double(step) * 0.1))
        }
        XCTAssertFalse(segmenter.hasPendingSpeech)
    }

    func test話したあと0点8秒黙ると1回だけ確定する() {
        var segmenter = SilenceSegmenter()
        XCTAssertFalse(segmenter.observeAudioLevel(loud, at: 0.0))
        XCTAssertFalse(segmenter.observePartialText("こんにちは", at: 0.3))
        XCTAssertFalse(segmenter.observeAudioLevel(loud, at: 0.5))
        // 0.5秒に最後の音。0.5 + 0.8 = 1.3 秒になるまでは確定しない。
        XCTAssertFalse(segmenter.observeAudioLevel(quiet, at: 1.0))
        XCTAssertFalse(segmenter.observeAudioLevel(quiet, at: 1.2))
        XCTAssertTrue(segmenter.observeAudioLevel(quiet, at: 1.31))
        // 確定したらリセットされるので、黙り続けても2回目は出ない。
        XCTAssertFalse(segmenter.hasPendingSpeech)
        XCTAssertFalse(segmenter.observeAudioLevel(quiet, at: 2.0))
        XCTAssertFalse(segmenter.observeAudioLevel(quiet, at: 5.0))
    }

    func test文字が増え続けている間は確定しない() {
        var segmenter = SilenceSegmenter()
        XCTAssertFalse(segmenter.observePartialText("今日は", at: 0.0))
        XCTAssertFalse(segmenter.observeAudioLevel(quiet, at: 0.5))
        XCTAssertFalse(segmenter.observePartialText("今日はいい", at: 0.7))
        XCTAssertFalse(segmenter.observeAudioLevel(quiet, at: 1.2))
        XCTAssertFalse(segmenter.observePartialText("今日はいい天気", at: 1.4))
        XCTAssertFalse(segmenter.observeAudioLevel(quiet, at: 2.1))
        XCTAssertTrue(segmenter.observeAudioLevel(quiet, at: 2.25))
    }

    func test同じ文字が届いても活動とはみなさない() {
        var segmenter = SilenceSegmenter()
        XCTAssertFalse(segmenter.observePartialText("xin chào", at: 0.0))
        XCTAssertFalse(segmenter.observePartialText("xin chào ", at: 0.5))
        XCTAssertTrue(segmenter.observePartialText("xin chào", at: 0.8))
    }

    func test無音の長さを変えられる() {
        var segmenter = SilenceSegmenter(configuration: .init(silenceDuration: 0.3))
        XCTAssertFalse(segmenter.observePartialText("はい", at: 0.0))
        XCTAssertFalse(segmenter.observeAudioLevel(quiet, at: 0.2))
        XCTAssertTrue(segmenter.observeAudioLevel(quiet, at: 0.3))
    }

    func testうるさい場所でも文字が止まれば確定する() {
        var segmenter = SilenceSegmenter(configuration: .init(stableTextTimeout: 2.0, maxUtteranceDuration: nil))
        XCTAssertFalse(segmenter.observePartialText("もしもし", at: 0.0))
        // ずっと大きな音(雑音)が続く。
        XCTAssertFalse(segmenter.observeAudioLevel(loud, at: 1.0))
        XCTAssertFalse(segmenter.observeAudioLevel(loud, at: 1.9))
        XCTAssertTrue(segmenter.observeAudioLevel(loud, at: 2.0))
    }

    func test長すぎる文は上限で区切る() {
        var segmenter = SilenceSegmenter(configuration: .init(stableTextTimeout: nil, maxUtteranceDuration: 5))
        var fired = false
        for step in 0...60 {
            let time = Double(step) * 0.1
            fired = segmenter.observePartialText("文字\(step)", at: time) || fired
            if fired {
                XCTAssertEqual(time, 5.0, accuracy: 0.001)
                break
            }
        }
        XCTAssertTrue(fired)
    }

    func test確定のあと次の文も区切れる() {
        var segmenter = SilenceSegmenter()
        XCTAssertFalse(segmenter.observePartialText("一つ目", at: 0.0))
        XCTAssertTrue(segmenter.tick(at: 0.8))
        XCTAssertFalse(segmenter.observeAudioLevel(loud, at: 3.0))
        XCTAssertFalse(segmenter.observePartialText("二つ目", at: 3.2))
        XCTAssertEqual(segmenter.pendingText, "二つ目")
        XCTAssertFalse(segmenter.tick(at: 3.9))
        XCTAssertTrue(segmenter.tick(at: 4.05))
    }

    func test空の途中結果は無視する() {
        var segmenter = SilenceSegmenter()
        XCTAssertFalse(segmenter.observePartialText("   ", at: 0.0))
        XCTAssertFalse(segmenter.hasPendingSpeech)
        XCTAssertFalse(segmenter.tick(at: 10))
    }

    func test音量の計算() {
        XCTAssertEqual(SilenceSegmenter.decibels(rms: 1.0), 0, accuracy: 0.001)
        XCTAssertEqual(SilenceSegmenter.decibels(rms: 0.1), -20, accuracy: 0.001)
        XCTAssertEqual(SilenceSegmenter.decibels(rms: 0), -160)
        XCTAssertEqual(SilenceSegmenter.decibels(ofSamples: [Float]()), -160)
        XCTAssertEqual(SilenceSegmenter.decibels(ofSamples: [0.1, -0.1, 0.1, -0.1] as [Float]), -20, accuracy: 0.001)
    }
}
