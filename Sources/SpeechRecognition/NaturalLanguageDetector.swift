#if canImport(NaturalLanguage)
import NaturalLanguage
import TranslatorCore

/// Apple の NaturalLanguage を使った言語判定。日本語とベトナム語の2択に絞って判定する。
public struct NaturalLanguageDetector: LanguageDetecting {
    public init() {}

    public func detect(_ text: String) -> Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.japanese, .vietnamese]
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .japanese?: return .japanese
        case .vietnamese?: return .vietnamese
        default: return nil
        }
    }
}
#endif
