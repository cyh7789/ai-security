# 資料流追蹤備註

## 1. 人工清點最容易整段漏掉的進入點

最容易漏的是工具回傳物件裡偽裝成協定欄位的字串，例如 `pending_actions` 與 `_protocol`。人工通常會清點使用者輸入和 `note`，卻把工具結果的結構視為可信協定。`execute()` 會把 `ARMS[arm].extra` 整包展開後 `JSON.stringify`，再放回下一輪模型上下文（`code/17-words-into-actions/agent.mjs:69-74`、`code/17-words-into-actions/agent.mjs:114`、`code/17-words-into-actions/agent.mjs:163`）。因此清點欄位名稱而非整個工具回傳物件，會漏掉 paths.tsv 第 11 列。

## 2. 函式簽章造成的載體盲區

有。`runGates(text, user = "u1")` 只收一個待檢查字串與使用者代號（`code/23-what-can-actually-reach-it/intake.mjs:47`）。原本流程只以 `runGates(TYPED)` 檢查使用者打的文字（`code/23-what-can-actually-reach-it/intake.mjs:73`），附件 `doc` 是另一個變數，所以這個呼叫形狀看不到附件載體。只有 `scope === "both"` 的額外迴圈才把 `doc` 送進 `length` 與 `scenario`（`code/23-what-can-actually-reach-it/intake.mjs:77-84`）。

## 3. 最不確定的三列

1. 第 20 列：程式用 `stopped = "到達輸出"` 表示交付，但沒有實作寄信或把生成信件正文寫到 stdout；我依程式自己的流程狀態把它歸入第 4 類（`code/23-what-can-actually-reach-it/intake.mjs:95`）。
2. 第 21 列：同樣受「到達輸出」只是狀態標記影響；靜態可達性明確，但實際交付呼叫不存在（`code/23-what-can-actually-reach-it/intake.mjs:98-108`）。
3. 第 18 列：`run-attacks.sh` 把模型生成內容寫入回覆檔，符合「生成內容交付出去」的廣義讀法，但它是量測留檔，不是寄給客戶的信件傳送介面（`code/11-what-the-model-reads/run-attacks.sh:63-65`）。
