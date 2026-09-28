import Foundation
import TranslatorCore

// 「Mac があれば Mac に頼み、ダメなら iPhone 自身で訳す」ための仕組み。
// 例えるなら、まず隣の物知りな助手(Mac)に聞き、3秒たっても返事がなければ自分で辞書を引く、という動き。

/// 主役(ふつうは Mac)に頼んだ結果。
public enum PrimaryOutcome: Sendable {
    /// 訳が返ってきた。
    case success(String)
    /// エラーで失敗した。
    case failure(Error)
    /// 時間切れ。
    case timedOut
    /// そもそもつながっていないので頼まなかった。
    case unavailable
}

/// 控え(iPhone 自身)に切り替えた理由。
public enum FallbackReason: String, Sendable, Equatable {
    case unavailable
    case failed
    case timedOut
    case emptyResult
}

/// どちらの訳を使うかの結論。
public enum FallbackDecision: Sendable, Equatable {
    /// 主役の訳をそのまま使う。
    case usePrimary(String)
    /// 控えで訳し直す。
    case useFallback(FallbackReason)
}

/// 「結果を見て、どちらを使うか決める」だけの純粋な決まり。
/// 通信も時間も使わないので、テストで全部のパターンを簡単に確かめられる。
public enum FallbackPolicy {
    public static func decide(_ outcome: PrimaryOutcome) -> FallbackDecision {
        switch outcome {
        case .success(let text):
            // 空っぽの訳は役に立たないので、自分で訳し直す。
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .useFallback(.emptyResult)
            }
            return .usePrimary(text)
        case .failure:
            return .useFallback(.failed)
        case .timedOut:
            return .useFallback(.timedOut)
        case .unavailable:
            return .useFallback(.unavailable)
        }
    }
}

/// 主役(Mac)→ 控え(iPhone)の順で試す Translating 実装。
/// パイプラインから見ると普通の翻訳器なので、今までのコードを変えずに差し込める。
public struct FallbackTranslator: Translating {
    public let primary: Translating
    public let fallback: Translating
    /// 主役を待つ最大の秒数。
    public let timeout: TimeInterval
    private let isPrimaryAvailable: @Sendable () async -> Bool
    private let onDecision: (@Sendable (FallbackDecision) -> Void)?

    /// - Parameters:
    ///   - primary: まず頼む翻訳器(例:RemoteTranslator = Mac)。
    ///   - fallback: ダメだったときの翻訳器(例:iPhone 内の Apple 翻訳)。
    ///   - timeout: 主役を待つ秒数。初期値は 3 秒。
    ///   - isPrimaryAvailable: 主役が今使えるか(Mac とつながっているか)。false なら待たずに控えを使う。
    ///   - onDecision: どちらを使ったかの知らせ(画面表示や記録用。なくてもよい)。
    public init(
        primary: Translating,
        fallback: Translating,
        timeout: TimeInterval = 3,
        isPrimaryAvailable: @escaping @Sendable () async -> Bool = { true },
        onDecision: (@Sendable (FallbackDecision) -> Void)? = nil
    ) {
        self.primary = primary
        self.fallback = fallback
        self.timeout = timeout
        self.isPrimaryAvailable = isPrimaryAvailable
        self.onDecision = onDecision
    }

    public func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        let outcome: PrimaryOutcome
        if await isPrimaryAvailable() {
            let primary = self.primary
            outcome = await Self.attempt(timeout: timeout) {
                try await primary.translate(text, from: source, to: target)
            }
        } else {
            outcome = .unavailable
        }
        let decision = FallbackPolicy.decide(outcome)
        onDecision?(decision)
        switch decision {
        case .usePrimary(let translated):
            return translated
        case .useFallback:
            return try await fallback.translate(text, from: source, to: target)
        }
    }

    /// operation を実行し、timeout 秒たっても終わらなければ「時間切れ」とする。
    /// 主役が止まらない作りでも待ち続けないよう、「先に届いた方だけを採用する」方式にしている。
    static func attempt(
        timeout: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> String
    ) async -> PrimaryOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<PrimaryOutcome, Never>) in
            let gate = OutcomeGate(continuation)
            let work = Task {
                do {
                    let text = try await operation()
                    gate.resume(with: .success(text))
                } catch {
                    gate.resume(with: .failure(error))
                }
            }
            let nanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
            Task {
                try? await Task.sleep(nanoseconds: nanoseconds)
                if gate.resume(with: .timedOut) {
                    work.cancel()
                }
            }
        }
    }
}

/// 「最初に来た1回だけ通す」改札。2回目以降は無視する。
final class OutcomeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PrimaryOutcome, Never>?

    init(_ continuation: CheckedContinuation<PrimaryOutcome, Never>) {
        self.continuation = continuation
    }

    /// 通れたら true、すでに誰かが通っていたら false。
    @discardableResult
    func resume(with outcome: PrimaryOutcome) -> Bool {
        lock.lock()
        let current = continuation
        continuation = nil
        lock.unlock()
        guard let current = current else { return false }
        current.resume(returning: outcome)
        return true
    }
}
