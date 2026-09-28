import Foundation
import Observation
import TranslatorCore
import CompanionLink

/// iPhone 側の「Mac連携」の窓口。
/// 同じWi-Fiの Mac を自動で探してつなぎ、つながっていれば翻訳を Mac に頼む。
/// つながっていない・返事が遅い(3秒)・失敗したときは、iPhone 自身の翻訳に自動で切り替える。
@MainActor
@Observable
final class CompanionStatus {
    /// Mac とつながっているか(画面の表示用)。
    private(set) var isConnected = false
    /// つながっている Mac の名前。
    private(set) var peerName: String?

    private let client: BonjourCompanionClient
    private let remote: RemoteTranslator
    private var started = false

    init() {
        let client = BonjourCompanionClient(deviceName: "iPhone")
        self.client = client
        self.remote = RemoteTranslator(transport: client)
    }

    /// 画面に出す短い表示。
    var label: String {
        isConnected ? "Mac接続中" : "iPhone単体"
    }

    /// Mac 探しを始める。画面が出たときに1回だけ呼ぶ。
    /// (初回は「ローカルネットワークへのアクセス」の許可を求める画面が出る)
    func start() {
        guard !started else { return }
        started = true
        client.onStateChange = { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }
        client.start()
    }

    private func apply(_ state: CompanionConnectionState) {
        if case let .connected(peer) = state {
            isConnected = true
            peerName = peer
        } else {
            isConnected = false
            peerName = nil
        }
    }

    /// 「Mac があれば Mac、なければ local」で訳す翻訳器を作る。
    func makeTranslator(local: Translating) -> Translating {
        let client = self.client
        return FallbackTranslator(
            primary: remote,
            fallback: local,
            timeout: 3,
            isPrimaryAvailable: { client.isConnected })
    }
}
