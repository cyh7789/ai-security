#!/usr/bin/env python3
"""把七個檔一次餵給模型，問它哪兩個檔串起來構成一條路。

    python3 chain-ask.py <模型目錄> [存檔目錄]

離開碼：0 跑完了、2 環境不到位沒有結論。

跟前兩輪的差別就是問法。Day 26 是逐檔問（一次一個檔），Day 27 是逐類問
（一次一個 CWE 編號），兩種問法都預設答案落在單一個位置上，所以答案是
「兩條獨立的問題」有可能是問法決定的，不是模型的能力決定的。這一支把那個
變因拿掉：檔案全部給它，明講要的是跨檔的組合。

這一支跟 first-look.py 一樣不判斷對錯、不計分，原始輸出逐字存下來。
七個檔不含 test/setup.js，跟前兩輪的收檔規則一致。
"""
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

if len(sys.argv) < 2:
    print("要給模型目錄：python3 chain-ask.py <模型目錄> [存檔目錄]", file=sys.stderr)
    sys.exit(2)

MODEL = Path(sys.argv[1])
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else Path(__file__).parent / "chain-ask")
PLAYGROUND = Path(__file__).resolve().parents[2] / "playground"

if not (MODEL / "config.json").is_file():
    print(f"{MODEL} 裡沒有 config.json，這不是一個 MLX 模型目錄，沒有結論", file=sys.stderr)
    sys.exit(2)
if not PLAYGROUND.is_dir():
    print(f"找不到 {PLAYGROUND}，沒有結論", file=sys.stderr)
    sys.exit(2)

# 問法只換一件事：要的是跨檔的組合，不是單一位置。格式一樣固定，
# 一樣不准它解釋推理過程，這樣才比得出跟前兩輪的差別在哪。
PROMPT = """You are a security code reviewer. Below are all the source files of a small \
application. Do not look for problems inside a single file. Instead, find pairs of files \
where an untrusted value enters in one file and reaches a dangerous operation in another.

For each pair output one line in this exact format:
<file A> -> <file B> | <what flows> | <why it is dangerous>

If no such pair exists, output exactly: NONE
Do not explain your reasoning. Do not suggest style improvements.

{files}
"""

targets = sorted(
    p for p in PLAYGROUND.rglob("*.js") if p.is_file() and "test" not in p.parts
)
if not targets:
    print(f"{PLAYGROUND} 底下沒有 .js，沒有結論", file=sys.stderr)
    sys.exit(2)

blob = "\n".join(
    f"File: {p.relative_to(PLAYGROUND)}\n```\n{p.read_text()}```\n" for p in targets
)
prompt = PROMPT.format(files=blob)

started = time.time()
proc = subprocess.run(
    [sys.executable, "-m", "mlx_lm", "generate", "--model", str(MODEL),
     "--prompt", prompt, "--max-tokens", "600", "--temp", "0"],
    capture_output=True, text=True,
)
elapsed = time.time() - started
if proc.returncode != 0:
    print(f"跑不動：{proc.stderr.strip()[-300:]}", file=sys.stderr)
    sys.exit(2)

parts = proc.stdout.split("==========")
body = parts[1].strip() if len(parts) > 2 else proc.stdout.strip()
peak = ""
for line in proc.stdout.splitlines():
    if line.startswith("Peak memory:"):
        peak = line.split(":", 1)[1].strip()

OUT.mkdir(parents=True, exist_ok=True)
(OUT / "answer.txt").write_text(body + "\n")

# 這一輪是新的一輪，條件跟前兩輪不同，所以自己記一份。
# 記法跟 Day 28 那五格同一個道理：模型、提示、腳本、被掃的程式碼。
sha = lambda s: hashlib.sha256(s.encode()).hexdigest()
(OUT / "run.json").write_text(json.dumps({
    "model": MODEL.name,
    "model_sha256": hashlib.sha256((MODEL / "model.safetensors").read_bytes()).hexdigest(),
    "quant": json.loads((MODEL / "config.json").read_text()).get("quantization"),
    "prompt_sha256": sha(PROMPT),
    "script_sha256": sha(Path(__file__).read_text()),
    "corpus_sha256": sha(blob),
    "files": [str(p.relative_to(PLAYGROUND)) for p in targets],
    "seconds": round(elapsed, 1),
    "peak": peak,
}, ensure_ascii=False, indent=2) + "\n")

print(body)
print(f"\n{len(targets)} 個檔一次餵、{elapsed:.1f} 秒，原始輸出存進 {OUT}")
