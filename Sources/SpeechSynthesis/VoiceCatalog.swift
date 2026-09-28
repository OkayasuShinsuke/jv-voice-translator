// 端末に入っている声の一覧を、画面で使いやすい VoiceOption に変換する係。
#if canImport(AVFoundation)
import AVFoundation
import TranslatorCore

public enum VoiceCatalog {
    /// その言語で使える声の一覧(Premium > Enhanced > 標準 の順)。
    /// Premium / Enhanced の声は「設定 > アクセシビリティ > 読み上げコンテンツ > 声」から無料で追加できる。
    public static func voices(for language: Language) -> [VoiceOption] {
        let options = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language.rawValue }
            .map(option(from:))
        return VoiceOption.sortedByQuality(options)
    }

    /// AVFoundation の声を、素の Swift の VoiceOption に変換する。
    public static func option(from voice: AVSpeechSynthesisVoice) -> VoiceOption {
        VoiceOption(
            identifier: voice.identifier,
            name: voice.name,
            languageCode: voice.language,
            quality: quality(from: voice.quality))
    }

    static func quality(from quality: AVSpeechSynthesisVoiceQuality) -> VoiceQuality {
        switch quality {
        case .premium: return .premium
        case .enhanced: return .enhanced
        default: return .standard
        }
    }
}
#endif
