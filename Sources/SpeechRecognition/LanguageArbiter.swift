import Foundation
import TranslatorCore

/// 1つの言語の認識器が出した「この文はこう聞こえた」という候補。
public struct RecognitionCandidate: Sendable, Equatable {
    public var language: Language
    public var text: String
    /// 0.0〜1.0。認識器が出さない場合は nil。
    public var confidence: Double?

    public init(language: Language, text: String, confidence: Double? = nil) {
        self.language = language
        self.text = text
        self.confidence = confidence
    }
}

/// 日本語の認識器とベトナム語の認識器が同じ音声を聞いたとき、どちらの結果を採用するかを決める審判。
///
/// たとえるなら、日本語担当とベトナム語担当の2人の通訳者が同時にメモを取り、
/// 審判が「自信の度合い(確信度)」と「メモの文字がその言語らしいか(言語判定)」で点数を付けて、
/// 点数の高いほうを採用する仕組みです。
///
/// 点数の付け方:
/// - 確信度 × `confidenceWeight`(確信度が無いときは `neutralConfidence` を使う)
/// - 判定器ごとに、判定結果が候補の言語と同じなら +`detectorWeight`、違う言語なら -`detectorWeight`
/// 同点のときは、候補の並び順で先にあるほうを選ぶ。
///
/// Apple のフレームワークを使わない純粋な計算だけなので、テストで動きを確かめられます。
public struct LanguageArbiter: Sendable {
    /// 文字から言語を推定する判定器(文字種判定、NaturalLanguage など)。
    public var detectors: [any LanguageDetecting]
    public var confidenceWeight: Double
    /// 認識器が確信度を出さなかったときに使う値(ちょうど真ん中の 0.5)。
    public var neutralConfidence: Double
    public var detectorWeight: Double

    public init(
        detectors: [any LanguageDetecting] = [ScriptLanguageDetector()],
        confidenceWeight: Double = 1.0,
        neutralConfidence: Double = 0.5,
        detectorWeight: Double = 0.25
    ) {
        self.detectors = detectors
        self.confidenceWeight = confidenceWeight
        self.neutralConfidence = neutralConfidence
        self.detectorWeight = detectorWeight
    }

    /// 1つの候補の点数。大きいほど「その言語で話された」可能性が高い。
    public func score(_ candidate: RecognitionCandidate) -> Double {
        let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return -Double.infinity }
        let confidence = min(1, max(0, candidate.confidence ?? neutralConfidence))
        var score = confidence * confidenceWeight
        for detector in detectors {
            guard let detected = detector.detect(text) else { continue }
            score += detected == candidate.language ? detectorWeight : -detectorWeight
        }
        return score
    }

    /// 候補の中から1つを選ぶ。文字が空の候補は選ばない。全部空なら nil。
    /// 選んだ候補の文字は前後の空白を取り除いて返す。
    public func choose(_ candidates: [RecognitionCandidate]) -> RecognitionCandidate? {
        var best: RecognitionCandidate?
        var bestScore = -Double.infinity
        for candidate in candidates {
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let value = score(candidate)
            // 「より大きい」ときだけ入れ替えるので、同点なら先の候補が残る。
            if best == nil || value > bestScore {
                var trimmed = candidate
                trimmed.text = text
                best = trimmed
                bestScore = value
            }
        }
        return best
    }
}
