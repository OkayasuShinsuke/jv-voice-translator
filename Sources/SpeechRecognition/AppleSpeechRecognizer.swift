// ワークストリーム① 音声認識のたたき台。
// Apple の Speech フレームワーク(無料・端末内処理に対応)を使う。
#if canImport(Speech) && canImport(AVFoundation)
import AVFoundation
import Foundation
import Speech
import TranslatorCore

public enum SpeechRecognitionError: Error {
    case notAuthorized
    case unsupportedLanguage(Language)
}

/// SFSpeechRecognizer を使った認識器。
/// 今は candidates の先頭の言語だけで聞き取る(自動言語判定はワークストリーム①の最初の課題)。
public final class AppleSpeechRecognizer: SpeechRecognizing, @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// true なら端末内だけで認識する(通信なし・無料)。対応していない言語では自動で false 扱い。
    public var preferOnDevice: Bool

    public init(preferOnDevice: Bool = true) {
        self.preferOnDevice = preferOnDevice
    }

    public static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public func transcripts(candidates: [Language]) -> AsyncThrowingStream<Transcript, Error> {
        AsyncThrowingStream { continuation in
            let language = candidates.first ?? .japanese
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue)),
                  recognizer.isAvailable else {
                continuation.finish(throwing: SpeechRecognitionError.unsupportedLanguage(language))
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if preferOnDevice && recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            do {
                #if os(iOS)
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                #endif
                let input = audioEngine.inputNode
                let format = input.outputFormat(forBus: 0)
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    request.append(buffer)
                }
                audioEngine.prepare()
                try audioEngine.start()
            } catch {
                continuation.finish(throwing: error)
                return
            }

            task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let best = result.bestTranscription
                    let confidences = best.segments.map { Double($0.confidence) }
                    let confidence = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
                    continuation.yield(Transcript(
                        text: best.formattedString,
                        language: language,
                        isFinal: result.isFinal,
                        confidence: confidence
                    ))
                    if result.isFinal { continuation.finish() }
                }
                if let error { continuation.finish(throwing: error) }
            }

            continuation.onTermination = { [weak self] _ in
                Task { await self?.stop() }
            }
        }
    }

    public func stop() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
#endif
