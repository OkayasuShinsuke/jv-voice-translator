import SwiftUI
import TextTranslation

/// 「翻訳データがまだ端末に入っていません」を伝える案内バナー。
///
/// たとえ話:カーナビの地図データのようなもの。使う前に一度ダウンロードしておかないと、
/// 現地(翻訳したい言語)の案内ができない。このバナーは「まだ地図が入っていません、
/// 設定アプリからダウンロードしてください」と教えてくれる看板。
struct AvailabilityBanner: View {
    let report: LanguageAvailabilityReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("翻訳データの準備が必要です", systemImage: "arrow.down.circle")
                .font(.subheadline.bold())
            Text(bodyText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("「設定」→「一般」→「言語と地域」→「翻訳言語」から、日本語とベトナム語をダウンロードしてください。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.2))
    }

    private var bodyText: String {
        var lines: [String] = []
        if report.japaneseToVietnamese != .installed {
            lines.append("日本語→ベトナム語: \(report.japaneseToVietnamese.japaneseDescription)")
        }
        if report.vietnameseToJapanese != .installed {
            lines.append("ベトナム語→日本語: \(report.vietnameseToJapanese.japaneseDescription)")
        }
        return lines.joined(separator: " / ")
    }
}
