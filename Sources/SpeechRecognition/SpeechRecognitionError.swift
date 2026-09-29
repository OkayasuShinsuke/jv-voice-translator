import Foundation
import TranslatorCore

/// 音声認識で起こりうるエラー。
public enum SpeechRecognitionError: Error, Equatable {
    /// 音声認識の使用が許可されていない(設定アプリで許可が必要)。
    case notAuthorized
    /// その言語の認識器がこの端末・OSでは使えない。
    case unsupportedLanguage(Language)
    /// iOS 26 の SpeechAnalyzer が使えない(古いOS・非対応の端末など)。
    case speechAnalyzerUnavailable
    /// 候補の言語すべてで認識器を用意できなかった。
    case noAvailableEngine
    /// 認識がすぐに失敗する状態が続いたので、あきらめて止めた。
    case repeatedFailures(Language)
}

// 画面にそのまま出せる、日本語初心者にも分かりやすいエラー文。
// たとえ話:エラーの名前(notAuthorized など)はプログラムのための「型番」で、
// そのままでは利用者に見せても伝わらない。ここでは型番から「お店の張り紙」のような
// やさしい日本語に変換している。
extension SpeechRecognitionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "マイクや音声認識が許可されていません。"
        case .unsupportedLanguage(let language):
            return "\(language.beginnerFriendlyName)の音声認識が、この端末では使えません。"
        case .speechAnalyzerUnavailable:
            return "新しい音声認識の仕組み(SpeechAnalyzer)が、この端末やOSのバージョンでは使えません。"
        case .noAvailableEngine:
            return "音声認識の準備ができませんでした。"
        case .repeatedFailures(let language):
            return "\(language.beginnerFriendlyName)の聞き取りがうまくいかない状態が続いたので、いったん止めました。"
        }
    }

    /// 「どうすればいいか」を添える一言。設定アプリへの案内など、次の一歩を示す。
    public var recoverySuggestion: String? {
        switch self {
        case .notAuthorized:
            return "「設定」アプリ →「JV Translator」→「マイク」と「音声認識」を両方ともオンにしてください。"
        case .unsupportedLanguage, .speechAnalyzerUnavailable, .noAvailableEngine:
            return "しばらくしてからもう一度お試しください。改善しない場合はOSを最新版に更新してください。"
        case .repeatedFailures:
            return "周りの音が大きすぎないか確認し、マイクの近くではっきり話してからもう一度お試しください。"
        }
    }
}

private extension Language {
    /// エラー文の中で使う、日本語初心者にも読みやすい言語名。
    var beginnerFriendlyName: String {
        switch self {
        case .japanese: return "日本語"
        case .vietnamese: return "ベトナム語"
        }
    }
}
