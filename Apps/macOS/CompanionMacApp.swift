import SwiftUI
import Observation
import Translation
import TranslatorCore
import TextTranslation
import CompanionLink

/// Mac連携モードの受け側アプリ。
/// 同じWi-Fiの iPhone から文章を受け取り、Mac の Apple 翻訳(無料・端末内)で訳して返す。
@main
struct CompanionMacApp: App {
    var body: some Scene {
        WindowGroup {
            CompanionView()
        }
    }
}

/// 画面に並べる記録1行分。
struct CompanionLogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
}

/// Mac アプリの頭脳。通信係(サーバー)を動かし、翻訳の依頼に答える。
@MainActor
@Observable
final class CompanionModel {
    var state: CompanionConnectionState = .stopped
    var logs: [CompanionLogEntry] = []

    private let server = BonjourCompanionServer(deviceName: Host.current().localizedName ?? "Mac")
    private var translator: AppleTranslator?
    private var started = false

    /// 待ち受けを始める。画面が出たときに1回だけ呼ぶ。
    func start(translator: AppleTranslator) {
        guard !started else { return }
        started = true
        self.translator = translator
        server.onStateChange = { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }
        server.start()
        addLog("iPhone からの接続を待っています")
        Task { await self.serve() }
    }

    private func apply(_ newState: CompanionConnectionState) {
        guard newState != state else { return }
        state = newState
        switch newState {
        case .connected(let peer): addLog("接続しました:\(peer)")
        case .waiting: addLog("待ち受け中")
        case .failed(let reason): addLog("エラー:\(reason)")
        case .stopped, .connecting: break
        }
    }

    /// iPhone から届くメッセージを順番に処理する(アプリが動いている間ずっと)。
    private func serve() async {
        do {
            for try await message in server.messages() {
                handle(message)
            }
        } catch {
            addLog("受信が止まりました:\(error.localizedDescription)")
        }
    }

    private func handle(_ message: CompanionMessage) {
        switch message {
        case let .hello(version, name):
            addLog("あいさつ受信:\(name)(プロトコル v\(version))")
        case let .translateRequest(id, text, source):
            addLog("依頼:\(text)")
            // 翻訳は時間がかかるので、次の依頼を待たせないよう別の作業として動かす。
            Task { await self.respond(id: id, text: text, source: source) }
        default:
            addLog("未対応のメッセージを受信しました")
        }
    }

    private func respond(id: String, text: String, source: Language) async {
        let target = source.counterpart
        do {
            guard let translator = translator else { throw CompanionError.notConnected }
            let translated = try await translator.translate(text, from: source, to: target)
            try await server.send(.translation(
                id: id, text: translated, target: target, voice: .forSpoken(source)))
            addLog("返信:\(translated)")
        } catch {
            // 失敗を伝えても iPhone 側は時間切れで自分の翻訳に切り替えるので、ここでは記録だけする。
            try? await server.send(.error(message: error.localizedDescription))
            addLog("翻訳に失敗:\(error.localizedDescription)")
        }
    }

    private func addLog(_ text: String) {
        logs.append(CompanionLogEntry(text: text))
        // 記録が増えすぎないよう、古いものから捨てる。
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }
}

struct CompanionView: View {
    @State private var model = CompanionModel()
    @State private var translator = AppleTranslator()
    @State private var jaToVi = TranslationSession.Configuration(
        source: Locale.Language(identifier: "ja"), target: Locale.Language(identifier: "vi"))
    @State private var viToJa = TranslationSession.Configuration(
        source: Locale.Language(identifier: "vi"), target: Locale.Language(identifier: "ja"))

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 32))
                VStack(alignment: .leading) {
                    Text("JV Translator Companion").font(.title2)
                    Text("プロトコル v\(CompanionMessage.protocolVersion)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text(statusText)
            }

            List(model.logs.reversed()) { entry in
                HStack(alignment: .top) {
                    Text(entry.date, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(entry.text)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 360)
        .task {
            model.start(translator: translator)
        }
        // Apple の翻訳モデルは、初回に言語データのダウンロード確認が出る(無料)。
        .translationTask(jaToVi) { session in
            translator.register(session, from: .japanese, to: .vietnamese)
        }
        .translationTask(viToJa) { session in
            translator.register(session, from: .vietnamese, to: .japanese)
        }
    }

    private var statusText: String {
        switch model.state {
        case .stopped: return "停止中"
        case .waiting: return "iPhone を待っています"
        case .connecting: return "接続中…"
        case .connected(let peer): return "接続中:\(peer)"
        case .failed(let reason): return "エラー:\(reason)"
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .connected: return .green
        case .failed: return .red
        case .waiting, .connecting: return .orange
        case .stopped: return .gray
        }
    }
}
