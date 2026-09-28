import XCTest
import TranslatorCore
@testable import CompanionLink

final class CodecTests: XCTestCase {
    func testRoundTripAcrossPartialReads() throws {
        let messages: [CompanionMessage] = [
            .hello(protocolVersion: CompanionMessage.protocolVersion, deviceName: "iPhone"),
            .transcript(Transcript(text: "こんにちは", language: .japanese, isFinal: true)),
            .translation(id: "1", text: "Xin chào", target: .vietnamese, voice: .a),
        ]
        var wire = Data()
        for message in messages { wire.append(try CompanionCodec.encode(message)) }

        // 通信では途中で切れて届くことがあるので、2回に分けて受け取る。
        var buffer = Data(wire.prefix(wire.count / 2))
        var received = try CompanionCodec.decode(buffer: &buffer)
        buffer.append(wire.suffix(from: wire.count / 2))
        received += try CompanionCodec.decode(buffer: &buffer)

        XCTAssertEqual(received, messages)
        XCTAssertTrue(buffer.isEmpty)
    }
}
