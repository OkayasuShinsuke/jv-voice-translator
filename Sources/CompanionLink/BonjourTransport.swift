// Network フレームワーク(Apple 純正・無料)を使った、同じWi-Fi内での通信。
// Bonjour(ボンジュール)は「このWi-Fiに翻訳係の Mac はいますか?」と呼びかけて、相手を自動で見つける仕組み。
// Mac 側は看板を出して待ち(BonjourCompanionServer)、iPhone 側は看板を探してつなぐ(BonjourCompanionClient)。
#if canImport(Network)
import Foundation
import Network

/// Bonjour で使うサービスの種類名。Info.plist の NSBonjourServices と同じ文字にする。
public enum CompanionService {
    public static let bonjourType = "_jvtranslate._tcp"
}

/// 1本の TCP 接続を包み、メッセージの送受信だけに集中できるようにする係。
/// 受信は細切れで届くので、CompanionStreamDecoder で1行ずつ組み立て直す。
/// 中の値は、すべて渡された queue(1列に並んで順番に処理する窓口)の上で触る。
final class CompanionConnection: @unchecked Sendable {
    let connection: NWConnection
    private let queue: DispatchQueue
    private var decoder = CompanionStreamDecoder()
    private var receiving = false

    /// メッセージが1通そろうたびに呼ばれる。
    var onMessage: ((CompanionMessage) -> Void)?
    /// 接続の状態が変わるたびに呼ばれる。
    var onStateChange: ((NWConnection.State) -> Void)?

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    /// 相手の名前(分からなければ接続先の住所)。
    var endpointDescription: String {
        "\(connection.endpoint)"
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state, !self.receiving {
                self.receiving = true
                self.receiveNext()
            }
            self.onStateChange?(state)
        }
        connection.start(queue: queue)
    }

    func cancel() {
        connection.cancel()
    }

    /// 届いた分だけ読んで、また次を待つ(ずっと繰り返す)。
    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                let result = self.decoder.feed(data)
                for message in result.messages {
                    self.onMessage?(message)
                }
            }
            if isComplete || error != nil {
                // 相手が閉じた、または通信エラー。接続を片付ける(状態が .cancelled になる)。
                self.connection.cancel()
                return
            }
            self.receiveNext()
        }
    }

    /// メッセージを1行の JSON にして送る。送り終わるまで待つ。
    func send(_ message: CompanionMessage) async throws {
        let data = try CompanionCodec.encode(message)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

// MARK: - Mac 側(待ち受け)

/// Mac 側の通信係。Bonjour で「翻訳係はここです」という看板を出し、iPhone からの接続を待つ。
/// 複数の iPhone がつながった場合、send は全員に同じメッセージを送る
/// (返事には依頼の id が付いているので、関係ない iPhone は無視する)。
public final class BonjourCompanionServer: CompanionTransport, @unchecked Sendable {
    private let queue = DispatchQueue(label: "jvtranslate.companion.server")
    private let deviceName: String
    private let serviceName: String?
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: CompanionConnection] = [:]
    /// つながり終わった相手とその名前。
    private var peers: [ObjectIdentifier: String] = [:]
    private let incoming = Broadcaster<CompanionMessage>()

    /// 状態が変わるたびに呼ばれる(画面表示用)。start() の前に設定する。
    public var onStateChange: (@Sendable (CompanionConnectionState) -> Void)?

    /// - Parameters:
    ///   - deviceName: あいさつ(hello)で相手に伝える自分の名前。
    ///   - serviceName: Bonjour の看板の名前。nil ならコンピュータ名が使われる。
    public init(deviceName: String = "Mac", serviceName: String? = nil) {
        self.deviceName = deviceName
        self.serviceName = serviceName
    }

    /// 看板を出して待ち受けを始める。
    public func start() {
        queue.async { self.startOnQueue() }
    }

    /// 待ち受けをやめ、つながっている相手も切る。
    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for connection in self.connections.values { connection.cancel() }
            self.connections.removeAll()
            self.peers.removeAll()
            self.report(.stopped)
        }
    }

    public func send(_ message: CompanionMessage) async throws {
        let targets: [CompanionConnection] = queue.sync {
            connections.filter { peers[$0.key] != nil }.map { $0.value }
        }
        guard !targets.isEmpty else { throw CompanionError.notConnected }
        for target in targets {
            try await target.send(message)
        }
    }

    public func messages() -> AsyncThrowingStream<CompanionMessage, Error> {
        incoming.stream()
    }

    // ここから下は queue の上だけで動く。

    private func startOnQueue() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: serviceName, type: CompanionService.bonjourType)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.publishState()
                case .failed(let error):
                    self.report(.failed(error.localizedDescription))
                    self.listener?.cancel()
                    self.listener = nil
                case .cancelled:
                    break
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            report(.failed(error.localizedDescription))
        }
    }

    private func accept(_ nwConnection: NWConnection) {
        let connection = CompanionConnection(connection: nwConnection, queue: queue)
        let key = ObjectIdentifier(connection)
        connections[key] = connection

        connection.onMessage = { [weak self] message in
            guard let self = self else { return }
            // 相手のあいさつで名前が分かったら、状態の表示を更新する。
            if case let .hello(_, name) = message {
                self.peers[key] = name
                self.publishState()
            }
            self.incoming.yield(message)
        }
        connection.onStateChange = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .ready:
                if self.peers[key] == nil {
                    self.peers[key] = connection.endpointDescription
                }
                self.publishState()
                // つながったらすぐ、こちらからもあいさつする。
                let hello = CompanionMessage.hello(
                    protocolVersion: CompanionMessage.protocolVersion, deviceName: self.deviceName)
                Task { try? await connection.send(hello) }
            case .waiting, .failed:
                connection.cancel()
            case .cancelled:
                self.connections[key] = nil
                self.peers[key] = nil
                self.publishState()
            default:
                break
            }
        }
        connection.start()
    }

    private func publishState() {
        guard listener != nil else {
            report(.stopped)
            return
        }
        if peers.isEmpty {
            report(.waiting)
        } else {
            report(.connected(peer: peers.values.sorted().joined(separator: ", ")))
        }
    }

    private func report(_ state: CompanionConnectionState) {
        onStateChange?(state)
    }
}

