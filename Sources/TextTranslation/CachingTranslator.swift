// ワークストリーム② 翻訳:同じ文を何度も訳さないための「覚え書き(キャッシュ)」。
import Foundation
import TranslatorCore

/// 一度訳した文を覚えておき、同じ文が来たら覚えている訳をすぐ返す包み紙。
/// たとえ話:よく聞かれる質問の答えをメモ帳に書いておき、次からはメモを見て即答するイメージ。
/// 「こんにちは」「ありがとう」のような決まり文句は何度も出てくるので、2回目以降が速くなる。
///
/// - メモ帳のページ数(capacity)には限りがある。いっぱいになったら、
///   いちばん長く使われていない訳から消す(LRU = Least Recently Used)。
/// - `actor` にしているので、複数の場所から同時に呼ばれても中身が壊れない。
/// - 翻訳に失敗したときは覚えない(次に呼ばれたらもう一度 base に頼む)。
public actor CachingTranslator: Translating {
    /// 覚えるときの見出し。「元の言語・訳す先の言語・文」の3つがそろって同じときだけ同じ訳とみなす。
    struct CacheKey: Hashable {
        let source: Language
        let target: Language
        let text: String
    }

    private let base: Translating
    /// 覚えておける訳の最大数。0 以下なら何も覚えない。
    public let capacity: Int
    private var storage: [CacheKey: String] = [:]
    /// 使った順番。先頭がいちばん古く、末尾がいちばん新しい。
    private var usageOrder: [CacheKey] = []

    /// キャッシュから返せた回数(当たり)。
    public private(set) var hitCount = 0
    /// base に翻訳を頼んだ回数(外れ)。
    public private(set) var missCount = 0

    public init(base: Translating, capacity: Int = 200) {
        self.base = base
        self.capacity = max(0, capacity)
    }

    /// 今覚えている訳の数。
    public var count: Int { storage.count }

    public func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        let key = CacheKey(source: source, target: target, text: text)
        if let cached = storage[key] {
            hitCount += 1
            markAsRecentlyUsed(key)
            return cached
        }
        missCount += 1
        // ここで await している間に、別の呼び出しが先に同じ文を覚えることもある(actor の再入)。
        // その場合も下の store が上書きするだけなので、中身は壊れない。
        let translated = try await base.translate(text, from: source, to: target)
        store(translated, for: key)
        return translated
    }

    /// 覚えている訳をすべて忘れる。
    public func removeAll() {
        storage.removeAll()
        usageOrder.removeAll()
    }

    private func store(_ value: String, for key: CacheKey) {
        guard capacity > 0 else { return }
        storage[key] = value
        markAsRecentlyUsed(key)
        // ページが足りなくなったら、いちばん古いものから捨てる。
        while storage.count > capacity, let oldest = usageOrder.first {
            usageOrder.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }

    private func markAsRecentlyUsed(_ key: CacheKey) {
        if let index = usageOrder.firstIndex(of: key) {
            usageOrder.remove(at: index)
        }
        usageOrder.append(key)
    }
}
