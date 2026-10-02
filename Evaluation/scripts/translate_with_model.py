#!/usr/bin/env python3
"""無料の翻訳モデル(既定: Meta の NLLB-200)で評価データを訳し、訳文ファイル(JSON)を作るスクリプト。

たとえ話:
  評価データは「試験問題」、このスクリプトは「別の受験生(オープンな翻訳モデル)」です。
  受験生に問題を解かせて答案(訳文ファイル)を書かせ、採点は Swift の `jv-eval` が行います。

      Evaluation/datasets/*.json ──(このスクリプト)──> mt-hypotheses.json
                                                          │
      swift run jv-eval --translator file:mt-hypotheses.json  ← 同じ物差し(chrF)で採点

  GitHub の Mac ではアプリ本番の Apple 翻訳を動かせないので、まずは「無料モデルなら何点取れるか」
  という基準点(ベースライン)を毎週記録します。あとで iPhone 実機の訳文を同じ形の JSON で
  書き出せば、アプリの翻訳もまったく同じ方法で採点できます。

使い方(リポジトリの一番上のフォルダで実行):
  python3 -m pip install -r Evaluation/scripts/requirements-mt.txt
  python3 Evaluation/scripts/translate_with_model.py --out mt-hypotheses.json
  swift run jv-eval --translator file:mt-hypotheses.json --out mt-report.md

  --dataset    評価データのフォルダまたは .json(既定: Evaluation/datasets)
  --out        訳文ファイルの書き出し先
  --model      Hugging Face のモデル名(既定: facebook/nllb-200-distilled-600M)
  --batch-size 一度にまとめて訳す文の数(大きいほど速いがメモリを使う)
  --limit      各ファイルの先頭から何件だけ訳すか(動作確認用。0 なら全部)

モデルのライセンス: NLLB-200 は CC BY-NC 4.0(非商用)。ここでは「評価の物差し」として
CI で動かすだけで、アプリには組み込みません。
"""

import argparse
import json
import sys
import time
from pathlib import Path

# アプリの言語コード → NLLB の言語コード
NLLB_CODES = {"ja-JP": "jpn_Jpan", "vi-VN": "vie_Latn"}
COUNTERPART = {"ja-JP": "vi-VN", "vi-VN": "ja-JP"}


def load_samples(path: Path) -> list:
    """jv-eval と同じく、フォルダなら中の .json をファイル名順に全部読む。"""
    files = sorted(path.glob("*.json")) if path.is_dir() else [path]
    samples = []
    for file in files:
        samples.extend(json.loads(file.read_text(encoding="utf-8")))
    return samples


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dataset", type=Path, default=Path("Evaluation/datasets"))
    parser.add_argument("--out", type=Path, default=Path("mt-hypotheses.json"))
    parser.add_argument("--model", default="facebook/nllb-200-distilled-600M")
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    # 重いライブラリは使うときに読み込む(--help だけなら不要なので)
    import torch
    from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

    samples = load_samples(args.dataset)
    if args.limit:
        samples = samples[:args.limit]
    print(f"{len(samples)} 件を {args.model} で訳します", file=sys.stderr)

    tokenizer = AutoTokenizer.from_pretrained(args.model)
    model = AutoModelForSeq2SeqLM.from_pretrained(args.model)
    model.eval()

    hypotheses = []
    total_start = time.perf_counter()
    # 「日→越」と「越→日」で言語の指定が違うので、言語ごとにまとめて訳す
    for language, target in COUNTERPART.items():
        group = [s for s in samples if s["language"] == language]
        tokenizer.src_lang = NLLB_CODES[language]
        target_id = tokenizer.convert_tokens_to_ids(NLLB_CODES[target])
        for start in range(0, len(group), args.batch_size):
            batch = group[start:start + args.batch_size]
            inputs = tokenizer([s["referenceTranscript"] for s in batch],
                               return_tensors="pt", padding=True, truncation=True, max_length=256)
            batch_start = time.perf_counter()
            with torch.no_grad():
                generated = model.generate(**inputs, forced_bos_token_id=target_id,
                                           max_new_tokens=256, num_beams=4)
            per_sentence = (time.perf_counter() - batch_start) / len(batch)
            outputs = tokenizer.batch_decode(generated, skip_special_tokens=True)
            for sample, output in zip(batch, outputs):
                hypotheses.append({"id": sample["id"], "language": language,
                                   "source": sample["referenceTranscript"], "output": output.strip(),
                                   "secondsPerSentence": round(per_sentence, 3)})
            print(f"  {language}: {min(start + len(batch), len(group))}/{len(group)}", file=sys.stderr)

    args.out.write_text(json.dumps(hypotheses, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    elapsed = time.perf_counter() - total_start
    print(f"書き出し: {args.out}({len(hypotheses)} 件、{elapsed:.0f} 秒)", file=sys.stderr)


if __name__ == "__main__":
    main()