// MARK: - iPhone 側(探してつなぐ)

/// iPhone 側の通信係。同じWi-Fiで Mac の看板を探し、見つけたら自動でつなぐ。
/// 切れたら少し待って探し直す。つながっていない間の send は CompanionError.notConnected で失敗する。
public final class BonjourCompanionClient: CompanionTransport, @unchecked Sendable {
    private let queue = DispatchQueue(label: "jvtranslate.companion.client")
    private let deviceName: String
    private var browser: NWBrowser?
    private var current: CompanionConnection?
    private var peerName: String?
    private var running = false
    private let incoming = Broadcaster<CompanionMessage>()

    private let flagLock = NSLock()
    private var connectedFlag = false

    /// 状態が変わるたびに呼ばれる(画面表示用)。start() の前に設定する。
    public var onStateChange: (@Sendable (CompanionConnectionState) -> Void)?

    public init(deviceName: String = "iPhone") {
        self.deviceName = deviceName
    }

    /// 今 Mac とつながっているか。どのスレッドから読んでもよい。
    public var isConnected: Bool {
        flagLock.lock()
        defer { flagLock.unlock() }
        return connectedFlag
    }

    /// Mac 探しを始める。
    public func start() {
        queue.async {
            self.running = true
            self.startBrowsing()
        }
    }

    /// 探すのをやめ、接続も切る。
    public func stop() {
        queue.async {
            self.running = false
            self.browser?.cancel()
            self.browser = nil
            let connection = self.current
            self.current = nil
            connection?.cancel()
            self.setConnected(false)
            self.incoming.finish(throwing: CompanionError.disconnected)
            self.report(.stopped)
        }
    }

    public func send(_ message: CompanionMessage) async throws {
        let connection: CompanionConnection? = queue.sync {
            isConnected ? current : nil
        }
        guard let connection = connection else { throw CompanionError.notConnected }
        try await connection.send(message)
    }

    public func messages() -> AsyncThrowingStream<CompanionMessage, Error> {
        incoming.stream()
    }

    // ここから下は queue の上だけで動く。

    private func startBrowsing() {
        guard running, browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: CompanionService.bonjourType, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .failed(let error) = state {
                self.report(.failed(error.localizedDescription))
                self.browser?.cancel()
                self.browser = nil
                // 少し待ってから探し直す。
                self.queue.asyncAfter(deadline: .now() + 3) { self.startBrowsing() }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.connectIfIdle(results: results)
        }
        self.browser = browser
        report(.waiting)
        browser.start(queue: queue)
    }

    private func connectIfIdle(results: Set<NWBrowser.Result>) {
        guard running, current == nil, let first = results.first else { return }
        connect(to: first.endpoint)
    }

    private func connect(to endpoint: NWEndpoint) {
        let connection = CompanionConnection(connection: NWConnection(to: endpoint, using: .tcp), queue: queue)
        current = connection
        peerName = nil
        report(.connecting)

        connection.onMessage = { [weak self] message in
            guard let self = self else { return }
            if case let .hello(_, name) = message {
                self.peerName = name
                self.report(.connected(peer: name))
            }
            self.incoming.yield(message)
        }
        connection.onStateChange = { [weak self, weak connection] state in
            guard let self = self, let connection = connection, self.current === connection else { return }
            switch state {
            case .ready:
                self.setConnected(true)
                self.report(.connected(peer: self.peerName ?? "Mac"))
                let hello = CompanionMessage.hello(
                    protocolVersion: CompanionMessage.protocolVersion, deviceName: self.deviceName)
                Task { try? await connection.send(hello) }
            case .waiting, .failed:
                // つながらない・切れた。片付けると .cancelled が来るので、そこで後始末する。
                connection.cancel()
            case .cancelled:
                self.handleDisconnect()
            default:
                break
            }
        }
        connection.start()
    }

    private func handleDisconnect() {
        current = nil
        setConnected(false)
        // 返事を待っている人(RemoteTranslator)に「切れた」と伝える。
        incoming.finish(throwing: CompanionError.disconnected)
        guard running else { return }
        report(.waiting)
        // 少し待ってから、見つかっている Mac につなぎ直す。
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, let browser = self.browser else { return }
            self.connectIfIdle(results: browser.browseResults)
        }
    }

    private func setConnected(_ value: Bool) {
        flagLock.lock()
        connectedFlag = value
        flagLock.unlock()
    }

    private func report(_ state: CompanionConnectionState) {
        onStateChange?(state)
    }
}
#endif
