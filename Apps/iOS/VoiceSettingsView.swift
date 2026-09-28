import SwiftUI
import TranslatorCore
import SpeechSynthesis

/// 声A・声Bの「声・速さ・高さ」を選ぶ設定画面。
/// 値を動かすとすぐ iPhone に保存され、次に「聞き取り開始」を押したときから使われる。
struct VoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let store: VoiceSettingsStore
    @State private var profileA: VoiceProfile
    @State private var profileB: VoiceProfile
    /// 試し聞き用の読み上げ係(翻訳用とは別に1つ持つ)。
    @State private var previewer = AppleSpeechSynthesizer()

    init(store: VoiceSettingsStore = VoiceSettingsStore()) {
        self.store = store
        _profileA = State(initialValue: store.profile(for: .a))
        _profileB = State(initialValue: store.profile(for: .b))
    }

    var body: some View {
        NavigationStack {
            Form {
                VoiceRoleSection(role: .a, profile: $profileA, previewer: previewer)
                VoiceRoleSection(role: .b, profile: $profileB, previewer: previewer)
                Section("もっと自然な声にするには") {
                    Text("iPhone の「設定 > アクセシビリティ > 読み上げコンテンツ > 声」を開き、ベトナム語・日本語の声を選んで「Premium(高品質)」や「Enhanced(拡張)」をダウンロードしてください(無料)。ダウンロード後にこの画面を開き直すと一覧に出てきます。")
                        .font(.footnote)
                }
            }
            .navigationTitle("声の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            // 値が変わるたびに保存する。
            .onChange(of: profileA) { _, newValue in store.save(newValue, for: .a) }
            .onChange(of: profileB) { _, newValue in store.save(newValue, for: .b) }
            .onDisappear {
                Task { await previewer.stop() }
            }
        }
    }
}

/// 声1つぶん(声A または 声B)の設定欄。
private struct VoiceRoleSection: View {
    let role: VoiceRole
    @Binding var profile: VoiceProfile
    let previewer: AppleSpeechSynthesizer
    @State private var voices: [VoiceOption] = []

    var body: some View {
        Section {
            Picker("声", selection: $profile.voiceIdentifier) {
                Text("自動(いちばん高品質な声)").tag(String?.none)
                ForEach(voices) { voice in
                    Text(voice.displayName).tag(Optional(voice.identifier))
                }
            }

            VStack(alignment: .leading) {
                Text("速さ: \(String(format: "%.2f", profile.rate))")
                Slider(value: $profile.rate, in: VoiceProfile.rateRange)
            }

            VStack(alignment: .leading) {
                Text("高さ: \(String(format: "%.2f", profile.pitch))")
                Slider(value: $profile.pitch, in: VoiceProfile.pitchRange)
            }

            HStack {
                Button("試し聞き") {
                    Task { await preview() }
                }
                Spacer()
                Button("元に戻す") {
                    profile = VoiceSettingsStore.defaultProfile
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        } header: {
            Text(role.displayName)
        } footer: {
            if voices.isEmpty {
                Text("この言語の声が見つかりません。下の案内から声をダウンロードしてください。")
            }
        }
        .onAppear(perform: loadVoices)
    }

    private func loadVoices() {
        voices = VoiceCatalog.voices(for: role.synthesisLanguage)
        // 保存していた声が消されていたら「自動」に戻す。
        if let id = profile.voiceIdentifier, !voices.contains(where: { $0.identifier == id }) {
            profile.voiceIdentifier = nil
        }
    }

    private func preview() async {
        await previewer.stop()
        previewer.profiles[role] = profile
        try? await previewer.speak(role.sampleText, language: role.synthesisLanguage, voice: role)
    }
}
