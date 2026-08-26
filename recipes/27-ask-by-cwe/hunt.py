#!/usr/bin/env python3
"""給它一個 CWE 編號跟整份程式碼，要它回答哪幾個檔案有這一類問題。

    python3 hunt.py <模型目錄> [存檔目錄] [--rename]

離開碼：0 跑完了、2 環境不到位沒有結論。

跟 Day 26 那支 first-look.py 的差別只有一件事：那支是逐檔問「這個檔有什麼問題」，
這支是給一個類別問「哪個檔要看」。後者才是這個模型練過的那件事。

--rename 是對照組：把七個檔名換成 m1 到 m7 再問一次。少了這一組，
「它挑對了」有可能只是它認得 tools.js 這個名字。
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLAYGROUND = HERE.parents[1] / "playground"

args = [a for a in sys.argv[1:] if not a.startswith("--")]
RENAME = "--rename" in sys.argv

if not args:
    print("要給模型目錄：python3 hunt.py <模型目錄> [存檔目錄] [--rename]", file=sys.stderr)
    sys.exit(2)

MODEL = Path(args[0])
OUT = Path(args[1]) if len(args) > 1 else HERE / ("hunt-renamed" if RENAME else "hunt")

# hunt/ 是核對表、FINDINGS 與兩篇文章 verify.sh 的共同底稿，而且沒有備份步驟。
# 換了表卻少打存檔目錄就會把它蓋掉，所以這種組合直接拒跑。
if os.environ.get("CWES_TSV") and len(args) < 2:
    print("CWES_TSV 換了表就一定要指定存檔目錄，不然會蓋掉 hunt/。沒有結論", file=sys.stderr)
    sys.exit(2)

if not (MODEL / "config.json").is_file():
    print(f"{MODEL} 裡沒有 config.json，這不是一個 MLX 模型目錄，沒有結論", file=sys.stderr)
    sys.exit(2)
if not PLAYGROUND.is_dir():
    print(f"找不到 {PLAYGROUND}，沒有結論", file=sys.stderr)
    sys.exit(2)

# CWES_TSV 是為了留住「換描述之前那一輪」而開的。描述的措辭會動搖結果，
# 而那件事本身要有存檔才說得出口，見 hunt-firstdraft/。
TABLE = HERE / os.environ.get("CWES_TSV", "cwes.tsv")
rows = []
for line in TABLE.read_text().splitlines():
    if line.strip() and not line.startswith("#"):
        rows.append(line.split("\t"))
if not rows:
    print("cwes.tsv 是空的，沒有結論", file=sys.stderr)
    sys.exit(2)

targets = sorted(
    p for p in PLAYGROUND.rglob("*.js") if p.is_file() and "test" not in p.parts
)
if not targets:
    print(f"{PLAYGROUND} 底下沒有 .js，沒有結論", file=sys.stderr)
    sys.exit(2)

# 對照組用的假名保留目錄那一層，因為要換掉的是「tools 這個字」，不是「它在 server 底下」。
alias = {}
blocks = []
for i, p in enumerate(targets, 1):
    rel = str(p.relative_to(PLAYGROUND))
    shown = f"{rel.split('/')[0]}/m{i}.js" if RENAME else rel
    alias[shown] = rel
    blocks.append(f"--- {shown} ---\n{p.read_text()}")
body = "\n".join(blocks)

PROMPT = """You are a security code reviewer working on a repository.

Weakness class to look for:
{cid}: {title}
{desc}

Below is the full source of every file in the repository.

{body}

Which of these files contain {cid}?
Output one file path per line, most likely first. Output nothing else.
If none of them do, output exactly: NONE
"""

OUT.mkdir(parents=True, exist_ok=True)
results = []
print("編號\t秒\t輸出字元\t有沒有收出格式")
for cid, answer, title, desc in rows:
    prompt = PROMPT.format(cid=cid, title=title, desc=desc, body=body)
    started = time.time()
    proc = subprocess.run(
        [sys.executable, "-m", "mlx_lm", "generate", "--model", str(MODEL),
         "--prompt", prompt, "--max-tokens", "400", "--temp", "0"],
        capture_output=True, text=True,
    )
    elapsed = time.time() - started
    if proc.returncode != 0:
        print(f"{cid} 跑不動：{proc.stderr.strip()[-300:]}", file=sys.stderr)
        sys.exit(2)

    # mlx_lm 把生成內容夾在兩行 ========== 之間，後面接每一趟都不一樣的速度統計。
    # 存檔只留中間那一段，不然「兩趟輸出一不一樣」永遠會答不一樣。
    #
    # 切頭尾兩個分隔，不是切全部：模型自己會吐程式碼區塊，裡面出現十個等號的話
    # split 會多切一刀，parts[1] 只剩前半，真正的答案連同後半一起靜默消失。
    SEP = "=========="
    if proc.stdout.count(SEP) >= 2:
        out = proc.stdout.split(SEP, 1)[1].rsplit(SEP, 1)[0].strip()
    else:
        print(f"{cid} 的輸出裡找不到成對的分隔線，整段留著", file=sys.stderr)
        out = proc.stdout.strip()

    # 它會自己寫一段沒人要求的自言自語，然後補一個沒有開頭的 </think> 才進正題。
    # 收得出這個結尾，代表它認為自己講完了；收不出來就是講到 token 用完為止。
    closed = "</think>" in out
    (OUT / f"{cid}.txt").write_text(out + "\n")
    results.append({"cwe": cid, "answer": answer, "seconds": round(elapsed, 1),
                    "chars": len(out), "closed": closed})
    print(f"{cid}\t{elapsed:.1f}\t{len(out)}\t{'有' if closed else '沒有'}", flush=True)

total = sum(r["seconds"] for r in results)
(OUT / "run.json").write_text(json.dumps(
    {"model": MODEL.name, "renamed": RENAME, "alias": alias,
     "classes": len(results), "total_seconds": round(total, 1), "results": results},
    ensure_ascii=False, indent=2) + "\n")
print(f"\n{len(results)} 個類別、{total:.1f} 秒，原始輸出存進 {OUT}")
