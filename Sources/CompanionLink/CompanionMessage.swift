import Foundation
import TranslatorCore

/// Mac連携モードで iPhone と Mac がやり取りするメッセージ。
/// iPhone がマイク音声を送り、Mac が認識・翻訳して結果(と必要なら合成音声)を返す。
public enum CompanionMessage: Codable, Sendable, Equatable {
    /// 接続直後のあいさつ。プロトコルの版と、端末名。
    case hello(protocolVersion: Int, deviceName: String)
    /// iPhone → Mac: 16kHz・モノラル・16bit PCM の音声のかたまり。
    case audioChunk(sequence: Int, pcm16: Data)
    /// iPhone → Mac: 文字だけ送って訳してもらう(長文翻訳をMacに任せる場合)。
    case translateRequest(id: String, text: String, source: Language)
    /// Mac → iPhone: 認識結果(途中・確定)。
    case transcript(Transcript)
    /// Mac → iPhone: 翻訳結果。
    case translation(id: String, text: String, target: Language, voice: VoiceRole)
    /// Mac → iPhone: Macで合成した音声(任意)。nil なら iPhone 側で読み上げる。
    case synthesizedAudio(id: String, wav: Data)
    case error(message: String)

    public static let protocolVersion = 1
}

/// 1行1メッセージ(JSON Lines)で送るための変換。TCP でも WebSocket でも同じ形で使える。
public enum CompanionCodec {
    public static func encode(_ message: CompanionMessage) throws -> Data {
        var data = try JSONEncoder().encode(message)
        data.append(0x0A) // 改行で区切る
        return data
    }

    /// 受け取ったバイト列から完全な行だけを取り出し、残り(途中の行)は buffer に残す。
    public static func decode(buffer: inout Data) throws -> [CompanionMessage] {
        var messages: [CompanionMessage] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if !line.isEmpty {
                messages.append(try JSONDecoder().decode(CompanionMessage.self, from: Data(line)))
            }
        }
        return messages
    }
}

/// 通信路の差し込み口。実装は Network フレームワーク(Bonjour で同じWi-Fi内のMacを自動発見)を予定。
public protocol CompanionTransport: Sendable {
    func send(_ message: CompanionMessage) async throws
    func messages() -> AsyncThrowingStream<CompanionMessage, Error>
}

/// Mac に翻訳を任せる Translating 実装。iPhone側から見ると普通の翻訳器と同じに見える。
/// 「翻訳お願い」の手紙に番号(id)を書いて送り、同じ番号の返事が来たら待っている人に渡す仕組み。
public actor RemoteTranslator: Translating {
    private let transport: CompanionTransport
    private var pending: [String: CheckedContinuation<String, Error>] = [:]
    private var listening = false

    public init(transport: CompanionTransport) {
        self.transport = transport
    }

    public func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        startListeningIfNeeded()
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do {
                    try await transport.send(.translateRequest(id: id, text: text, source: source))
                } catch {
                    self.fail(id: id, error: error)
                }
            }
        }
    }

    private func startListeningIfNeeded() {
        guard !listening else { return }
        listening = true
        // 返事の受け取り口は、依頼を送る「前に」その場で開いておく。
        // (後から開くと、とても速い返事を取りこぼすことがあるため)
        let stream = transport.messages()
        Task {
            var endError: Error = CompanionError.disconnected
            do {
                for try await message in stream {
                    if case let .translation(id, text, _, _) = message {
                        pending.removeValue(forKey: id)?.resume(returning: text)
                    }
                }
            } catch {
                endError = error
            }
            // 通信が終わった(切れた)ら、待っている人全員に「失敗」を伝える。
            // 次の translate でまた受け取り口を開き直せるよう listening を戻す。
            finishAll(error: endError)
        }
    }

    private func finishAll(error: Error) {
        let waiting = pending
        pending.removeAll()
        listening = false
        for continuation in waiting.values { continuation.resume(throwing: error) }
    }

    private func fail(id: String, error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }
}
