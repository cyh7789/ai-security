# 那張表是拿什麼跑出來的

Day 26 跟 Day 27 各留下一張成績單。那些數字底下有四個條件：哪一份權重、哪一組量化參數、哪一版提示、哪一支腳本。這一份把那四樣記成機器對得起來的值，跑實驗之前先對一次帳。

## 為什麼是這四樣

Day 26 那份 `POSITIONING.md` 結尾自己寫著：

> 什麼情況下這份聲明要重寫：換模型、換量化版本、換提示、換掃描的語言。

那四樣是人寫的散文，這一份把它變成腳本讀得懂的東西。

## 跑

```bash
python3 stamp.py record /path/to/antares-1b-mlx    # 記一次，寫成 stamp.json
python3 stamp.py check  /path/to/antares-1b-mlx    # 跑實驗前對一次
```

離開碼照 Day 22 那份公約：0 四格全對、1 有格子對不上、2 缺東西沒有結論。

`stamp.json` 進版控，跟程式碼放在一起。

## 這一天真正的證據

Day 27 換掉兩條類別描述，其中一題的答案就翻了（`hunt-firstdraft/` 是換之前那一輪）。兩輪存檔的 `run.json` 在 `model` 欄逐字相同，看不出差別在哪。

拿這支對兩輪各算一次：

```bash
python3 stamp.py check <模型目錄> --cwes ../27-ask-by-cwe/cwes-firstdraft.tsv
```

四格裡三格通過，只有 `prompt` 那格不同。那次翻盤從「我記得是描述改了」變成一個對得起來的雜湊。

## 提示跟腳本的邊界是自己畫的

提示樣板寫在 `hunt.py` 裡，類別描述在 `cwes.tsv`。整支 `hunt.py` 一起算最省事，但改一個註解會讓 `prompt` 那格跟著動，而「今天是提示變了還是程式變了」正是這張表要回答的。

所以 `prompt` 那格只取 `PROMPT = """..."""` 那段樣板，加上 `cwes.tsv` 的內容；`script` 那格才是整支 `hunt.py`。`verify.sh` 第 6 條驗這件事：加一行註解，`script` 不合、`prompt` 不動。

## 雜湊在這裡不是防篡改

`sha256` 只是「模型是哪一份」那一格的填法，換成任何一個穩定的識別方式都成立。另外三格沒有雜湊可用，一樣要記。

這一份要解決的不是有人來換你的權重，是三個月後你自己說不出當初拿什麼跑的。

## 檢查

```bash
bash verify.sh        # 八節，快照在 verify.out
bash mutations.sh     # 把每一條各弄壞一次，九條全要抓到
```

`verify.sh` 只有第 2、3、6 條需要真的模型，設 `ANTARES_MLX` 指過去。對帳邏輯跟權重內容無關，其餘幾條用一個幾位元組的假模型目錄就驗得掉。
