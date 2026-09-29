import SwiftUI
import ConversationKit

/// 会話全体を、LINEのトーク画面のように上から下へ並べて出す画面。
/// 新しい吹き出しが増えたら、自動でいちばん下(最新)までスクロールする。
struct ChatView: View {
    let messages: [ChatMessage]
    /// 完成した吹き出しをタップしたときに、その吹き出しを渡して知らせる。
    var onTapMessage: (ChatMessage) -> Void = { _ in }

    /// LINE風の、薄い青みがかった背景色(ライトモード)。
    private static let lightBackground = Color(red: 0.55, green: 0.67, blue: 0.85)
    /// ダークモードでは、同じ色合いをぐっと暗くしたものを使う。
    private static let darkBackground = Color(red: 0.10, green: 0.14, blue: 0.20)

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark ? Self.darkBackground : Self.lightBackground
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty {
                    FirstLaunchGuideView()
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            ChatBubble(message: message) { onTapMessage(message) }
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .background(backgroundColor)
            .onChange(of: messages) { _, newValue in
                guard let last = newValue.last else { return }
                withAnimation {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onAppear {
                guard let last = messages.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

/// 会話がまだ1つも無いとき(アプリを初めて開いたときなど)に出す、案内メッセージ。
///
/// たとえ話:初めて入ったお店で、何も貼り紙が無いと何をすればいいか分からず戸惑ってしまう。
/// ここでは「下のマイクのボタンを押して話しかけてね」という、いちばん最初の一歩を教える貼り紙を出す。
struct FirstLaunchGuideView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "mic.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("まだ会話がありません")
                .font(.headline)
            Text("下のマイクのボタンを押して、日本語かベトナム語で話しかけてみましょう。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}
