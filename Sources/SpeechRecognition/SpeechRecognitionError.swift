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
