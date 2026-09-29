#!/usr/bin/env python3
"""Tatoeba(タトエバ)の日本語⇔ベトナム語の対訳を、評価データ(JSON)に変換するスクリプト。

たとえ話:
  Tatoeba は「世界中のボランティアが作った、みんなの対訳帳」です。
  このスクリプトは、その対訳帳から
    1. 日本語のページ(日本語の文の一覧)
    2. ベトナム語のページ(ベトナム語の文の一覧)
    3. 「この日本語文 ⇔ このベトナム語文 は同じ意味」という対応表(リンク)
  の3つをダウンロードし、対応表を見ながら1組ずつ取り出して、
  Evaluation/datasets/ の JSON と同じ形(id・言語・原文・訳文)に書き写します。

使い方(リポジトリの一番上のフォルダで実行):
  python3 Evaluation/scripts/import_tatoeba.py
  python3 Evaluation/scripts/import_tatoeba.py --per-direction 150 --seed 1

  --per-direction : 「日本語→ベトナム語」「ベトナム語→日本語」それぞれ何件作るか
  --seed          : くじ引き(ランダム抽出)の番号。同じ番号なら毎回同じ文が選ばれる
  --cache         : ダウンロードしたファイルを置く場所(2回目以降はダウンロードを省略)

Python の標準ライブラリだけで動きます(pip install は不要)。

ライセンス: Tatoeba の文は CC BY 2.0 FR です。作者名を書けば自由に使えるので、
出典と各文の投稿者を Evaluation/datasets/tatoeba_ATTRIBUTION.md に書き出します。
"""

import argparse
import bz2
import csv
import json
import random
import sys
import urllib.request
from pathlib import Path

BASE_URL = "https://downloads.tatoeba.org/exports/per_language"
FILES = {
    "jpn": "jpn/jpn_sentences_detailed.tsv.bz2",
    "vie": "vie/vie_sentences_detailed.tsv.bz2",
    "links": "jpn/jpn-vie_links.tsv.bz2",
}

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_JSON = REPO_ROOT / "Evaluation/datasets/tatoeba.json"
# 評価の読み込みは .json だけを読むので、出典は .md にしておく(データと混ざらない)
OUT_ATTRIBUTION = REPO_ROOT / "Evaluation/datasets/tatoeba_ATTRIBUTION.md"

# 品質フィルタ: 短すぎる文(「はい。」など)は採点の意味が薄く、
# 長すぎる文は音声で話す場面から離れるので除く。
JA_MIN_CHARS, JA_MAX_CHARS = 6, 60
VI_MIN_WORDS, VI_MAX_WORDS = 3, 30


def download(name: str, cache: Path) -> Path:
    """ファイルを1つダウンロードする(すでにあれば使い回す)。"""
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / Path(FILES[name]).name
    if not path.exists():
        url = f"{BASE_URL}/{FILES[name]}"
        print(f"ダウンロード中: {url}", file=sys.stderr)
        with urllib.request.urlopen(url, timeout=120) as response:
            path.write_bytes(response.read())
    return path


def read_tsv(path: Path):
    """bz2 で圧縮されたタブ区切りファイルを1行ずつ読む。"""
    with bz2.open(path, "rt", encoding="utf-8", newline="") as f:
        yield from csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE)


def load_sentences(path: Path) -> dict:
    """{文の番号: (本文, 投稿者名)} の辞書を作る。

    ファイルの1行 = 番号 / 言語 / 本文 / 投稿者 / 作成日時 / 更新日時
    """
    sentences = {}
    for row in read_tsv(path):
        if len(row) >= 4:
            # 投稿者が退会などでいない文は "\\N" になっているので、分かる言葉に置き換える
            user = row[3] if row[3] != "\\N" else "(投稿者不明)"
            sentences[row[0]] = (row[2].strip(), user)
    return sentences


# 「」や "" で囲まれた会話のかけ合いは、1人が話す音声の評価には向かないので除く
QUOTE_CHARS = "「」『』\""


def good_ja(text: str) -> bool:
    if any(c in text for c in QUOTE_CHARS):
        return False
    return JA_MIN_CHARS <= len(text) <= JA_MAX_CHARS


