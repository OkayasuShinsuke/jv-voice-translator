import XCTest
import TranslatorCore
@testable import SpeechSynthesis

final class VoiceSettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    // テストごとに新しい「使い捨てのメモ帳」を用意する。本物の設定は汚さない。
    override func setUp() {
        super.setUp()
        suiteName = "VoiceSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testReturnsDefaultsWhenNothingSaved() {
        let store = VoiceSettingsStore(defaults: defaults)
        XCTAssertEqual(store.profile(for: .a), VoiceProfile())
        XCTAssertEqual(store.profile(for: .b), VoiceProfile())
        XCTAssertNil(store.profile(for: .a).voiceIdentifier)
        XCTAssertEqual(store.profile(for: .a).rate, 0.5)
        XCTAssertEqual(store.profile(for: .a).pitch, 1.0)
    }

    func testSaveAndLoadRoundTrip() {
        let store = VoiceSettingsStore(defaults: defaults)
        let profile = VoiceProfile(voiceIdentifier: "com.apple.voice.premium.vi-VN.Linh", rate: 0.45, pitch: 1.2)
        store.save(profile, for: .a)

        // 別のインスタンスから読んでも同じ値が返る(=本当に保存されている)。
        let reloaded = VoiceSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.profile(for: .a), profile)
    }

    func testRolesAreStoredSeparately() {
        let store = VoiceSettingsStore(defaults: defaults)
        let a = VoiceProfile(voiceIdentifier: "voice.a", rate: 0.4, pitch: 0.9)
        let b = VoiceProfile(voiceIdentifier: "voice.b", rate: 0.6, pitch: 1.1)
        store.save(a, for: .a)
        store.save(b, for: .b)
        XCTAssertEqual(store.profile(for: .a), a)
        XCTAssertEqual(store.profile(for: .b), b)
        XCTAssertEqual(store.loadAll(), [.a: a, .b: b])
    }

    func testLoadAllFillsDefaultsForMissingRoles() {
        let store = VoiceSettingsStore(defaults: defaults)
        let b = VoiceProfile(voiceIdentifier: "voice.b")
        store.save(b, for: .b)
        XCTAssertEqual(store.loadAll(), [.a: VoiceProfile(), .b: b])
    }

    func testResetRestoresDefault() {
        let store = VoiceSettingsStore(defaults: defaults)
        store.save(VoiceProfile(voiceIdentifier: "voice.a", rate: 0.3), for: .a)
        store.reset(.a)
        XCTAssertEqual(store.profile(for: .a), VoiceSettingsStore.defaultProfile)
    }

    func testCorruptDataFallsBackToDefault() {
        let store = VoiceSettingsStore(defaults: defaults)
        defaults.set(Data("こわれたデータ".utf8), forKey: store.key(for: .a))
        XCTAssertEqual(store.profile(for: .a), VoiceProfile())
    }

    func testOutOfRangeValuesAreClamped() {
        let store = VoiceSettingsStore(defaults: defaults)
        store.save(VoiceProfile(voiceIdentifier: nil, rate: 5, pitch: -1), for: .b)
        let loaded = store.profile(for: .b)
        XCTAssertEqual(loaded.rate, VoiceProfile.rateRange.upperBound)
        XCTAssertEqual(loaded.pitch, VoiceProfile.pitchRange.lowerBound)
    }

    func testKeyPrefixSeparatesStores() {
        let first = VoiceSettingsStore(defaults: defaults, keyPrefix: "first.")
        let second = VoiceSettingsStore(defaults: defaults, keyPrefix: "second.")
        first.save(VoiceProfile(rate: 0.7), for: .a)
        XCTAssertEqual(second.profile(for: .a), VoiceProfile())
    }
}

final class VoiceOptionTests: XCTestCase {
    func testQualityLabels() {
        XCTAssertEqual(VoiceQuality.premium.label, "Premium")
        XCTAssertEqual(VoiceQuality.enhanced.label, "Enhanced")
        XCTAssertEqual(VoiceQuality.standard.label, "標準")
    }

    func testSortedByQualityThenName() {
        let options = [
            VoiceOption(identifier: "s", name: "Otoya", languageCode: "ja-JP", quality: .standard),
            VoiceOption(identifier: "e", name: "Kyoko", languageCode: "ja-JP", quality: .enhanced),
            VoiceOption(identifier: "p2", name: "Otoya", languageCode: "ja-JP", quality: .premium),
            VoiceOption(identifier: "p1", name: "Kyoko", languageCode: "ja-JP", quality: .premium),
        ]
        XCTAssertEqual(VoiceOption.sortedByQuality(options).map(\.identifier), ["p1", "p2", "e", "s"])
    }

    func testDisplayName() {
        let option = VoiceOption(identifier: "x", name: "Linh", languageCode: "vi-VN", quality: .enhanced)
        XCTAssertEqual(option.displayName, "Linh(Enhanced)")
    }

    func testRoleLanguages() {
        XCTAssertEqual(VoiceRole.a.synthesisLanguage, .vietnamese)
        XCTAssertEqual(VoiceRole.b.synthesisLanguage, .japanese)
    }
}
