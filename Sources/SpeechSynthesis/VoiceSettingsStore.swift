// 声A・声Bの設定を iPhone に保存する係。UserDefaults(アプリ用の小さなメモ帳)を使う。
import Foundation
import TranslatorCore

/// 声A・声Bの VoiceProfile を保存・読み込みする。
///
/// たとえるなら「声ごとの引き出し」。引き出しが空なら、ふつうの設定(defaultProfile)を返す。
/// テストでは本物のメモ帳を汚さないよう、UserDefaults(suiteName:) で作った別のメモ帳を渡す。
public struct VoiceSettingsStore {
    private let defaults: UserDefaults
    private let keyPrefix: String

    /// 何も保存されていないときの設定(声は自動・ふつうの速さ・ふつうの高さ)。
    public static let defaultProfile = VoiceProfile()

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "voiceSettings.profile.") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    /// 保存に使うキー(例: "voiceSettings.profile.a")。
    public func key(for role: VoiceRole) -> String {
        keyPrefix + role.rawValue
    }

    /// 保存されている設定を読む。無い・壊れているときは defaultProfile を返す。
    public func profile(for role: VoiceRole) -> VoiceProfile {
        guard let data = defaults.data(forKey: key(for: role)),
              let profile = try? JSONDecoder().decode(VoiceProfile.self, from: data)
        else { return Self.defaultProfile }
        return profile.clamped()
    }

    /// 設定を保存する。
    public func save(_ profile: VoiceProfile, for role: VoiceRole) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key(for: role))
    }

    /// 声A・声Bの両方をまとめて読む。AppleSpeechSynthesizer(profiles:) にそのまま渡せる。
    public func loadAll() -> [VoiceRole: VoiceProfile] {
        var result: [VoiceRole: VoiceProfile] = [:]
        for role in VoiceRole.allRoles {
            result[role] = profile(for: role)
        }
        return result
    }

    /// 設定を消して、ふつうの設定に戻す。
    public func reset(_ role: VoiceRole) {
        defaults.removeObject(forKey: key(for: role))
    }
}
