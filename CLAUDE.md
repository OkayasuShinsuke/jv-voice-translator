# CLAUDE.md(AI エージェント向けの作業メモ)

- 目的:iPhone 向け日越リアルタイム音声翻訳アプリ。詳細は README.md と docs/ を参照。
- 無料の機能だけを使う。iPhone 端末内の処理を優先し、Mac 連携モード(CompanionLink)は追加の選択肢。
- ワークストリームごとに担当フォルダが決まっている(docs/WORKSTREAMS.md)。担当外のフォルダは原則変更しない。
- `TranslatorCore/Protocols.swift` の変更は全ワークストリームに影響するので、プルリクエストで理由を説明する。
- Apple 専用フレームワークを使うコードは `#if canImport(...)` で囲み、`TranslatorCore` と `Evaluation` は Apple 以外でもビルドできる状態を保つ。
- 変更には `swift test` で動くテストを付ける。CI(.github/workflows/ci.yml)が緑になるまで直す。
- 利用者は Python / Swift 初心者。コメントとドキュメントは日本語で、たとえ話を交えて分かりやすく書く。
