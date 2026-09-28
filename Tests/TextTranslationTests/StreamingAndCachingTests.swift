import XCTest
import TranslatorCore
@testable import TextTranslation

/// 何回・どの文で呼ばれたかを記録するための入れ物(actor なので同時に書いても安全)。
actor CallLog {
    private(set) var texts: [String] = []
    func record(_ text: String) { texts.append(text) }
    var count: Int { texts.count }
}

/// 呼ばれた文を記録して "<文>" を返す偽物の翻訳器。
struct RecordingTranslator: Translating {
    let log: CallLog
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        await log.record(text)
        return "<\(text)>"
    }
}

/// 文ごとに決まった時間だけ待ってから訳を返す偽物の翻訳器。訳し終わった文を log に記録する。
struct DelayedTranslator: Translating {
    let delays: [String: UInt64]  // 文 → 待つナノ秒
    let finished: CallLog
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        try await Task.sleep(nanoseconds: delays[text] ?? 0)
        await finished.record(text)
        return "<\(text)>"
    }
}

/// 指定した文で必ず失敗する偽物の翻訳器。
struct FailingTranslator: Translating {
    struct Boom: Error {}
    let failOn: String
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        if text == failOn { throw Boom() }
        return "<\(text)>"
    }
}

final class StreamingTranslatorTests: XCTestCase {
    func testStreamYieldsSentencesInOrder() async throws {
        // 後ろの文ほど速く訳せる場合でも、順番は元の文の順に並ぶこと。
        let finished = CallLog()
        let translator = ChunkedTranslator(base: DelayedTranslator(
            delays: ["A.": 30_000_000, "B.": 10_000_000, "C.": 0], finished: finished))
        var received: [String] = []
        for try await sentence in translator.translateStream("A. B. C.", from: .vietnamese, to: .japanese) {
            received.append(sentence)
        }
        XCTAssertEqual(received, ["<A.>", "<B.>", "<C.>"])
    }

    func testFirstSentenceArrivesBeforeWholeTextFinishes() async throws {
        // 2文目はわざと2秒かかる。1文目はその前に届くはず(=先に話し始められる)。
        let finished = CallLog()
        let translator = ChunkedTranslator(base: DelayedTranslator(
            delays: ["今日は晴れです。": 0, "散歩に行きましょう!": 2_000_000_000], finished: finished))
        let start = Date()
        var iterator = translator.translateStream("今日は晴れです。散歩に行きましょう!",
                                                   from: .japanese, to: .vietnamese).makeAsyncIterator()

        let first = try await iterator.next()
        let firstElapsed = Date().timeIntervalSince(start)
        let finishedWhenFirstArrived = await finished.count
        XCTAssertEqual(first, "<今日は晴れです。>")
        XCTAssertEqual(finishedWhenFirstArrived, 1, "1文目が届いた時点で、2文目はまだ訳し終わっていないはず")
        XCTAssertLessThan(firstElapsed, 1.5)

        let second = try await iterator.next()
        XCTAssertEqual(second, "<散歩に行きましょう!>")
        let end = try await iterator.next()
        XCTAssertNil(end)
    }

    func testStreamFinishesWithErrorWhenBaseFails() async {
        let translator = ChunkedTranslator(base: FailingTranslator(failOn: "B."))
        var received: [String] = []
        do {
            for try await sentence in translator.translateStream("A. B. C.", from: .vietnamese, to: .japanese) {
                received.append(sentence)
            }
            XCTFail("エラーで終わるはず")
        } catch {
            XCTAssertTrue(error is FailingTranslator.Boom)
        }
        XCTAssertEqual(received, ["<A.>"])
    }

    func testEmptyTextYieldsNothing() async throws {
        let translator = ChunkedTranslator(base: EchoTranslator())
        var received: [String] = []
        for try await sentence in translator.translateStream("   ", from: .japanese, to: .vietnamese) {
            received.append(sentence)
        }
        XCTAssertEqual(received, [])
    }
}

final class CachingTranslatorTests: XCTestCase {
    func testCacheHitAvoidsSecondBaseCall() async throws {
        let log = CallLog()
        let cache = CachingTranslator(base: RecordingTranslator(log: log), capacity: 10)

        let first = try await cache.translate("こんにちは", from: .japanese, to: .vietnamese)
        let second = try await cache.translate("こんにちは", from: .japanese, to: .vietnamese)

        XCTAssertEqual(first, "<こんにちは>")
        XCTAssertEqual(second, "<こんにちは>")
        let calls = await log.count
        XCTAssertEqual(calls, 1, "2回目は覚えている訳を返すので、base は1回しか呼ばれない")
        let hits = await cache.hitCount
        let misses = await cache.missCount
        XCTAssertEqual(hits, 1)
        XCTAssertEqual(misses, 1)
    }

