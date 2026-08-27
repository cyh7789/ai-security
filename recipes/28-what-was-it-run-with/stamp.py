#!/usr/bin/env python3
"""把一次實驗的條件記成四格，跑之前先對一次帳。

    python3 stamp.py record <模型目錄> [成分表路徑]
    python3 stamp.py check  <模型目錄> [成分表路徑]

離開碼照 Day 22 那份公約：0 四格全對、1 有格子對不上、2 缺東西沒有結論。

為什麼是這四格：Day 26 那份 POSITIONING.md 自己寫著「換模型、換量化版本、
換提示、換掃描的語言，這份聲明就過期」。那四樣是人寫的散文，這支把它們變成
機器對得起來的值。

`--cwes` 是給「換描述之前那一輪」用的。Day 27 換掉兩條類別描述，其中一題的
答案就翻了，而兩輪存檔的 run.json 在 model 欄逐字相同，看不出差別在哪。
拿這支對兩輪各算一次，會看到只有 prompt 那格不同。
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
RECIPE27 = HERE.parent / "27-ask-by-cwe"


def die(msg):
    """缺東西是沒有結論，不是不合。混在一起的話，一台沒有模型的機器會把
    整張表印成不合，而其實一格都沒比到。"""
    print(f"{msg}，沒有結論", file=sys.stderr)
    sys.exit(2)


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def prompt_template(script):
    """提示樣板跟腳本住在同一個檔，所以要自己畫邊界。

    抽出來單獨算，改一個註解 script 那格會動、prompt 那格不動。整支一起算的話
    兩格會一起動，而「今天到底是提示變了還是程式變了」正是這張表要回答的。
    """
    m = re.search(r'^PROMPT = """(.*?)"""', script.read_text(), re.S | re.M)
    if not m:
        die(f"{script.name} 裡找不到 PROMPT 那段樣板")
    return m.group(1)


def prompt_rows(cwes):
    """只取實際餵給模型的那幾欄。

    hunt.py 是 `for cid, answer, title, desc in rows` 然後
    `PROMPT.format(cid=cid, title=title, desc=desc, ...)`：第 2 欄那個人工答案
    從來沒進過提示。整份檔案一起算的話，我改一格答案、模型讀到的東西一個字
    都沒變，這一格卻報不合，而那個方向最糟：它會讓人把一份其實有效的成績單
    丟掉重跑。註解與空白行同理。
    """
    rows = []
    for line in cwes.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) < 4:
            die(f"{cwes.name} 有一列不足四欄，跟 hunt.py 的解析對不起來")
        cid, _answer, title, desc = cols[:4]
        rows.append("\t".join((cid, title, desc)))
    if not rows:
        die(f"{cwes.name} 裡沒有資料列")
    return rows


def corpus_files(root):
    """收檔的規則要跟 hunt.py 的 targets 一模一樣（`*.js`、排除 test）。

    兩邊各寫一次的話，改一邊就靜默分岔：stamp 記的是 A 組、模型讀的是 B 組，
    而對帳照樣說通過。這裡回傳清單而不是只回傳數量，因為「少收一個、
    多收另一個」總數不變，只比數量看不出來。
    """
    if not root.is_dir():
        die(f"找不到被掃的目錄 {root}")
    return sorted(
        p for p in root.rglob("*.js") if p.is_file() and "test" not in p.parts
    )


def corpus_digest(root):
    """被掃的那份程式碼也是輸入，而且是最大的一塊。

    檔名一起算進去：Day 27 那組改名對照餵給模型的內容就是檔名加內容，
    兩者都動得了答案。
    """
    files = corpus_files(root)
    if not files:
        die(f"{root} 底下沒有 .js")
    rels = [str(f.relative_to(root)) for f in files]
    h = hashlib.sha256()
    for f, rel in zip(files, rels):
        h.update(rel.encode())
        h.update(b"\0")
        h.update(f.read_bytes())
        h.update(b"\0")
    return rels, h.hexdigest()


def compose(model_dir, cwes, corpus):
    weights = model_dir / "model.safetensors"
    config = model_dir / "config.json"
    script = RECIPE27 / "hunt.py"
    for p in (weights, config, script, cwes):
        if not p.is_file():
            die(f"找不到 {p}")

    corpus_rels, corpus_sha = corpus_digest(corpus)

    quant = json.loads(config.read_text()).get("quantization")
    if quant is None:
        die(f"{config} 裡沒有 quantization 那格")

    # 提示由兩截組成：樣板的骨架，加上餵進去的那幾條類別描述。
    # 兩截各自都改得動答案，所以一起算成一格。
    rows = prompt_rows(cwes)
    blob = prompt_template(script) + "\n" + "\n".join(rows)

    return {
        "model": {
            "檔": str(weights.relative_to(model_dir.parent)),
            "sha256": sha256_file(weights),
        },
        "quant": {
            "來源": "config.json 的 quantization",
            # sort_keys 是為了讓兩台機器算出同一個字串。JSON 的鍵沒有順序，
            # 不排的話同一份設定在不同 Python 版本可能印出不同的字。
            "值": json.dumps(quant, sort_keys=True, separators=(",", ":")),
        },
        "prompt": {
            "來源": f"{script.name} 的 PROMPT 樣板加上 {cwes.name} 的 {len(rows)} 列"
                    "（只取實際餵給模型的編號、標題、描述三欄）",
            "sha256": hashlib.sha256(blob.encode()).hexdigest(),
        },
        "script": {
            "檔": script.name,
            "sha256": sha256_file(script),
        },
        "corpus": {
            "來源": f"{corpus.name}/ 底下 {len(corpus_rels)} 個 .js，檔名與內容一起算",
            "檔": corpus_rels,
            "sha256": corpus_sha,
        },
    }


ap = argparse.ArgumentParser(add_help=False)
ap.add_argument("action", choices=["record", "check"])
ap.add_argument("model_dir")
ap.add_argument("stamp", nargs="?", default=str(HERE / "stamp.json"))
ap.add_argument("--cwes", default=str(RECIPE27 / "cwes.tsv"))
ap.add_argument("--corpus", default=str(RECIPE27.parents[1] / "playground"))
args = ap.parse_args()

CELLS = ("model", "quant", "prompt", "script", "corpus")

model_dir = Path(args.model_dir)
if not (model_dir / "config.json").is_file():
    die(f"{model_dir} 裡沒有 config.json，這不是一個 MLX 模型目錄")

now = compose(model_dir, Path(args.cwes), Path(args.corpus))
stamp = Path(args.stamp)

if args.action == "record":
    stamp.write_text(json.dumps(now, ensure_ascii=False, indent=2) + "\n")
    print(f"{len(CELLS)} 格記進 {stamp.name}：")
    for k in CELLS:
        v = now[k]
        print(f"  {k}\t{v.get('sha256') or v['值']}")
    sys.exit(0)

if not stamp.is_file():
    die(f"還沒有 {stamp.name}，先跑一次 record")
was = json.loads(stamp.read_text())

bad = []
for key in CELLS:
    if key not in was:
        die(f"{stamp.name} 裡沒有 {key} 那格，這份成分表跟現在這支對不起來")
    a = was[key].get("sha256") or was[key].get("值")
    b = now[key].get("sha256") or now[key].get("值")
    if a == b:
        print(f"  通過\t{key}\t{b}")
    else:
        # 「表上」是 stamp.json 記著的，「實測」是現在算出來的。
        # 寫「當初／現在」在回頭對舊資料時字面剛好跟事實相反。
        print(f"  沒過\t{key}\t表上 {a}／實測 {b}")
        bad.append(key)

if bad:
    print(f"\n{len(bad)} 格對不上：{'、'.join(bad)}。"
          f"上一輪那些數字是別的條件跑出來的，重跑之前不要拿來比。")
    sys.exit(1)
print(f"\n{len(CELLS)} 格都對得上，這一輪跟成分表記的是同一組條件。")
sys.exit(0)
