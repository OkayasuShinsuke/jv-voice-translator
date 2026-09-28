import SwiftUI
import CompanionLink

/// Mac連携モードの受け側アプリ(仮)。
/// 同じWi-Fiの iPhone から音声や文章を受け取り、Macの強い処理能力で認識・翻訳して返す。
@main
struct CompanionMacApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 48))
                Text("JV Translator Companion").font(.title2)
                Text("iPhone からの接続を待っています(実装予定)").foregroundStyle(.secondary)
                Text("プロトコル v\(CompanionMessage.protocolVersion)").font(.caption)
            }
            .padding(40)
        }
    }
}
