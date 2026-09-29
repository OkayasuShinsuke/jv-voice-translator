#!/usr/bin/env python3
"""FLORES-200 の日本語⇔ベトナム語の対訳を、評価データ(JSON)に変換するスクリプト。

たとえ話:
  FLORES-200 は「同じ英語ニュース記事を、プロの翻訳者が 200 言語に訳した問題集」です。
  1 行目はどの言語でも同じ文の訳なので、日本語ファイルの 5 行目とベトナム語ファイルの
  5 行目を並べれば、そのまま 1 組の対訳になります(Tatoeba のような対応表は要りません)。

      jpn_Jpan.devtest        vie_Latn.devtest
      1行目: 「我々が…」  ⇔  1行目: "Chúng tôi…"
      2行目: ノバスコシア…  ⇔  2行目: Tiến sĩ Ehud Ur…
        …                        …

  Tatoeba(日常の短い文)と違い、FLORES は Wikipedia / Wikinews の長めの文なので、
  ワークストリーム②「長文でも正確に訳せるか」の確認に向いています。

使い方(リポジトリの一番上のフォルダで実行):
  python3 Evaluation/scripts/import_flores.py
  python3 Evaluation/scripts/import_flores.py --per-direction 80 --seed 1

  --per-direction : 「日本語→ベトナム語」「ベトナム語→日本語」それぞれ何件作るか
  --seed          : くじ引き(ランダム抽出)の番号。同じ番号なら毎回同じ文が選ばれる
  --cache         : ダウンロードしたファイルを置く場所(2回目以降はダウンロードを省略)

Python の標準ライブラリだけで動きます(pip install は不要)。

ライセンス: FLORES-200 は CC BY-SA 4.0 です。出典を書き、この JSON も同じ
CC BY-SA 4.0 で扱います(Evaluation/datasets/flores_ATTRIBUTION.md に書き出します)。
"""

import argparse
import json
import random
import sys
import tarfile
import urllib.request
from pathlib import Path

URL = "https://dl.fbaipublicfiles.com/nllb/flores200_dataset.tar.gz"
# devtest(本番テスト用)を使う。dev は学習の調整に使われがちなので避ける。
SPLIT = "devtest"
MEMBERS = {
    "ja": f"flores200_dataset/{SPLIT}/jpn_Jpan.{SPLIT}",
    "vi": f"flores200_dataset/{SPLIT}/vie_Latn.{SPLIT}",
    "meta": f"flores200_dataset/metadata_{SPLIT}.tsv",
}

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_JSON = REPO_ROOT / "Evaluation/datasets/flores.json"
OUT_ATTRIBUTION = REPO_ROOT / "Evaluation/datasets/flores_ATTRIBUTION.md"

# 長すぎる文は音声で話す場面から離れるので除く(FLORES は平均 20 語ほど)。
JA_MAX_CHARS = 90
VI_MAX_WORDS = 45


def download(cache: Path) -> Path:
    """tar.gz(約 25MB)を1回だけダウンロードする。"""
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / Path(URL).name
    if not path.exists():
        print(f"ダウンロード中: {URL}", file=sys.stderr)
        urllib.request.urlretrieve(URL, path)
    return path


def read_lines(archive: Path) -> dict:
    """tar.gz を展開せずに、必要な3ファイルだけを行のリストとして読む。"""
    result = {}
    with tarfile.open(archive, "r:gz") as tar:
        for key, name in MEMBERS.items():
            member = tar.extractfile(f"./{name}") or tar.extractfile(name)
            result[key] = member.read().decode("utf-8").splitlines()
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--per-direction", type=int, default=50)
    parser.add_argument("--seed", type=int, default=20260929)
    parser.add_argument("--cache", type=Path, default=Path(".flores-cache"))
    args = parser.parse_args()

    lines = read_lines(download(args.cache))
    ja, vi = lines["ja"], lines["vi"]
    meta = lines["meta"][1:]  # 1行目は見出し(URL, domain, …)
    if not (len(ja) == len(vi) == len(meta)):
        sys.exit(f"行数がそろっていません: ja={len(ja)} vi={len(vi)} meta={len(meta)}")

    # 行番号(0 始まり)の候補。長さの条件を満たすものだけ残す。
    candidates = [i for i in range(len(ja))
                  if len(ja[i]) <= JA_MAX_CHARS and len(vi[i].split()) <= VI_MAX_WORDS]
    print(f"条件を満たす対訳: {len(candidates)} 組 / 全 {len(ja)} 組", file=sys.stderr)

    need = args.per_direction * 2
    if len(candidates) < need:
        sys.exit(f"対訳が足りません({len(candidates)} < {need})。--per-direction を減らしてください。")

    # 同じ文を「日→越」と「越→日」の両方に使うと、片方で答えを見たことになるので
    # くじ引きで重ならないように2つに分ける。
    chosen = random.Random(args.seed).sample(candidates, need)
    ja_side = sorted(chosen[:args.per_direction])
    vi_side = sorted(chosen[args.per_direction:])

    samples, rows = [], []
    for i, line in enumerate(ja_side, 1):  # 日本語を話す → ベトナム語に訳す
        sample_id = f"ja-flores-{i:03d}"
        samples.append({"id": sample_id, "language": "ja-JP",
                        "referenceTranscript": ja[line], "referenceTranslation": vi[line]})
        rows.append((sample_id, line))
    for i, line in enumerate(vi_side, 1):  # ベトナム語を話す → 日本語に訳す
        sample_id = f"vi-flores-{i:03d}"
        samples.append({"id": sample_id, "language": "vi-VN",
                        "referenceTranscript": vi[line], "referenceTranslation": ja[line]})
        rows.append((sample_id, line))

    OUT_JSON.write_text(json.dumps(samples, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    out = [
        "# FLORES-200 由来の評価データの出典",
        "",
        "`flores.json` の文は Meta AI の [FLORES-200](https://github.com/facebookresearch/flores/tree/main/flores200)"
        f"(`{SPLIT}`)から取得しました。",
        "ライセンスは [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) です。",
        "`flores.json` も同じ CC BY-SA 4.0 で提供します。",
        "`Evaluation/scripts/import_flores.py` で作り直せます。",
        "",
        "> NLLB Team et al. \"No Language Left Behind: Scaling Human-Centered Machine Translation\" (2022).",
        "",
        "| 評価データの id | devtest の行番号 | 元記事 |",
        "|---|---|---|",
    ]
    for sample_id, line in rows:
        url = meta[line].split("\t")[0]
        out.append(f"| {sample_id} | {line + 1} | {url} |")
    OUT_ATTRIBUTION.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"書き出し: {OUT_JSON.relative_to(REPO_ROOT)} ({len(samples)} 件)", file=sys.stderr)


if __name__ == "__main__":
    main()
