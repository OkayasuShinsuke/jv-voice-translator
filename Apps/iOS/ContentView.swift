import SwiftUI
import Translation
import TranslatorCore
import SpeechRecognition
import TextTranslation
import SpeechSynthesis

/// 最初の画面。「聞き取り開始」を押すと、話した言語を訳して読み上げる。
/// 今は仮の画面。各ワークストリームの部品ができたら、ここで組み立てる。
struct ContentView: View {
    @State private var language: Language = .japanese
    @State private var log: [TranslationEvent] = []
    @State private var isListening = false
    @State private var pipeline: TranslationPipeline?
    @State private var showsVoiceSettings = false
    @State private var translator = AppleTranslator()
    /// Mac連携の状態(Mac があれば翻訳を Mac に任せる)。
    @State private var companion = CompanionStatus()
    @State private var jaToVi = TranslationSession.Configuration(
        source: Locale.Language(identifier: "ja"), target: Locale.Language(identifier: "vi"))
    @State private var viToJa = TranslationSession.Configuration(
        source: Locale.Language(identifier: "vi"), target: Locale.Language(identifier: "ja"))

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("話す言語", selection: $language) {
                    Text("日本語 → Tiếng Việt(声A)").tag(Language.japanese)
                    Text("Tiếng Việt → 日本語(声B)").tag(Language.vietnamese)
                }
                .pickerStyle(.segmented)

                Label(companion.label, systemImage: companion.isConnected ? "laptopcomputer.and.iphone" : "iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List(log.indices.reversed(), id: \.self) { index in
                    VStack(alignment: .leading) {
                        Text(log[index].source.text).font(.headline)
                        Text(log[index].translatedText).foregroundStyle(.secondary)
                    }
                }

                Button(isListening ? "停止" : "聞き取り開始") {
                    Task { await toggle() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("日越 翻訳")
            .toolbar {
                Button("声の設定", systemImage: "speaker.wave.2") { showsVoiceSettings = true }
            }
            .sheet(isPresented: $showsVoiceSettings) { VoiceSettingsView() }
        }
        .task { companion.start() }
        // Apple の翻訳モデルは、初回に言語データのダウンロード確認が出る(無料)。
        .translationTask(jaToVi) { session in
            translator.register(session, from: .japanese, to: .vietnamese)
        }
        .translationTask(viToJa) { session in
            translator.register(session, from: .vietnamese, to: .japanese)
        }
    }

    private func toggle() async {
        if isListening {
            await pipeline?.stop()
            isListening = false
            return
        }
        guard await AppleSpeechRecognizer.requestAuthorization() else { return }
        let recognizer = LanguageLockedRecognizer(base: AppleSpeechRecognizer(), language: language)
        let pipeline = TranslationPipeline(
            recognizer: recognizer,
            translator: ChunkedTranslator(base: companion.makeTranslator(local: translator)),
            synthesizer: AppleSpeechSynthesizer(profiles: VoiceSettingsStore().loadAll()))
        self.pipeline = pipeline
        isListening = true
        try? await pipeline.run { event in
            Task { @MainActor in log.append(event) }
        }
        isListening = false
    }
}

/// 画面で選んだ言語で聞き取らせるための小さな包み紙。自動言語判定ができたら不要になる。
struct LanguageLockedRecognizer: SpeechRecognizing {
    let base: SpeechRecognizing
    let language: Language

    func transcripts(candidates: [Language]) -> AsyncThrowingStream<Transcript, Error> {
        base.transcripts(candidates: [language])
    }

    func stop() async { await base.stop() }
}
