// ワークストリーム③ 自然な音声合成のたたき台。AVSpeechSynthesizer(無料・端末内)を使う。
#if canImport(AVFoundation)
import AVFoundation
import TranslatorCore

// 声の設定(VoiceProfile)は VoiceProfile.swift にある。保存は VoiceSettingsStore が担当する。

public final class AppleSpeechSynthesizer: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private var finished: CheckedContinuation<Void, Never>?
    public var profiles: [VoiceRole: VoiceProfile]

    public init(profiles: [VoiceRole: VoiceProfile] = [.a: VoiceProfile(), .b: VoiceProfile()]) {
        self.profiles = profiles
        super.init()
        synthesizer.delegate = self
    }

    /// その言語で使える声のうち、Premium > Enhanced > 標準 の順で最も自然なもの。
    /// Premium/Enhanced の声は iPhone の「設定 > アクセシビリティ > 読み上げコンテンツ > 声」から無料でダウンロードできる。
    public static func bestVoice(for language: Language) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language.rawValue }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: language.rawValue)
    }

    public func speak(_ text: String, language: Language, voice: VoiceRole) async throws {
        let profile = profiles[voice] ?? VoiceProfile()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = profile.voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? Self.bestVoice(for: language)
        utterance.rate = profile.rate
        utterance.pitchMultiplier = profile.pitch
        await withCheckedContinuation { continuation in
            // 前の読み上げの待ちが残っていたら先に終わらせる(待ちっぱなしを防ぐ)。
            resumeFinished()
            finished = continuation
            synthesizer.speak(utterance)
        }
    }

    public func stop() async {
        synthesizer.stopSpeaking(at: .immediate)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        resumeFinished()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        resumeFinished()
    }

    private func resumeFinished() {
        finished?.resume()
        finished = nil
    }
}
#endif
