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
    /// マイク・音声認識の許可が無い、または聞き取り中にエラーが起きたときに出す案内(空文字なら非表示)。
    @State private var recognitionErrorTitle = ""
    @State private var recognitionErrorDetail = ""
    @State private var showsRecognitionError = false
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
            .alert(recognitionErrorTitle, isPresented: $showsRecognitionError) {
                Button("OK") {}
            } message: {
                Text(recognitionErrorDetail)
            }
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
                            PulsingRing()
                        }
                    }
            }
            .accessibilityLabel(isListening ? "聞き取りを止める" : "聞き取りを始める")
        }
        .padding()
        .background(.regularMaterial)
    }

    /// 完成した吹き出しをタップしたときに、その訳を読み上げ直す。
    ///
    /// 聞き取り中は、パイプライン用の読み上げ係とタップ再生用の読み上げ係が別々に動いているため、
    /// 同時に話すと声が二重に鳴ってしまう(issue #18)。安全のため、聞き取り中はタップ再生を無効にする。
    private func replay(_ message: ChatMessage) {
        guard !isListening, let translatedText = message.translatedText else { return }
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
        guard await AppleSpeechRecognizer.requestAuthorization() else {
            // 許可が無いままだと何も起こらず、利用者が「押したのに動かない」と困ってしまうため、
            // 「設定アプリでオンにしてください」という案内を出す。
            showRecognitionError(SpeechRecognitionError.notAuthorized)
            return
        }
        conversation.clear()
        let recognizer = makeRecognizer(for: mode)
        let pipeline = TranslationPipeline(
            recognizer: recognizer,
            translator: ChunkedTranslator(base: companion.makeTranslator(local: translator)),
            synthesizer: AppleSpeechSynthesizer(profiles: VoiceSettingsStore().loadAll()))
        self.pipeline = pipeline
        isListening = true
        do {
            try await pipeline.run(
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
        } catch {
            // 聞き取り中に何が起きたのか分からないまま黙って止まると不安にさせてしまうため、
            // 分かりやすい日本語で理由を伝える。
            showRecognitionError(error)
        }
        isListening = false
    }

    /// エラーの中身を、アラートにそのまま出せる日本語の2行(タイトル・詳しい説明)に変換して表示する。
    private func showRecognitionError(_ error: Error) {
        if let localized = error as? LocalizedError {
            recognitionErrorTitle = localized.errorDescription ?? "聞き取りでエラーが起きました"
            recognitionErrorDetail = localized.recoverySuggestion ?? "もう一度お試しください。"
        } else {
            recognitionErrorTitle = "聞き取りでエラーが起きました"
            recognitionErrorDetail = "もう一度お試しください。"
        }
        showsRecognitionError = true
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

/// マイクボタンの上に出す、赤い輪が外へふわっと広がって消える「脈打つ」合図。
///
/// たとえ話:水面に石を落としたときに広がっていく波紋のように、輪が広がりながら薄くなって消える。
/// これを毎回繰り返すことで「今、聞いていますよ」と伝える。
///
/// 気をつけたこと(以前のバグ):この輪は「聞き取り中(isListening)」の間だけ画面に出てくるが、
/// 広がる・消えるという見た目の変化(アニメーション)は `isListening` が「変わった」ときにしか起きない。
/// ところが、この輪が画面に現れた時点ではもう `isListening` は true になった後なので、
/// 現れてから一度も「変わらない」→ アニメーションが一度も動かず、輪は透明(opacity 0)のまま
/// 固まって見えなくなってしまっていた。そこで、輪自身が持つ `isExpanded` という
/// 別の「見た目用のスイッチ」を用意し、輪が現れた直後(`onAppear`)に false → true と
/// 切り替えることで、確実にアニメーションの「変化」を起こすようにしている。
struct PulsingRing: View {
    @State private var isExpanded = false

    var body: some View {
        Circle()
            .stroke(Color.red.opacity(0.6), lineWidth: 3)
            .scaleEffect(isExpanded ? 1.4 : 1.0)
            .opacity(isExpanded ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    isExpanded = true
                }
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
