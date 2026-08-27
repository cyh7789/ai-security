# 單點都合理，組合起來卻失守

`src/api.js` 呼叫模型 API 拿回答，正常。`src/render.js` 把回答顯示出來，正常。兩個檔各自看都會通過 code review。

串起來就在使用者的瀏覽器上執行任意 JS。

## 模型把兩半都看到了

Day 26 逐檔問 `render.js` 的時候，它吐了兩條（存檔在 `recipes/26-what-low-looks-like/first-look/src_render.js.txt`）：

```text
CWE-79 | line 4 | Sets innerHTML to user-supplied content without sanitization.
CWE-90 | line 9 | Calls an external API (ask) without validating or sanitizing its output.
```

第一條是 sink，第二條是來源。**它列成兩條獨立的問題。**

Day 27 換成逐類問 CWE-79，它指對了檔案，理由寫的是：

```text
directly sets innerHTML from user input
```

那條路上沒有 user input。危險的東西是 `ask()` 回來的，也就是模型自己的輸出。

兩個行號也都不對：它說 line 4 與 line 9，實際的 sink 在第 11 行、呼叫在第 10 行。`verify.sh` 第 6 條把這件事數出來。

## 跑

```bash
npm install          # repo 根目錄，jsdom 已經列在 dependencies
node chain-exec.mjs
```

```text
有洞版 render.js 現況	造出 <img onerror>，派發 error 後 JS 真的執行了（XSS 成立）
修好版（逃逸）	沒造出可執行節點（只當文字顯示，擋下）
```

離開碼 0 是兩邊都如預期，1 是有一邊不對。

## 為什麼要 jsdom，不用字串比對

字串裡出現 `<img onerror=...>` 只證明那串字被印出來了，證不出瀏覽器會把它當成節點，也證不出那段 JS 會跑。這兩件事分不開的判準，正是 Day 27 那支確認腳本第一版踩過的坑：`dig` 解不出網域的時候會把整串參數原樣印回錯誤訊息，於是修好的版本也被判成打進去了。

所以這裡用真的 HTML 引擎解析，再派發 `error` 事件，看 `window.__xss` 有沒有被寫進去。`mutations.sh` 的 M3 就是把判準換回字串比對，看第 3 條抓不抓得到。

## 修法

Day 5 那篇教過：`innerHTML` 會把字串當成標記解析，`textContent` 不會。這一天不引入新修法，`chain-exec.mjs` 的修好版用逃逸示範同一條分界（字串版沒辦法直接用 `textContent`）。

靶場那條 sink 沒有真的修掉，因為 `playground/` 是這個系列的答案卷，前面幾天還要拿它來掃。

## 攻擊集為什麼要單獨記一條

`attacks.jsonl` 的 05-01 就是同一個 payload。差別在 `carrier`：那條標 `dom`，假設攻擊者在輸入框打字；這條標 `model`，假設模型自己吐出來。

**輸入框那邊的每一道檢查，對這串字一道都沒作用，因為它不是從那裡進來的。**

## 檢查

```bash
bash verify.sh        # 八節，快照在 verify.out
bash mutations.sh     # 把每一節各弄壞一次，九條全要抓到
```

第 3 節需要 node 與 jsdom，其餘幾節讀存檔與靶場就驗得掉。
