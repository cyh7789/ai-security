# 13：那些段落是誰放進去的

對應 Day 13（發表後補連結）。

Day 12 看的是工具描述那一欄，字是別人在你安裝之前就寫好的。這一份看的是知識庫：字是你自己放進去的，問題在於「你自己」這三個字比你以為的寬。

兩支腳本，沒有任何相依套件，有 Node 就能跑。

## 一、按來源分組數一次

```bash
node kb-sources.cjs demo/kb.jsonl --prefix :
```

吃一行一個 JSON 物件（JSONL），要有 `text` 跟 `source`，`metadata.source` 也認。多數向量庫都匯得出這個形狀。

`--prefix :` 是給「來源長得像 `kind:檔名`」那種用的。一份檔案一個來源的話，不切前綴會列出幾百列各自為 1，看不出它們其實是同一個入口。

結束碼三種，跟 recipe 08 同一條規矩：**「沒有問題」跟「我沒看到」不能混在一起。**

| 碼 | 意思 |
|---|---|
| 0 | 每一段都有來源欄 |
| 2 | 有段落沒有來源欄，或有行讀不出來 |

為什麼沒有來源要非 0：一段答不出「你哪來的」的內容，跟一段來源乾淨的內容，在檢索的時候待遇完全一樣。它不是雜訊，它是你清單上填不了的那一列。

`demo/kb-nosource.jsonl` 是故意壞的，拿來看非 0 長什麼樣。

### 怎麼把庫匯成這個形狀

Chroma 的話，`get()` 預設就回 `ids`、`documents`、`metadatas` 三樣（[官方參考](https://docs.trychroma.com/reference/python/collection)，2026-08 查證），來源通常在 metadata 裡：

```bash
python3 - <<'PY' > kb.jsonl
import chromadb, json
c = chromadb.PersistentClient("./chroma").get_collection("你的集合名")
r = c.get()
ids = r["ids"]
docs = r["documents"] or [None] * len(ids)
metas = r["metadatas"] or [None] * len(ids)
assert len(ids) == len(docs) == len(metas) == c.count(), (len(ids), len(docs), len(metas), c.count())
rows = ({"id": i, "text": d, "source": (m or {}).get("source")} for i, d, m in zip(ids, docs, metas))
print("\n".join(json.dumps(x, ensure_ascii=False) for x in rows))
PY
```

`documents` 跟 `metadatas` 可能整個是 `None`，所以先補齊長度再比筆數，對不上就停：**匯出少幾段，後面每個數字都錯，而它照樣印得出一張漂亮的表。** 庫很大就用 `limit` 與 `offset` 分批。存在 SQLite 或 Postgres 的就一句查詢撈三欄。**這一步撈不出 `source` 那一欄，第一步就已經有答案了**，那正是這支腳本會單獨數出來、而且用結束碼 2 告訴你的東西。跟 Day 8 那條規矩一樣：「沒有問題」跟「我沒看到」不能混在一起。

`--prefix :` 只在來源長得像 `類型:項目` 時才加。來源是網址或 Windows 路徑的話會被切成 `https` 或 `C`，那就不要加。

## 二、丟一份自己造的進去，看它排第幾

```bash
node rank-probe.cjs demo/corpus --ask "出差報帳要準備什麼單據" --poison demo/poison.txt --top 3
```

```text
問題：出差報帳要準備什麼單據
語料 9 份（含 1 份你自己造的），字面相似度，不是語意。
════ 送給模型的是前 3 名 ════
 1. 0.093848  poison.txt  ★你造的那份
 2. 0.058917  01-expense.md
 3. 0.035586  06-meeting.md

你造的那份排第 1 名，在前 3 裡面，會被送進 prompt。
```

`--top` 是「送進 prompt 的名額」，改它會讓同一份東西從進得去變成進不去。這就是這支要示範的那件事：**投毒文件不用贏過全部，它只要贏過第 N 名。**

### 這支不是語意檢索，它自己會講

預設用的是字元二元組的 TF-IDF 餘弦，同義詞看不出來，所以它會低估。手上有本機 embedding 端點（Ollama 那種 OpenAI 相容的）就接上去走真的語意：

```bash
node rank-probe.cjs demo/corpus --ask "..." --poison demo/poison.txt \
  --embed http://localhost:11434/v1/embeddings --embed-model nomic-embed-text
```

要示範的「排序」這件事在字面和語意兩邊一樣成立：分數是文字算出來的，而文字是寫的人決定的。

### 走訪跟著 symlink 走

Day 12 那個洞在這裡補掉了：`Dirent.isDirectory()` 對「指向目錄的 symlink」回 `false`，整棵子樹會被跳過而結束碼還是 0。這支用 `statSync`，繞圈也擋。`verify.sh` 第 11、12 條盯著這兩件事。

## 驗證

```bash
bash verify.sh          # 15 條，每條都驗行為
bash verify.sh 7        # 只跑第 7 條
bash mutations.sh       # 把功能弄壞 16 次，證明上面那 15 條真的會紅
```

`mutations.out` 有跑過的結果，最後一列是反向對照：改一句不影響行為的說明文字，verify 應該還是全綠。沒有那一列的話，「什麼都會讓它紅」跟「它咬得準」分不開。

寫這份的時候有六條閘門被抓出來是假的，兩條靠突變、四條靠外部審查：

| 原本怎麼寫 | 為什麼是假的 |
|---|---|
| 第 1 條只比 handbook 那一組的數字 | 「只讀前五行」剛好被排在前面的那組蓋過去 |
| 第 13 條用一句字面本來就會贏的問題 | 不管走不走 `--embed` 都綠 |
| 第 4 條把壞行數寫死成 1 | 只記第一個解析錯誤的實作照樣綠 |
| 第 6 條只比同一個檔的兩種餵法 | stdin 壞掉之後固定去讀示範檔，照樣綠 |
| 第 8 條只要求名次大於 1 | 名次固定報第 2 名照樣綠 |
| 第 15 條只 grep 一句警語 | 那是文案檢查不是行為檢查 |

**六條在正常路徑上全都是綠的。** 現在第 15 條改成驗「走訪跳過任何路徑就要非 0 結束」，那句警語併進第 13 條，用分支差異驗（走 `--embed` 的時候它反而不該出現）。
