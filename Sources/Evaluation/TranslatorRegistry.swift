import Foundation
import TranslatorCore

/// 入力をそのまま返すだけの「なにもしない翻訳」。
/// CI(GitHub の Mac)では Apple の翻訳機能が動かないため、評価の仕組みそのものを確かめる
/// 「ものさしの基準点」として使う。点数はほぼ 0 になるのが正常。
public struct IdentityTranslator: Translating {
    public init() {}

    public func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        text
    }
}

/// 翻訳エンジンの「名簿」。名前(例: "identity")からエンジンを作れるようにする。
/// 本物のエンジン(Apple Translation など)ができたら、`register` で名前を足すだけで
/// `jv-eval --translator <名前>` から同じデータで採点できる。
public struct TranslatorRegistry {
    /// エンジンを作る関数。評価のたびに新しく作れるよう、完成品ではなく「作り方」を登録する。
    public typealias Factory = () -> Translating

    private var factories: [String: Factory] = [:]

    public init() {}

    /// 最初から入っているエンジンの名簿。
    public static var builtIn: TranslatorRegistry {
        var registry = TranslatorRegistry()
        registry.register("identity") { IdentityTranslator() }
        return registry
    }

    /// 名前とエンジンの作り方を登録する。同じ名前なら上書き。
    public mutating func register(_ name: String, factory: @escaping Factory) {
        factories[name] = factory
    }

    /// 登録済みの名前(アルファベット順)。
    public var names: [String] {
        factories.keys.sorted()
    }

    /// 名前からエンジンを作る。登録されていなければ nil。
    public func make(_ name: String) -> Translating? {
        factories[name]?()
    }
}
