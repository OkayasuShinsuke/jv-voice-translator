import Foundation

// Mac連携モードで共通に使う小さな部品たち。Apple 専用の機能を使わないので、どこでもビルドできてテストもしやすい。

/// Mac連携で起こる失敗の種類。
public enum CompanionError: Error, Equatable, Sendable {
    /// まだつながっていない(Mac が見つかっていない)。
    case notConnected
    /// 途中で接続が切れた。
    case disconnected
}

/// 接続の様子。画面に「Mac接続中」などを出すために使う。
public enum CompanionConnectionState: Sendable, Equatable {
    /// 止まっている。
    case stopped
    /// 相手を待っている(Mac なら iPhone 待ち、iPhone なら Mac を探し中)。
    case waiting
    /// 相手が見つかって、つなぎに行っている途中。
    case connecting
    /// つながっている。peer は相手の名前。
    case connected(peer: String)
    /// うまく動かなかった。理由の文章付き。
    case failed(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// 通信で細切れに届くバイト列を少しずつ受け取り、1行そろうごとにメッセージへ戻す係。
/// 例えるなら、ちぎれて届く手紙の切れ端を順番に貼り合わせ、1通そろったら読む人。
/// 壊れた行があっても、その行だけ捨てて残りは読み続ける(1行のミスで通信全体を止めない)。
public struct CompanionStreamDecoder {
    private var buffer = Data()
    /// 改行が来ないまま大きくなりすぎたら捨てる上限(メモリを使い切らないための安全装置)。
    public let maxLineBytes: Int

    public init(maxLineBytes: Int = 8 * 1024 * 1024) {
        self.maxLineBytes = maxLineBytes
    }

    /// まだ行がそろっていない(途中まで届いている)バイト数。
    public var pendingByteCount: Int { buffer.count }

    /// 新しく届いたかけらを足して、そろった行をメッセージにして返す。
    /// invalidLines は読めずに捨てた行の数。
    public mutating func feed(_ chunk: Data) -> (messages: [CompanionMessage], invalidLines: Int) {
        buffer.append(chunk)
        var messages: [CompanionMessage] = []
        var invalid = 0
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.isEmpty { continue }
            if let message = try? JSONDecoder().decode(CompanionMessage.self, from: line) {
                messages.append(message)
            } else {
                invalid += 1
            }
        }
        if buffer.count > maxLineBytes {
            buffer.removeAll()
            invalid += 1
        }
        return (messages, invalid)
    }
}

/// 同じ知らせを、聞いている全員に配る「校内放送」のような係。
/// messages() を何回呼んでも、それぞれの受け取り口に同じメッセージが届く。
final class Broadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncThrowingStream<Element, Error>.Continuation] = [:]

    /// 新しい受け取り口を作る。作った瞬間から届くようになる。
    func stream() -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            self.lock.lock()
            self.continuations[id] = continuation
            self.lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    func yield(_ element: Element) {
        lock.lock()
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets { continuation.yield(element) }
    }

    /// 今ある受け取り口を全部閉じる(error があれば失敗として閉じる)。
    /// その後に stream() を呼べば、また新しい受け取り口を作れる。
    func finish(throwing error: Error? = nil) {
        lock.lock()
        let targets = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in targets { continuation.finish(throwing: error) }
    }
}
