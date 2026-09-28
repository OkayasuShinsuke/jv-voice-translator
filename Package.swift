// swift-tools-version: 5.9
// 翻訳アプリの「部品箱」。iOSアプリとMacコンパニオンアプリの両方がこのパッケージを使う。
import PackageDescription

let package = Package(
    name: "JVTranslator",
    defaultLocalization: "ja",
    // swift-tools-version 5.9 には .v18 などの名前がないので、文字列で版を指定する。
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "TranslatorCore", targets: ["TranslatorCore"]),
        .library(name: "SpeechRecognition", targets: ["SpeechRecognition"]),
        .library(name: "TextTranslation", targets: ["TextTranslation"]),
        .library(name: "SpeechSynthesis", targets: ["SpeechSynthesis"]),
        .library(name: "Evaluation", targets: ["Evaluation"]),
        .library(name: "CompanionLink", targets: ["CompanionLink"]),
    ],
    targets: [
        // 共通の約束事(プロトコル)とパイプライン。Appleのフレームワークに依存しない。
        .target(name: "TranslatorCore"),

        // ワークストリーム① 音声認識(速く・正確に)
        .target(name: "SpeechRecognition", dependencies: ["TranslatorCore"]),
        // ワークストリーム② 翻訳(長文でも速く・正確に)
        // ※ Apple純正の Translation フレームワークと名前がぶつからないよう TextTranslation とする。
        .target(name: "TextTranslation", dependencies: ["TranslatorCore"]),
        // ワークストリーム③ 自然な音声合成(声A / 声B)
        .target(name: "SpeechSynthesis", dependencies: ["TranslatorCore"]),
        // ワークストリーム④ 正確性の評価(WER/CER/chrF と遅延)
        .target(name: "Evaluation", dependencies: ["TranslatorCore"]),
        // 評価をコマンドで回す道具(`swift run jv-eval`)。CI でレポートを作るのに使う。
        .executableTarget(name: "jv-eval", dependencies: ["Evaluation", "TranslatorCore"]),
        // Mac連携モード(Macで処理してiPhoneへ送る)
        .target(name: "CompanionLink", dependencies: ["TranslatorCore"]),

        .testTarget(name: "TranslatorCoreTests", dependencies: ["TranslatorCore"]),
        .testTarget(name: "TextTranslationTests", dependencies: ["TextTranslation"]),
        .testTarget(name: "EvaluationTests", dependencies: ["Evaluation"]),
        .testTarget(name: "CompanionLinkTests", dependencies: ["CompanionLink"]),
    ]
)
