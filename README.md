# JV Translator(日越リアルタイム音声翻訳)

iPhone で日本語とベトナム語をリアルタイムに通訳するアプリです。

| 話した言語 | 訳す先 | 読み上げの声 |
|---|---|---|
| 日本語 | ベトナム語 | 声A |
| ベトナム語 | 日本語 | 声B |

- **無料**:Apple 純正の端末内機能(Speech / Translation / AVSpeechSynthesizer)を優先します。
- **iPhone 単体で完結**が基本。必要なら **Mac 連携モード**で Mac に重い処理を任せられます。

## フォルダ構成

```
Package.swift            部品(モジュール)の一覧
Sources/
  TranslatorCore/        共通の約束事(プロトコル)と「聞く→訳す→話す」パイプライン
  SpeechRecognition/     ① 音声認識
  TextTranslation/       ② 翻訳(長文対策つき)
  SpeechSynthesis/       ③ 自然な音声合成(声A/声B)
  Evaluation/            ④ 正確性の評価(CER/WER/chrF・遅延)
  CompanionLink/         Mac 連携モードの通信
Tests/                   自動テスト
Apps/iOS/                iPhone アプリ本体(画面)
Apps/macOS/              Mac コンパニオンアプリ
Evaluation/datasets/     評価用の例文データ
project.yml              Xcode プロジェクトの設計図(XcodeGen 用)
docs/                    設計・開発の進め方
```

## 動かし方(Mac で)

```bash
brew install xcodegen      # Xcode プロジェクトを作る道具を入れる(初回だけ)
swift test                 # 部品の自動テストを実行
xcodegen generate          # project.yml から JVTranslator.xcodeproj を作る
open JVTranslator.xcodeproj
```

Xcode で `JVTranslator` を選び、実機の iPhone を選んで ▶︎ を押します(Signing で自分の Apple ID のチームを選択)。

## ドキュメント

- [設計(アーキテクチャ)](docs/ARCHITECTURE.md)
- [4つのワークストリーム](docs/WORKSTREAMS.md)
- [自動開発フローの提案](docs/AUTOMATION.md)
