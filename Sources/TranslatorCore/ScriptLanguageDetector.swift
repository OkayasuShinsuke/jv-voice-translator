import Foundation

/// 文字の種類だけで日本語かベトナム語かを判定する、軽くて速い判定器。
/// ひらがな・カタカナ・漢字があれば日本語、ベトナム語特有の文字(ă, ơ, ư, đ など)があればベトナム語。
/// Apple の NLLanguageRecognizer を使う判定器は SpeechRecognition 側に置く。
public struct ScriptLanguageDetector: LanguageDetecting {
    public init() {}

    public func detect(_ text: String) -> Language? {
        var japanese = 0
        var vietnamese = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x4E00...0x9FFF, 0xFF66...0xFF9F:
                japanese += 1
            case 0x00C0...0x024F, 0x1EA0...0x1EFF:
                vietnamese += 1
            default:
                break
            }
        }
        if japanese == 0 && vietnamese == 0 { return nil }
        return japanese >= vietnamese ? .japanese : .vietnamese
    }
}