def good_vi(text: str) -> bool:
    if any(c in text for c in QUOTE_CHARS):
        return False
    return VI_MIN_WORDS <= len(text.split()) <= VI_MAX_WORDS


def build_pairs(jpn: dict, vie: dict, links_path: Path) -> list:
    """対応表から「1対1」の組だけを取り出す。

    1つの日本語文に訳が3つある、のような場合は「どれが正解か」が1つに決まらず
    採点がぶれるので、ここでは両側とも相手が1つだけの組を使う。
    """
    links = [(a, b) for a, b in (row[:2] for row in read_tsv(links_path))
             if a in jpn and b in vie]
    ja_count, vi_count = {}, {}
    for a, b in links:
        ja_count[a] = ja_count.get(a, 0) + 1
        vi_count[b] = vi_count.get(b, 0) + 1

    pairs, seen_text = [], set()
    for a, b in links:
        if ja_count[a] != 1 or vi_count[b] != 1:
            continue
        ja_text, vi_text = jpn[a][0], vie[b][0]
        if not (good_ja(ja_text) and good_vi(vi_text)):
            continue
        if ja_text in seen_text or vi_text in seen_text:  # 同じ文の重複を避ける
            continue
        seen_text.update([ja_text, vi_text])
        pairs.append({"ja_id": a, "vi_id": b, "ja": ja_text, "vi": vi_text,
                      "ja_user": jpn[a][1], "vi_user": vie[b][1]})
    return pairs


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--per-direction", type=int, default=100)
    parser.add_argument("--seed", type=int, default=20260929)
    parser.add_argument("--cache", type=Path, default=Path(".tatoeba-cache"))
    args = parser.parse_args()

    jpn = load_sentences(download("jpn", args.cache))
    vie = load_sentences(download("vie", args.cache))
    pairs = build_pairs(jpn, vie, download("links", args.cache))
    print(f"条件を満たす対訳: {len(pairs)} 組", file=sys.stderr)

    need = args.per_direction * 2
    if len(pairs) < need:
        sys.exit(f"対訳が足りません({len(pairs)} < {need})。--per-direction を減らしてください。")

    # 並びを番号順にそろえてからくじ引きすると、seed が同じなら毎回同じ結果になる
    pairs.sort(key=lambda p: int(p["ja_id"]))
    chosen = random.Random(args.seed).sample(pairs, need)
    ja_side, vi_side = chosen[:args.per_direction], chosen[args.per_direction:]
    ja_side.sort(key=lambda p: int(p["ja_id"]))
    vi_side.sort(key=lambda p: int(p["vi_id"]))

    samples = []
    for i, p in enumerate(ja_side, 1):  # 日本語を話す → ベトナム語に訳す
        samples.append({"id": f"ja-tatoeba-{i:03d}", "language": "ja-JP",
                        "referenceTranscript": p["ja"], "referenceTranslation": p["vi"]})
    for i, p in enumerate(vi_side, 1):  # ベトナム語を話す → 日本語に訳す
        samples.append({"id": f"vi-tatoeba-{i:03d}", "language": "vi-VN",
                        "referenceTranscript": p["vi"], "referenceTranslation": p["ja"]})

    OUT_JSON.write_text(json.dumps(samples, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Tatoeba 由来の評価データの出典",
        "",
        "`tatoeba.json` の文は [Tatoeba](https://tatoeba.org) から取得しました。",
        "ライセンスは [CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/) です。",
        "`Evaluation/scripts/import_tatoeba.py` で作り直せます。",
        "",
        "| 評価データの id | 日本語文 (番号 / 投稿者) | ベトナム語文 (番号 / 投稿者) |",
        "|---|---|---|",
    ]
    for prefix, group in (("ja", ja_side), ("vi", vi_side)):
        for i, p in enumerate(group, 1):
            lines.append(
                f"| {prefix}-tatoeba-{i:03d} "
                f"| [#{p['ja_id']}](https://tatoeba.org/sentences/show/{p['ja_id']}) / {p['ja_user']} "
                f"| [#{p['vi_id']}](https://tatoeba.org/sentences/show/{p['vi_id']}) / {p['vi_user']} |")
    OUT_ATTRIBUTION.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"書き出し: {OUT_JSON.relative_to(REPO_ROOT)} ({len(samples)} 件)", file=sys.stderr)


if __name__ == "__main__":
    main()
