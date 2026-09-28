// ワークストリーム② 翻訳のたたき台。Apple の Translation フレームワーク(無料・端末内)を使う。
#if canImport(Translation)
import Foundation
import Translation
import TranslatorCore

/// SwiftUI の `.translationTask` から受け取った TranslationSession を包んで、Translating として使えるようにする。
/// 言語ペアごとにセッションが必要なので、日→越 と 越→日 の2つを渡す。
@available(iOS 18.0, macOS 15.0, *)
public final class AppleTranslator: Translating, @unchecked Sendable {
    private var sessions: [String: TranslationSession] = [:]

    public init() {}

    public func register(_ session: TranslationSession, from source: Language, to target: Language) {
        sessions[key(source, target)] = session
    }

    public func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        guard let session = sessions[key(source, target)] else {
            throw TranslationSetupError.sessionMissing(source: source, target: target)
        }
        return try await session.translate(text).targetText
    }

    private func key(_ source: Language, _ target: Language) -> String {
        "\(source.rawValue)->\(target.rawValue)"
    }
}

public enum TranslationSetupError: Error {
    case sessionMissing(source: Language, target: Language)
}
#endif
