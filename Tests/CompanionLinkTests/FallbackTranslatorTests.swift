import XCTest
import TranslatorCore
@testable import CompanionLink

/// テスト用の翻訳器。決めた時間だけ待ってから、決めた結果を返す(または失敗する)。
private struct FakeTranslator: Translating {
    enum Behavior: Sendable {
        case reply(String)
        case fail
        case slow(seconds: Double, reply: String)
    }

    struct FakeError: Error {}

    let behavior: Behavior
    let calls: CallCounter

    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        await calls.increment()
        switch behavior {
        case .reply(let value):
            return value
        case .fail:
            throw FakeError()
        case .slow(let seconds, let value):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return value
        }
    }
}

/// 何回呼ばれたかを数える係。
private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

final class FallbackTranslatorTests: XCTestCase {
    // MARK: 決まり(FallbackPolicy)だけのテスト

    func testPolicyUsesPrimaryOnSuccess() {
        XCTAssertEqual(FallbackPolicy.decide(.success("Xin chào")), .usePrimary("Xin chào"))
    }

    func testPolicyFallsBackOnEveryProblem() {
        XCTAssertEqual(FallbackPolicy.decide(.failure(CompanionError.disconnected)), .useFallback(.failed))
        XCTAssertEqual(FallbackPolicy.decide(.timedOut), .useFallback(.timedOut))
        XCTAssertEqual(FallbackPolicy.decide(.unavailable), .useFallback(.unavailable))
        XCTAssertEqual(FallbackPolicy.decide(.success("  \n")), .useFallback(.emptyResult))
    }

    // MARK: 実際に翻訳器を組み合わせたテスト

    func testPrimaryOkIsUsed() async throws {
        let primaryCalls = CallCounter()
        let fallbackCalls = CallCounter()
        let translator = FallbackTranslator(
            primary: FakeTranslator(behavior: .reply("Mac の訳"), calls: primaryCalls),
            fallback: FakeTranslator(behavior: .reply("iPhone の訳"), calls: fallbackCalls))

        let result = try await translator.translate("こんにちは", from: .japanese, to: .vietnamese)

        XCTAssertEqual(result, "Mac の訳")
        let fallbackCount = await fallbackCalls.count
        XCTAssertEqual(fallbackCount, 0)
    }

    func testPrimaryThrowsFallsBack() async throws {
        let translator = FallbackTranslator(
            primary: FakeTranslator(behavior: .fail, calls: CallCounter()),
            fallback: FakeTranslator(behavior: .reply("iPhone の訳"), calls: CallCounter()))

        let result = try await translator.translate("こんにちは", from: .japanese, to: .vietnamese)

        XCTAssertEqual(result, "iPhone の訳")
    }

    func testPrimaryTooSlowFallsBack() async throws {
        let recorder = DecisionRecorder()
        let translator = FallbackTranslator(
            primary: FakeTranslator(behavior: .slow(seconds: 5, reply: "遅すぎる訳"), calls: CallCounter()),
            fallback: FakeTranslator(behavior: .reply("iPhone の訳"), calls: CallCounter()),
            timeout: 0.2,
            onDecision: { recorder.record($0) })

        let started = Date()
        let result = try await translator.translate("こんにちは", from: .japanese, to: .vietnamese)

        XCTAssertEqual(result, "iPhone の訳")
        // 5秒も待たずに、時間切れ(0.2秒)で控えに切り替わっていること。
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(recorder.decisions, [.useFallback(.timedOut)])
    }

    func testUnavailablePrimaryIsNotEvenAsked() async throws {
        let primaryCalls = CallCounter()
        let translator = FallbackTranslator(
            primary: FakeTranslator(behavior: .reply("Mac の訳"), calls: primaryCalls),
            fallback: FakeTranslator(behavior: .reply("iPhone の訳"), calls: CallCounter()),
            isPrimaryAvailable: { false })

        let result = try await translator.translate("こんにちは", from: .japanese, to: .vietnamese)

        XCTAssertEqual(result, "iPhone の訳")
        let primaryCount = await primaryCalls.count
        XCTAssertEqual(primaryCount, 0)
    }

    func testFallbackErrorIsPassedToCaller() async {
        let translator = FallbackTranslator(
            primary: FakeTranslator(behavior: .fail, calls: CallCounter()),
            fallback: FakeTranslator(behavior: .fail, calls: CallCounter()))

        do {
            _ = try await translator.translate("こんにちは", from: .japanese, to: .vietnamese)
            XCTFail("両方失敗したらエラーになるはず")
        } catch {
            XCTAssertTrue(error is FakeTranslator.FakeError)
        }
    }
}

/// onDecision で届いた結論を記録する係。
private final class DecisionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [FallbackDecision] = []

    func record(_ decision: FallbackDecision) {
        lock.lock()
        stored.append(decision)
        lock.unlock()
    }

    var decisions: [FallbackDecision] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
