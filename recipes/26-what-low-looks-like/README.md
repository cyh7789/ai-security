# 26：「低」長什麼樣

對應 Day 26（發表後補連結）。

前面二十五天每一次讓模型看程式碼，都得把那段程式碼送出去。這一份把模型收回本機，
然後做一件比建置更重要的事：**在信任它之前，先量出它做不到什麼。**

跟前面的 recipe 不一樣，這一份需要 Python 與 [mlx-lm](https://github.com/ml-explore/mlx-lm)，
而 MLX 只跑在 Apple Silicon 上。其他平台的路徑列在最後一節。

## 先把模型弄到手

官方權重在 [`fdtn-ai/antares-1b`](https://huggingface.co/fdtn-ai/antares-1b)，Apache 2.0，
但要先在那個頁面上填一份表（姓名、Email、國家、任職單位、職稱）並勾同意條款。
表單自己寫著你填的資料要屬實。

```bash
pip install mlx-lm
hf download fdtn-ai/antares-1b
python3 -m mlx_lm convert --hf-path fdtn-ai/antares-1b --mlx-path ./antares-1b-mlx -q --q-bits 4
```

轉完的目錄約 1.03 GB，`config.json` 的 `quantization` 欄會是
`{"group_size": 64, "bits": 4, "mode": "affine"}`。

> 驗證紀錄（2026-08-25）：這一版 mlx-lm 是 0.31.3。上面那行 `convert` 我今天拿
> 另一個公開模型（`HuggingFaceTB/SmolLM2-135M`）實際跑過一次，出來的 `quantization`
> 欄跟我手上這份 antares 逐字相同。抓官方權重那一步要先過同意條款，我在 2026-07-22
> 做過一次，今天沒有重做。

## 跑

```bash
export ANTARES_MLX=./antares-1b-mlx     # 或你自己放的地方

python3 smoke.py "$ANTARES_MLX" 3       # 最小輸入跑三次，量載入時間與峰值記憶體
python3 first-look.py "$ANTARES_MLX"    # 掃 playground 七個檔，原始輸出存進 first-look/
bash verify.sh                          # 九條檢查
bash mutations.sh                       # 把那九條各弄壞一次，看它們會不會紅
```

離開碼照 Day 22 那份公約：0 全綠、1 有紅、2 環境不到位沒有結論。

## 這裡面有什麼

| 檔 | 是什麼 |
|---|---|
| `smoke.py` | 最小輸入，量載入時間、生成時間、峰值記憶體 |
| `first-look.py` | 七個檔各跑一次，**原始輸出逐字存下來**，不判斷對錯 |
| `first-look/` | 我 2026-08-25 那一輪的存檔，七份原始輸出加一份 `run.json` |
| `verdict.tsv` | 我親手核的一輪：六個已知問題各被指到沒有，每一列附一句逐字出自存檔的依據 |
| `POSITIONING.md` | 能力定位聲明。人手寫的，不讓模型改 |
| `verify.sh` | 九條檢查，護的是「聲明不准跟存檔分岔」 |
| `mutations.sh` | 十個突變，最後一列是不改任何東西的反向對照 |

## 為什麼原始輸出要原樣存

`first-look/` 裡面有跳針、有沒收尾的句子、有一個沒有開頭的 `</think>`，
還有一條在乾淨檔案上報出來、而句子自己說「no obvious unsafe code」的候選。
這些都留著。

修飾掉難看的部分，第一次自己跑的人會以為是自己弄壞了，然後把整條路丟掉。

## 我這一輪量到什麼

模型 `fdtn-ai/antares-1b` 的 MLX 4-bit 版，M 系列 Mac，2026-08-25：

- 載入 0.4 到 0.5 秒（第一次 2.2 秒，差的是作業系統的檔案快取），峰值記憶體 1.03 GB
- 七個檔案掃完 33.1 秒，單檔 4.3 到 6.3 秒，掃描當下峰值 1.49 GB
- 六個已知問題指出三個；三條命中裡 CWE 編號對一條、行號零條
- 兩個乾淨檔案誤報一個
- 兩趟跑出來的內容逐字相同（`--temp 0`）

數字會隨機器與版本變。**要看的不是這幾個數，是它們支撐的那句話：
候選產生器，不是掃描器。**

## 沒有 Apple Silicon 的話

以下引官方模型頁列的路徑，**我沒有實際跑過**：

- `transformers` 直接載入（跨平台，CPU 也跑得動，但沒有量化，記憶體要求高得多）
- vLLM / SGLang 部署（要 GPU）
- 社群轉的 GGUF 走 Ollama / LM Studio / llama.cpp

最後一條要留意：那些 GGUF 倉庫不是 Cisco 發的，是別人轉的。
怎麼確認你手上那份是你以為的東西，是 Day 28 整天的題目。
