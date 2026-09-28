import SwiftUI
import TranslatorCore
import ConversationKit

/// LINEのトーク画面のような、1つの吹き出し。
///
/// 右(自分が日本語で話した)は緑、左(相手がベトナム語で話した)は白の吹き出しにする。
/// 吹き出しの中には「元の言葉」と「訳した言葉」を、細い区切り線をはさんで両方見せる。
struct ChatBubble: View {
    let message: ChatMessage
    /// 完成した吹き出しをタップしたときに呼ばれる(訳を読み上げ直す)。
    var onTap: () -> Void = {}

    /// 右側(緑)の吹き出しの色。LINEの送信側の緑に寄せている。
    private static let rightBubbleColor = Color(red: 0.02, green: 0.78, blue: 0.33)

    private var isRight: Bool { message.side == .right }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isRight {
                Spacer(minLength: 40)
                captionColumn
                bubbleBody
            } else {
                bubbleBody
                captionColumn
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: isRight ? .trailing : .leading)
        .onTapGesture {
            if case .done = message.state { onTap() }
        }
    }

    /// 吹き出しの外側、LINEのように時刻や声・国旗を小さく出す列。
    private var captionColumn: some View {
        VStack(alignment: isRight ? .trailing : .leading, spacing: 2) {
            Text(flagAndVoiceLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(timeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var flagAndVoiceLabel: String {
        let flag = message.spokenLanguage == .japanese ? "🇯🇵" : "🇻🇳"
        let voiceName = message.voice == .a ? "声A" : "声B"
        return "\(flag) \(voiceName)"
    }

    private var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.date)
    }

    @ViewBuilder
    private var bubbleBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch message.state {
            case .listening:
                Text(message.originalText.isEmpty ? "…" : message.originalText)
                    .font(.body)
                TypingIndicator()
            case .translating:
                Text(message.originalText)
                    .font(.body)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("翻訳中…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .done:
                Text(message.originalText)
                    .font(.body)
                Divider()
                Text(message.translatedText ?? "")
                    .font(.subheadline)
                    .foregroundStyle(isRight ? .white.opacity(0.85) : .secondary)
            case .failed(let errorMessage):
                Text(message.originalText)
                    .font(.body)
                Text("うまく訳せませんでした: \(errorMessage)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .foregroundStyle(bubbleTextColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var bubbleTextColor: Color {
        isRight ? .white : .primary
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isRight {
            Self.rightBubbleColor
        } else {
            Color(.systemBackground)
        }
    }
}

/// 「聞き取り中」の吹き出しに出す、点が増えたり減ったりするアニメーション。
/// たとえるなら、チャットアプリでよく見る「相手が入力中…」の表示と同じもの。
struct TypingIndicator: View {
    @State private var dotCount = 1
    @State private var timer: Timer?

    var body: some View {
        Text(String(repeating: "。", count: dotCount))
            .font(.caption)
            .foregroundStyle(.secondary)
            .onAppear { startAnimating() }
            .onDisappear { timer?.invalidate() }
    }

    private func startAnimating() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            Task { @MainActor in
                dotCount = dotCount % 3 + 1
            }
        }
    }
}
