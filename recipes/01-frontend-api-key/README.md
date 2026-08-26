# 01 金鑰不要放前端

對應 [Day 1](https://ithelp.ithome.com.tw/articles/10400931)。

```bash
bash verify.sh        # 跑全部三個情境
bash verify.sh 2      # 只跑第 2 個
```

整支跑在 `mktemp -d` 開的暫存目錄裡，不碰你的任何檔案，跑完自動刪掉。
需要 `node` 與 `npx`。build 用 esbuild，它的 `--define` 就是 Vite 用來把
`import.meta.env.VITE_*` 換成字面值的同一個機制，所以這裡看到的產物跟 Vite 產的一樣。

## 洞在哪

`before/api.js`：

```js
const API_KEY = import.meta.env.VITE_MODEL_API_KEY;
// ...
headers: { Authorization: `Bearer ${API_KEY}` }
```

`VITE_` 或 `NEXT_PUBLIC_` 開頭的環境變數，build 完就躺在 bundle 裡，
跟寫死在原始碼沒有分別。它叫環境變數沒錯，但它的環境是使用者的瀏覽器。

`after/` 把金鑰移到一台你控制的機器：前端打同源的 `/api/chat`，
`server.js` 拿 `process.env.PROVIDER_API_KEY` 去跟供應商講話。

## verify.sh 驗什麼

### 1. build 產物裡有沒有金鑰

```
before/  dist 裡含 sk- 的檔案數：1
after/   dist 裡含 sk- 的檔案數：0
```

順帶示範一件更重要的事：拿 `ghp_` 去搜同一份**有洞的**產物，得到 0。
**`grep` 找不到只代表這個前綴沒有，不代表沒洩漏。** 其他前綴、編碼過的字串、
還沒走到的請求，都不在這個檢查的射程內。

### 2. 請求打去哪、header 帶了什麼

Day 1 的第一招是開 DevTools 看 Network。這裡用等價但可自動化的做法：
跑 build 出來的那份程式（也就是瀏覽器真的會執行的東西），攔截 `fetch`，
把它想送出去的目標與 header 印出來。

```
before  送去 https://api.example-model.com/v1/chat
        Authorization: Bearer sk-proj-8Kj2mNp4qR7sT9vXwYzA3bC5dE6fG1hI
after   送去 /api/chat
        Authorization: (沒有 Authorization)
```

**驗收不能只看「有沒有 Authorization 這個 header」。** 修好之後它仍然可能出現，
那是你自己應用的登入權杖。要看的是裡面裝著誰的憑證。

### 3. `dist/` 沒清乾淨，你看的是上一版

兩個方向，都會給你錯的答案：

| | 現場 | 你會以為 |
|---|---|---|
| 方向一 | 程式碼改好了，忘記重新 build | 「還是沒過，我到底哪裡沒改到」 |
| 方向二 | `dist` 是修好那版留下的，原始碼被改回舊寫法 | 「過了，安全」 |

方向一浪費你半小時。方向二危險得多：檢查說沒事，漏洞在原始碼裡等著下一次 build。

修法是 `rm -rf dist` 再 build 一次。**驗收的第一個動作，永遠是確認你在看的是新的東西。**

## 什麼情況不適用

`after/` 只解決「供應商金鑰不進瀏覽器」，它還不能直接上線。
`/api/chat` 目前沒有身分驗證、每人額度與速率限制，公開部署後會變成一個免費的模型端點。
那些是後面幾天的題目，今天先把信任邊界畫對。

另外這裡示範的是 `sk-` 前綴與 `VITE_` 慣例。換一家供應商、換一套框架，
字串會不一樣，但三個檢查的形狀不變。
