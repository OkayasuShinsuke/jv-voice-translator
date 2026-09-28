import Foundation

/// 長文を文ごとに分けて、訳せた文から順に受け取れる翻訳器の「差し込み口」。
///
/// たとえ話:料理が1皿ずつ出てくるレストランのように、全部の文の翻訳が終わるのを待たずに
/// 1文目からテーブルへ運べる(=読み上げを始められる)ようにするための仕組み。
///
/// `TranslationPipeline` は、渡された翻訳器がこのプロトコルにも対応していれば、
/// こちらを優先して使い、1文目の訳ができた時点で読み上げを始める。対応していない
/// 普通の `Translating` を渡した場合は、これまでどおり全文を訳し終えてから読み上げる。
public protocol StreamingTranslating: Translating {
    /// 文ごとに訳し、訳せた文から元の順番どおりに1つずつ流す。
    func translateStream(_ text: String, from source: Language, to target: Language) -> AsyncThrowingStream<String, Error>
}
