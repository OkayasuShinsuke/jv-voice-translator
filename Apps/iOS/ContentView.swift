import SwiftUI
import Translation
import TranslatorCore
import SpeechRecognition
import TextTranslation
import SpeechSynthesis
import ConversationKit

/// 聞き取りの言語モード。
///
/// たとえ話:通訳さんに「日本語だけ聞いて」「ベトナム語だけ聞いて」と指定する代わりに、
/// 「どちらの言語で話しても自動で聞き分けて」とお願いできるのが `automatic`。
enum RecognitionMode: String, CaseIterable, Hashable, Identifiable {
    case automatic
    case japanese
    case vietnamese

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "自動"
        case .japanese: return "日本語"
        case .vietnamese: return "Tiếng Việt"
        }
    }
}

/// 最初の画面。LINEのトーク画面のように、話した言葉と訳した言葉を吹き出しで並べる。
/// 下の丸いマイクボタンを押すと聞き取りが始まり、話すたびに吹き出しが増えていく。
struct ContentView: View {
    @State private var mode: RecognitionMode = .automatic
    /// 会話の吹き出し一覧を持つノート(ワークストリーム⑥)。
    @State private var conversation = ConversationStore()
    @State private var isListening = false
    @State private var pipeline: TranslationPipeline?
    @State private var showsVoiceSettings = false
    @State private var translator = AppleTranslator()
    /// タップして訳を読み上げ直すための、聞き取り用とは別の読み上げ係。
    @State private var replaySynthesizer = AppleSpeechSynthesizer()
    /// Mac連携の状態(Mac があれば翻訳を Mac に任せる)。
    @State private var companion = CompanionStatus()
    /// 翻訳データ(日⇔越)が端末にダウンロード済みかどうかの報告。nil の間はまだ調べている最中。
    @State private var availability: LanguageAvailabilityReport?
    @State private var jaToVi = TranslationSession.Configuration(
        source: Locale.Language(identifier: "ja"), target: Locale.Language(identifier: "vi"))
    @State private var viToJa = TranslationSession.Configuration(
        source: Locale.Language(identifier: "vi"), target: Locale.Language(identifier: "ja"))

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let availability, !availability.isReady {
                    AvailabilityBanner(report: availability)
                }
                ChatView(messages: conversation.messages, onTapMessage: replay)
                bottomBar
            }
            .navigationTitle("日越 翻訳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Label(companion.label, systemImage: companion.isConnected ? "laptopcomputer.and.iphone" : "iphone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("声の設定", systemImage: "speaker.wave.2") { showsVoiceSettings = true }
                }
            }
            .sheet(isPresented: $showsVoiceSettings) { VoiceSettingsView() }
        }
        .task { companion.start() }
        .task { availability = await LanguageAvailabilityReport.check(using: AppleLanguageAvailabilityChecker()) }
        // Apple の翻訳モデルは、初回に言語データのダウンロード確認が出る(無料)。
        .translationTask(jaToVi) { session in
            translator.register(session, from: .japanese, to: .vietnamese)
        }
        .translationTask(viToJa) { session in
            translator.register(session, from: .vietnamese, to: .japanese)
        }
    }

    /// 画面いちばん下の、言語切り替えと聞き取りボタンをまとめた場所。
    private var bottomBar: some View {
        VStack(spacing: 12) {
            Picker("聞き取る言語", selection: $mode) {
                ForEach(RecognitionMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isListening)

            Button {
                Task { await toggle() }
            } label: {
                Image(systemName: isListening ? "mic.fill" : "mic")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(isListening ? Color.red : Color.green)
                    .clipShape(Circle())
                    // 聞き取り中は、赤い輪がふわっと広がって消える「脈打つ」ような合図を出す。
                    .overlay {
                        if isListening {
                            Circle()
                                .stroke(Color.red.opacity(0.6), lineWidth: 3)
                                .scaleEffect(isListening ? 1.4 : 1.0)
                                .opacity(isListening ? 0 : 1)
                                .animation(
                                    .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                    value: isListening)
                        }
                    }
            }
            .accessibilityLabel(isListening ? "聞き取りを止める" : "聞き取りを始める")
        }
        .padding()
        .background(.regularMaterial)
    }

    /// 完成した吹き出しをタップしたときに、その訳を読み上げ直す。
    private func replay(_ message: ChatMessage) {
        guard let translatedText = message.translatedText else { return }
        replaySynthesizer.profiles = VoiceSettingsStore().loadAll()
        Task {
            try? await replaySynthesizer.speak(
                translatedText, language: message.spokenLanguage.counterpart, voice: message.voice)
        }
    }

    private func toggle() async {
        if isListening {
            await pipeline?.stop()
            isListening = false
            return
        }
        guard await AppleSpeechRecognizer.requestAuthorization() else { return }
        conversation.clear()
        let recognizer = makeRecognizer(for: mode)
        let pipeline = TranslationPipeline(
            recognizer: recognizer,
            translator: ChunkedTranslator(base: companion.makeTranslator(local: translator)),
            synthesizer: AppleSpeechSynthesizer(profiles: VoiceSettingsStore().loadAll()))
        self.pipeline = pipeline
        isListening = true
        try? await pipeline.run(
            onTranscript: { transcript in
                Task { @MainActor in
                    if transcript.isFinal {
                        conversation.finalize(transcript)
                    } else {
                        conversation.updatePartial(transcript)
                    }
                }
            },
            onTranslationChunk: { chunkSoFar in
                // 1文目の翻訳ができた時点で、吹き出しの訳の部分をその場で書き換える。
                Task { @MainActor in conversation.updateTranslationProgress(chunkSoFar) }
            },
            onEvent: { event in
                Task { @MainActor in conversation.complete(with: event) }
            })
        isListening = false
    }

    /// 選んだモードに応じて、聞き取り役(自動判定 or 固定言語)を作る。
    private func makeRecognizer(for mode: RecognitionMode) -> SpeechRecognizing {
        switch mode {
        case .automatic:
            return AutoLanguageRecognizer()
        case .japanese:
            return LanguageLockedRecognizer(base: AppleSpeechRecognizer(), language: .japanese)
        case .vietnamese:
            return LanguageLockedRecognizer(base: AppleSpeechRecognizer(), language: .vietnamese)
        }
    }
}

/// 画面で選んだ言語だけで聞き取らせるための小さな包み紙。
/// 中身(base)が一時停止に対応していれば、その機能もそのまま素通しする。
struct LanguageLockedRecognizer: PausableSpeechRecognizing {
    let base: SpeechRecognizing
    let language: Language

    func transcripts(candidates: [Language]) -> AsyncThrowingStream<Transcript, Error> {
        base.transcripts(candidates: [language])
    }

    func stop() async { await base.stop() }

    func pause() async { await (base as? PausableSpeechRecognizing)?.pause() }
    func resume() async { await (base as? PausableSpeechRecognizing)?.resume() }
}
