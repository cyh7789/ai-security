#!/usr/bin/env python3
"""最小輸入跑一次，量載入時間、生成時間、峰值記憶體。

    python3 smoke.py <模型目錄> [次數]

離開碼照 Day 22 那份公約：0 跑完了、2 環境不到位沒有結論。

為什麼要跑不只一次：第一次的載入時間裡有一大截是作業系統從磁碟把權重讀進來，
第二次起那份還在檔案快取裡。只報一次的數字，讀者會拿它對不上自己的機器，
然後以為自己裝壞了。
"""
import sys
import time
from pathlib import Path

if len(sys.argv) < 2:
    print("要給模型目錄：python3 smoke.py <模型目錄> [次數]", file=sys.stderr)
    sys.exit(2)

MODEL = Path(sys.argv[1])
ROUNDS = int(sys.argv[2]) if len(sys.argv) > 2 else 3

if not (MODEL / "config.json").is_file():
    print(f"{MODEL} 裡沒有 config.json，這不是一個 MLX 模型目錄，沒有結論", file=sys.stderr)
    sys.exit(2)

try:
    import mlx.core as mx
    from mlx_lm import load, generate
except ImportError as e:
    print(f"匯入不到 mlx-lm（{e}）。pip install mlx-lm，而且要 Apple Silicon", file=sys.stderr)
    sys.exit(2)

# 權重檔的總大小要跟後面那個峰值並排看：載入之後常駐的就是這一份，
# 峰值減掉它才是推論當下真正多吃的記憶體。
weights = sum(p.stat().st_size for p in MODEL.glob("*.safetensors"))

print("回合\t載入秒\t生成秒\t載入後峰值GB\t全程峰值GB")
for i in range(1, ROUNDS + 1):
    mx.reset_peak_memory()
    t0 = time.time()
    model, tok = load(str(MODEL))
    mx.eval(mx.zeros(1))          # 逼它把權重真的搬進記憶體，不然峰值量到的是零
    t_load = time.time() - t0
    peak_load = mx.get_peak_memory() / 1e9

    t1 = time.time()
    prompt = tok.apply_chat_template(
        [{"role": "user", "content": "hello"}], add_generation_prompt=True, tokenize=False
    )
    generate(model, tok, prompt=prompt, max_tokens=20, verbose=False)
    t_gen = time.time() - t1

    print(f"{i}\t{t_load:.2f}\t{t_gen:.2f}\t{peak_load:.3f}\t{mx.get_peak_memory()/1e9:.3f}")
    del model, tok

print(f"\n權重檔合計 {weights/1e9:.2f} GB（{weights} bytes）")
