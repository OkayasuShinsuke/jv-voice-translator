import XCTest
import TranslatorCore
@testable import CompanionLink

/// テスト用:メモリの中だけでつながる通信路。
/// 本物(Network フレームワーク)と同じく JSON Lines のバイト列にして、わざと細切れで相手に届ける。
final class InMemoryTransport: CompanionTransport, @unchecked Sendable {
    private let lock = NSLock()
    private weak var peer: InMemoryTransport?
    private var decoder = CompanionStreamDecoder()
    private var connected = true
    private let incoming = Broadcaster<CompanionMessage>()
    private let chunkSize: Int

    init(chunkSize: Int) {
        self.chunkSize = chunkSize
    }

    /// つながった2つの端を作る(片方が iPhone、もう片方が Mac の役)。
    static func pair(chunkSize: Int = 5) -> (InMemoryTransport, InMemoryTransport) {
        let a = InMemoryTransport(chunkSize: chunkSize)
        let b = InMemoryTransport(chunkSize: chunkSize)
        a.peer = b
        b.peer = a
        return (a, b)
    }

    func send(_ message: CompanionMessage) async throws {
        lock.lock()
        let isConnected = connected
        let target = peer
        lock.unlock()
        guard isConnected, let target = target else { throw CompanionError.notConnected }
        let bytes = try CompanionCodec.encode(message)
        var chunks: [Data] = []
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + chunkSize, bytes.count)
            chunks.append(bytes.subdata(in: offset..<end))
            offset = end
        }
        target.deliver(chunks)
    }

    func messages() -> AsyncThrowingStream<CompanionMessage, Error> {
        incoming.stream()
    }

    /// 回線が切れたことにする。
    func disconnect() {
        lock.lock()
        connected = false
        lock.unlock()
        incoming.finish(throwing: CompanionError.disconnected)
    }

    private func deliver(_ chunks: [Data]) {
        lock.lock()
        var received: [CompanionMessage] = []
        for chunk in chunks {
            received += decoder.feed(chunk).messages
        }
        lock.unlock()
        for message in received { incoming.yield(message) }
    }
}

final class InMemoryTransportTests: XCTestCase {
    func testMessagesSurviveTinyChunks() async throws {
        let (iphone, mac) = InMemoryTransport.pair(chunkSize: 3)
        let sent: [CompanionMessage] = [
            .hello(protocolVersion: CompanionMessage.protocolVersion, deviceName: "iPhone"),
            .translateRequest(id: "42", text: "こんにちは。元気ですか?", source: .japanese),
            .error(message: "テスト"),
        ]
        let stream = mac.messages()
        for message in sent { try await iphone.send(message) }

        var received: [CompanionMessage] = []
        for try await message in stream {
            received.append(message)
            if received.count == sent.count { break }
        }
        XCTAssertEqual(received, sent)
    }

    func testDecoderSkipsBrokenLineAndKeepsGoing() throws {
        var decoder = CompanionStreamDecoder()
        var wire = Data("これはJSONではない\n".utf8)
        wire.append(try CompanionCodec.encode(.error(message: "ok")))

        // 1バイトずつ届いても大丈夫なことを確かめる。
        var messages: [CompanionMessage] = []
        var invalid = 0
        for byte in wire {
            let result = decoder.feed(Data([byte]))
            messages += result.messages
            invalid += result.invalidLines
        }
        XCTAssertEqual(messages, [.error(message: "ok")])
        XCTAssertEqual(invalid, 1)
        XCTAssertEqual(decoder.pendingByteCount, 0)
    }

    func testRemoteTranslatorGetsReplyFromFakeMac() async throws {
        let (iphone, mac) = InMemoryTransport.pair()
        // 偽物の Mac:依頼が来たら、先頭に [訳] を付けて返す。
        let macInbox = mac.messages()
        let fakeMac = Task {
            for try await message in macInbox {
                if case let .translateRequest(id, text, source) = message {
                    try await mac.send(.translation(
                        id: id, text: "[訳]" + text, target: source.counterpart, voice: .forSpoken(source)))
                }
            }
        }
        defer { fakeMac.cancel() }

        let remote = RemoteTranslator(transport: iphone)
        let first = try await remote.translate("こんにちは", from: .japanese, to: .vietnamese)
        let second = try await remote.translate("Xin chào", from: .vietnamese, to: .japanese)

        XCTAssertEqual(first, "[訳]こんにちは")
        XCTAssertEqual(second, "[訳]Xin chào")
    }

    func testDisconnectedMacFallsBackToLocal() async throws {
        let (iphone, mac) = InMemoryTransport.pair()
        // Mac は返事をしないまま、0.1秒後に回線が切れる。
        Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            iphone.disconnect()
        }
        let translator = FallbackTranslator(
            primary: RemoteTranslator(transport: iphone),
            fallback: LocalEcho(),
            timeout: 5)

        let started = Date()
        let result = try await translator.translate("こんにちは", from: .japanese, to: .vietnamese)

        XCTAssertEqual(result, "iPhone:こんにちは")
        // 5秒の時間切れを待たずに、切断で即座に切り替わっていること。
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        // mac 側はテストの最後まで生かしておく(途中で消えると「切断」の確認にならないため)。
        withExtendedLifetime(mac) {}
    }
}

/// iPhone 自身の翻訳器の代わり。
private struct LocalEcho: Translating {
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        "iPhone:" + text
    }
}