    func testDifferentDirectionIsDifferentKey() async throws {
        let log = CallLog()
        let cache = CachingTranslator(base: RecordingTranslator(log: log), capacity: 10)
        _ = try await cache.translate("A", from: .japanese, to: .vietnamese)
        _ = try await cache.translate("A", from: .vietnamese, to: .japanese)
        let calls = await log.count
        XCTAssertEqual(calls, 2)
    }

    func testEvictsLeastRecentlyUsedWhenFull() async throws {
        let log = CallLog()
        let cache = CachingTranslator(base: RecordingTranslator(log: log), capacity: 2)

        _ = try await cache.translate("A", from: .japanese, to: .vietnamese)  // 覚える: A
        _ = try await cache.translate("B", from: .japanese, to: .vietnamese)  // 覚える: A, B
        _ = try await cache.translate("A", from: .japanese, to: .vietnamese)  // A を使った → B が最古
        _ = try await cache.translate("C", from: .japanese, to: .vietnamese)  // いっぱい → B を捨てる
        let count = await cache.count
        XCTAssertEqual(count, 2)

        _ = try await cache.translate("A", from: .japanese, to: .vietnamese)  // 残っている(当たり)
        _ = try await cache.translate("B", from: .japanese, to: .vietnamese)  // 捨てたので base を呼ぶ
        let texts = await log.texts
        XCTAssertEqual(texts, ["A", "B", "C", "B"])
    }

    func testZeroCapacityNeverCaches() async throws {
        let log = CallLog()
        let cache = CachingTranslator(base: RecordingTranslator(log: log), capacity: 0)
        _ = try await cache.translate("A", from: .japanese, to: .vietnamese)
        _ = try await cache.translate("A", from: .japanese, to: .vietnamese)
        let calls = await log.count
        XCTAssertEqual(calls, 2)
    }

    func testFailuresAreNotCached() async throws {
        let cache = CachingTranslator(base: FailingTranslator(failOn: "X"), capacity: 10)
        do {
            _ = try await cache.translate("X", from: .japanese, to: .vietnamese)
            XCTFail("失敗するはず")
        } catch {}
        let count = await cache.count
        XCTAssertEqual(count, 0)
    }

    func testConcurrentCallsAreSafe() async throws {
        let log = CallLog()
        let cache = CachingTranslator(base: RecordingTranslator(log: log), capacity: 5)
        try await withThrowingTaskGroup(of: String.self) { group in
            for i in 0..<100 {
                group.addTask { try await cache.translate("文\(i % 10)", from: .japanese, to: .vietnamese) }
            }
            for try await result in group {
                XCTAssertTrue(result.hasPrefix("<文"))
            }
        }
        let count = await cache.count
        XCTAssertLessThanOrEqual(count, 5)
    }
}

/// いつも決まった状態を返す偽物の確認器。
struct FakeAvailabilityChecker: LanguageAvailabilityChecking {
    let statuses: [LanguagePair: LanguagePairStatus]
    func status(for pair: LanguagePair) async -> LanguagePairStatus {
        statuses[pair] ?? .unsupported
    }
}

final class LanguageAvailabilityTests: XCTestCase {
    func testReportCombinesBothDirections() async {
        let checker = FakeAvailabilityChecker(statuses: [
            .japaneseToVietnamese: .installed,
            .vietnameseToJapanese: .needsDownload,
        ])
        let report = await LanguageAvailabilityReport.check(using: checker)
        XCTAssertEqual(report.japaneseToVietnamese, .installed)
        XCTAssertEqual(report.vietnameseToJapanese, .needsDownload)
        XCTAssertFalse(report.isReady)
        XCTAssertTrue(report.needsDownload)
    }

    func testReadyWhenBothInstalled() {
        let report = LanguageAvailabilityReport(japaneseToVietnamese: .installed, vietnameseToJapanese: .installed)
        XCTAssertTrue(report.isReady)
        XCTAssertFalse(report.needsDownload)
    }

    func testStatusHelpers() {
        XCTAssertTrue(LanguagePairStatus.installed.canTranslateNow)
        XCTAssertFalse(LanguagePairStatus.needsDownload.canTranslateNow)
        XCTAssertFalse(LanguagePairStatus.unsupported.canTranslateNow)
        for status in LanguagePairStatus.allCases {
            XCTAssertFalse(status.japaneseDescription.isEmpty)
        }
    }

    func testAppleCheckerReturnsSomeStatus() async {
        // CI の Mac で本物の API を呼んでも落ちないことだけ確かめる(結果は環境しだい)。
        let status = await AppleLanguageAvailabilityChecker().status(for: .japaneseToVietnamese)
        XCTAssertTrue(LanguagePairStatus.allCases.contains(status))
    }
}
