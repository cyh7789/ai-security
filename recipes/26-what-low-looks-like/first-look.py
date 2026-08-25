#!/usr/bin/env python3
"""拿這個範例專案的七個檔案餵它一輪，把**原始輸出**逐字存下來。

    python3 first-look.py <模型目錄> [存檔目錄]

離開碼：0 跑完了、2 環境不到位沒有結論。

這一支不判斷對錯，也不計分。今天要給的是「它跑出來長什麼樣」，
逐條核對是明天的事（Day 27 拿 ANSWER-KEY 對）。所以這裡連跳針、
連沒收尾的句子、連那個沒有開頭的 </think> 都原樣留著：
修飾掉難看的部分，第一次自己跑的人會以為是自己弄壞了。

七個檔不含 test/setup.js。那支是測試腳手，答案卷也沒收它。
"""
import json
import subprocess
import sys
import time
from pathlib import Path

if len(sys.argv) < 2:
    print("要給模型目錄：python3 first-look.py <模型目錄> [存檔目錄]", file=sys.stderr)
    sys.exit(2)

MODEL = Path(sys.argv[1])
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else Path(__file__).parent / "first-look")
PLAYGROUND = Path(__file__).resolve().parents[2] / "playground"

if not (MODEL / "config.json").is_file():
    print(f"{MODEL} 裡沒有 config.json，這不是一個 MLX 模型目錄，沒有結論", file=sys.stderr)
    sys.exit(2)
if not PLAYGROUND.is_dir():
    print(f"找不到 {PLAYGROUND}，沒有結論", file=sys.stderr)
    sys.exit(2)

# 這段提示刻意寫得很直白，而且要求固定格式。今天要看的是它在最單純的用法下
# 長什麼樣；提示調得漂亮一點當然有差，但那會把「它本來的水準」蓋掉。
PROMPT = """You are a security code reviewer. Analyse the following file and list \
only concrete security problems you can point at a specific line.

For each problem output one line in this exact format:
CWE-<number> | line <n> | <one short sentence>

If you find no security problem, output exactly: NONE
Do not explain your reasoning. Do not suggest style improvements.

File: {name}
```
{code}
```
"""

targets = sorted(
    p for p in PLAYGROUND.rglob("*.js") if p.is_file() and "test" not in p.parts
)
if not targets:
    print(f"{PLAYGROUND} 底下沒有 .js，沒有結論", file=sys.stderr)
    sys.exit(2)

OUT.mkdir(parents=True, exist_ok=True)
rows = []
for path in targets:
    rel = path.relative_to(PLAYGROUND)
    prompt = PROMPT.format(name=path.name, code=path.read_text())
    started = time.time()
    proc = subprocess.run(
        [sys.executable, "-m", "mlx_lm", "generate", "--model", str(MODEL),
         "--prompt", prompt, "--max-tokens", "400", "--temp", "0"],
        capture_output=True, text=True,
    )
    elapsed = time.time() - started
    if proc.returncode != 0:
        print(f"{rel} 跑不動：{proc.stderr.strip()[-300:]}", file=sys.stderr)
        sys.exit(2)

    # mlx_lm 把生成內容夾在兩行 ========== 之間，後面接它自己的速度統計。
    # 統計每一趟都不一樣（同一段內容照樣），所以存檔只留中間那一段，
    # 不然「兩趟輸出一不一樣」永遠會答不一樣。
    parts = proc.stdout.split("==========")
    body = parts[1].strip() if len(parts) > 2 else proc.stdout.strip()
    peak = ""
    for line in proc.stdout.splitlines():
        if line.startswith("Peak memory:"):
            peak = line.split(":", 1)[1].strip()

    name = str(rel).replace("/", "_") + ".txt"
    (OUT / name).write_text(body + "\n")
    rows.append({"file": str(rel), "seconds": round(elapsed, 1), "peak": peak, "raw": name})
    print(f"{rel}\t{elapsed:.1f}s\t{peak}", flush=True)

total = sum(r["seconds"] for r in rows)
(OUT / "run.json").write_text(json.dumps(
    {"model": str(MODEL), "files": len(rows), "total_seconds": round(total, 1),
     "results": rows}, ensure_ascii=False, indent=2) + "\n")
print(f"\n{len(rows)} 個檔、{total:.1f} 秒，原始輸出存進 {OUT}")
