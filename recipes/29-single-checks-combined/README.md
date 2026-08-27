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

`jsdom` 已經列在 repo 根目錄的 `dependencies`，所以兩條指令都從根目錄下：

```bash
npm install
node recipes/29-single-checks-combined/chain-exec.mjs
```

不要在這個目錄裡打 `npm install jsdom`。這裡沒有自己的 `package.json`，npm 會往上找到根目錄那一份，把它的 `dependencies` 改掉。

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
bash verify.sh        # 九節，快照在 verify.out
bash mutations.sh     # 把每一節各弄壞一次，十一條全要抓到，快照在 mutations.out
```

第 3 節需要 node 與 jsdom，第 9 節需要 `chain-ask/` 那一輪的存檔（已經附在這裡）。其餘幾節不用裝東西，但要整份 clone 在原位：第 7 節讀 `recipes/05-innerhtml-fake-green/`，第 8 節讀根目錄 README 的索引表，少了它們會判沒過，不是跳過。

`mutations.sh` 是真的寫檔：它會改寫 `playground/` 那兩支、兩份存檔、`chain-exec.mjs`、`chain-ask/answer.txt` 與根目錄 README，靠 `trap` 在結束時還原。工作區有沒提交的修改就先收乾淨再跑，硬中斷還原不回來。

## 那直接問它組合呢

前兩輪是逐檔問（Day 26）與逐類問（Day 27），兩種問法都預設答案落在單一位置上，所以「它看不到組合」有可能是問法決定的。`chain-ask.py` 把那個變因拿掉：七個檔一次全給，明講要的是跨檔的組合。

```bash
python3 chain-ask.py /path/to/antares-1b-mlx     # 存檔在 chain-ask/
```

它回的兩對（逐字在 `chain-ask/answer.txt`）：

```text
server/files.js -> server/tools.js | uploads/filename | reads arbitrary uploaded file contents into memory and executes system commands
server/files.js -> src/format.js | any formatPrice input (cents, currency) | formatPrice performs sensitive number formatting/rounding on untrusted values
```

兩對的資料流都不存在：`server/tools.js` 與 `src/format.js` 沒有任何別的檔引用。那七個檔之間唯一一條檔對檔的引用是 `src/render.js` 第 1 行的 `import { ask } from "./api.js";`，也就是它沒指出來的那一條。`verify.sh` 第 9 節守這件事。
