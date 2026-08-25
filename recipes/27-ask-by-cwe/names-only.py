#!/usr/bin/env python3
"""只給檔名清單、不給內容，問同一個 CWE 編號。

    python3 names-only.py <模型目錄> [存檔目錄]

離開碼：0 跑完了、2 環境不到位沒有結論。

這一輪存在的理由，是把 `hunt.py` 那一輪的成績跟一個更省事的做法比。
省事的版本很誘人：檔名清單比整份原始碼短得多，幾百個檔的專案也塞得下。
所以要證明它不管用，而不是嘴上說不管用。

兩發：真名一次、檔名換成 m1 到 m7 一次。真名那發答對而改名那發答錯，
就代表它靠的是名字裡的字，不是任何它讀到的東西 —— 因為兩發它都沒有讀到東西。
"""
import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLAYGROUND = HERE.parents[1] / "playground"

if len(sys.argv) < 2:
    print("要給模型目錄：python3 names-only.py <模型目錄> [存檔目錄]", file=sys.stderr)
    sys.exit(2)

MODEL = Path(sys.argv[1])
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / "names-only"

if not (MODEL / "config.json").is_file():
    print(f"{MODEL} 裡沒有 config.json，這不是一個 MLX 模型目錄，沒有結論", file=sys.stderr)
    sys.exit(2)
if not PLAYGROUND.is_dir():
    print(f"找不到 {PLAYGROUND}，沒有結論", file=sys.stderr)
    sys.exit(2)

row = None
for line in (HERE / "cwes.tsv").read_text().splitlines():
    if line.startswith("CWE-78\t"):
        row = line.split("\t")
if row is None:
    print("cwes.tsv 裡沒有 CWE-78，沒有結論", file=sys.stderr)
    sys.exit(2)
_, ANSWER, TITLE, DESC = row

targets = sorted(
    p for p in PLAYGROUND.rglob("*.js") if p.is_file() and "test" not in p.parts
)

PROMPT = """You are a security code reviewer working on a repository.

Weakness class to look for:
CWE-78: {title}
{desc}

Files in the repository:
{files}

Which of these files should be opened and inspected for CWE-78?
Output one file path per line, most likely first. Output nothing else.
If none of them are worth opening, output exactly: NONE
"""

OUT.mkdir(parents=True, exist_ok=True)
results = []
for label, rename in (("real", False), ("renamed", True)):
    alias = {}
    names = []
    for i, p in enumerate(targets, 1):
        rel = str(p.relative_to(PLAYGROUND))
        shown = f"{rel.split('/')[0]}/m{i}.js" if rename else rel
        alias[shown] = rel
        names.append(shown)
    prompt = PROMPT.format(title=TITLE, desc=DESC, files="\n".join(names))
    started = time.time()
    proc = subprocess.run(
        [sys.executable, "-m", "mlx_lm", "generate", "--model", str(MODEL),
         "--prompt", prompt, "--max-tokens", "400", "--temp", "0"],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        print(f"{label} 跑不動：{proc.stderr.strip()[-300:]}", file=sys.stderr)
        sys.exit(2)
    SEP = "=========="
    if proc.stdout.count(SEP) >= 2:
        out = proc.stdout.split(SEP, 1)[1].rsplit(SEP, 1)[0].strip()
    else:
        out = proc.stdout.strip()
    (OUT / f"{label}.txt").write_text(out + "\n")
    results.append({"round": label, "renamed": rename, "alias": alias,
                    "seconds": round(time.time() - started, 1)})
    print(f"{label}\t{time.time() - started:.1f}s")

(OUT / "run.json").write_text(json.dumps(
    {"model": str(MODEL), "cwe": "CWE-78", "answer": ANSWER, "results": results},
    ensure_ascii=False, indent=2) + "\n")
print(f"\n兩發存進 {OUT}")
