// ワークストリーム② 翻訳:言語データ(辞書のようなもの)が端末に入っているかを調べる部品。
// Apple の翻訳は「言語データ」を端末にダウンロードしてから使う。
// 入っていないと初回の翻訳でダウンロード待ちになるので、先に状態を調べて画面で案内できるようにする。
import Foundation
import TranslatorCore
#if canImport(Translation)
import Translation
#endif

/// 1つの言語ペア(例: 日本語→ベトナム語)が今どんな状態か。
/// Apple のフレームワークに依存しない、ふつうの Swift の列挙型。
public enum LanguagePairStatus: String, Sendable, Equatable, CaseIterable {
    /// 言語データが端末に入っている。すぐ翻訳できる。
    case installed
    /// 対応はしているが、言語データのダウンロードが必要。
    case needsDownload
    /// この言語ペアの翻訳には対応していない(または Translation が使えない環境)。
    case unsupported

    /// 今すぐ(通信なしで)翻訳できるか。
    public var canTranslateNow: Bool { self == .installed }

    /// 画面に出すための短い日本語の説明。
    public var japaneseDescription: String {
        switch self {
        case .installed: return "利用できます"
        case .needsDownload: return "言語データのダウンロードが必要です"
        case .unsupported: return "この組み合わせには対応していません"
        }
    }
}

/// 翻訳の向き(元の言語 → 訳す先の言語)。
public struct LanguagePair: Hashable, Sendable {
    public var source: Language
    public var target: Language

    public init(source: Language, target: Language) {
        self.source = source
        self.target = target
    }

    /// 日本語 → ベトナム語
    public static let japaneseToVietnamese = LanguagePair(source: .japanese, target: .vietnamese)
    /// ベトナム語 → 日本語
    public static let vietnameseToJapanese = LanguagePair(source: .vietnamese, target: .japanese)
}

/// 言語ペアの状態を調べる「差し込み口」。
/// 本物は AppleLanguageAvailabilityChecker、テストでは偽物(フェイク)を差し込む。
public protocol LanguageAvailabilityChecking: Sendable {
    func status(for pair: LanguagePair) async -> LanguagePairStatus
}

/// 日→越 と 越→日 の両方の状態をまとめたもの。
public struct LanguageAvailabilityReport: Sendable, Equatable {
    public var japaneseToVietnamese: LanguagePairStatus
    public var vietnameseToJapanese: LanguagePairStatus

    public init(japaneseToVietnamese: LanguagePairStatus, vietnameseToJapanese: LanguagePairStatus) {
        self.japaneseToVietnamese = japaneseToVietnamese
        self.vietnameseToJapanese = vietnameseToJapanese
    }

    /// 両方向ともすぐ翻訳できるか。
    public var isReady: Bool {
        japaneseToVietnamese.canTranslateNow && vietnameseToJapanese.canTranslateNow
    }

    /// どちらかの向きでダウンロードが必要か。
    public var needsDownload: Bool {
        japaneseToVietnamese == .needsDownload || vietnameseToJapanese == .needsDownload
    }

    /// 両方向の状態を調べて、1つの報告にまとめる。
    public static func check(using checker: LanguageAvailabilityChecking) async -> LanguageAvailabilityReport {
        let jaToVi = await checker.status(for: .japaneseToVietnamese)
        let viToJa = await checker.status(for: .vietnameseToJapanese)
        return LanguageAvailabilityReport(japaneseToVietnamese: jaToVi, vietnameseToJapanese: viToJa)
    }
}

/// Apple の `LanguageAvailability` を使って、本当の状態を調べる。
/// Translation フレームワークが無い環境(Linux など)では、いつも `.unsupported` を返す。
public struct AppleLanguageAvailabilityChecker: LanguageAvailabilityChecking {
    public init() {}

    public func status(for pair: LanguagePair) async -> LanguagePairStatus {
        #if canImport(Translation)
        // 対応OS(iOS 26 / macOS 15)は LanguageAvailability が使える版(iOS 18 / macOS 15 以降)を満たしている。
        return await AppleLanguageAvailabilityBridge.status(for: pair)
        #else
        return .unsupported
        #endif
    }
}

#if canImport(Translation)
/// Apple の型を、上の純粋な Swift の列挙型に「翻訳」する橋渡し役。
enum AppleLanguageAvailabilityBridge {
    static func status(for pair: LanguagePair) async -> LanguagePairStatus {
        let availability = LanguageAvailability()
        let status = await availability.status(
            from: Locale.Language(identifier: pair.source.languageCode),
            to: Locale.Language(identifier: pair.target.languageCode)
        )
        switch status {
        case .installed: return .installed
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }
}
#endif
