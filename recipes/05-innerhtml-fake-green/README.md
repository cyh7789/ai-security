# 05 innerHTML 的假綠燈

對應 [Day 5](https://ithelp.ithome.com.tw/users/20138924/ironman/9086)。

```bash
bash verify.sh        # 跑四格加一個結論
bash verify.sh 2      # 只跑第 2 格
```

需要 `bash`、`python3`（起一個本機靜態伺服器）、一個 Chrome 或 Chromium。
沒有瀏覽器的話它會印一段可以貼進 DevTools Console 的等效檢查，同一件事在你現在
開著的瀏覽器裡也驗得掉。全部在 `mktemp -d` 裡進行，不碰你的檔案。

## 這裡要修的是驗證方法，不是那一行程式碼

有洞的那一行沒什麼好講的：

```js
output.innerHTML = `<div class="answer">${answer}</div>`;
```

修法也沒什麼好講的，`textContent` 換掉 `innerHTML` 就結束了。

真正會出事的是下一步。多數人驗收的方式是打一段 `<script>alert(1)</script>` 進去，
看它跳不跳。**這條輸入在有洞的版本上也不會跳。**

`innerHTML` 插入的 `<script>` 標籤會進 DOM，但不會執行。這是規範定的行為，
MDN 在 `Element.innerHTML` 的安全考量段寫得很清楚：

> While the property does prevent `<script>` elements from executing when they are
> injected, it is susceptible to many other ways that attackers can craft HTML to run
> malicious JavaScript.

所以那個綠燈跟修法一點關係都沒有。它在修之前就是綠的。

## 打哪裡：送進 `answer`，不是打聊天輸入框

這一格要先講，它是最容易把整個測試變成假綠燈的地方。

這個洞的污染源是 `answer`，也就是模型的回答。你在聊天輸入框打
`<img src=x onerror=alert(1)>`，那串字要先繞過模型才碰得到 `innerHTML`，
而模型會不會原樣覆述**不歸你管**：它可能拒答、可能改寫、可能把角括號換成實體。

所以「打輸入框沒跳」有兩種解釋：洞修好了，或者那串字根本沒走到 sink。
分不出這兩種狀態的檢查不是檢查，而那正是這份 recipe 要講的事。

有一種你可能以為安全的情況其實不安全：模型把那串字包進 markdown 的程式碼圍籬或行內反引號。
反引號是 markdown 的語法不是 HTML 的，`innerHTML` 拿到的就只是幾個普通字元，標籤照樣被解析。
實測五種回法（Chrome 151，跑的是 `before/render.js`）：

| 模型怎麼回 | `fired` | `imgInDOM` |
|---|---|---|
| 原樣覆述 | `true` | `true` |
| 包在三反引號的 html 圍籬裡 | `true` | `true` |
| 包在行內反引號裡 | `true` | `true` |
| 角括號換成實體 | `false` | `false` |
| 拒答，正常講話 | `false` | `false` |

**五種裡只有它自己做了 escape 那種真的擋住。** 如果你以為圍籬會擋，
「這次沒跳，大概是模型幫我包起來了」就會變成一個聽起來合理的解釋，而那是新的假綠燈。

`verify.sh` 的做法是把 `ask()` 換成回聲，讓 payload 確定抵達 `answer`：

```js
export async function ask(q) {
  return q;
}
```

這不是作弊，它模擬的正是這個洞真正的觸發條件：**模型的回答裡帶著標記。**
模型讀進去的網頁、工具回傳的內容、別人塞給它的一段文字，都可能帶著角括號進來，
然後被你的程式碼當成「自己系統的輸出」放行。

## 四格，看的是行的差異不是欄的差異

`verify.sh` 把兩個版本乘上兩條輸入跑成一個 2x2。用的是 `before/` 與 `after/`
裡真正那兩份 `render.js`：起一個本機靜態伺服器、以 ES module 載入、真的觸發 submit，
不是把那一行抄進腳本比對字串。

| | `<script>alert(1)</script>` | `<img src=x onerror=alert(1)>` |
|---|---|---|
| `before/` | 不跳（標籤進了 DOM） | **跳** |
| `after/` | 不跳 | 不跳 |

要看的不是 `after/` 那一列全綠，是 **script 那一欄上下一樣**。一條在有洞與修好上
表現相同的檢查分不出這兩種狀態，那它就不是一個驗證。

第 5 節就在斷言這件事：script 那條在兩版必須相同，img 那條在兩版必須不同。
拿掉任何一邊，這支腳本就退化成「跑一次看綠不綠」。

## 攻擊集為什麼收兩條

`attack-set.md` 裡有兩條，第二條永遠不跳。

留著它的理由是，哪天第一條也不跳了，你要先分得出來那是真的擋住，還是又拿到一個
跟第二條一樣的假綠燈。**一條永遠綠的檢查證明不了任何事，但它可以證明別的檢查有沒有意義。**

## 修法的代價，以及一條回頭路

`textContent` 之後，模型回的 markdown 與程式碼區塊會變成純文字顯示。

換行要講細一點：`textContent` 保得住字串裡的換行字元，但 HTML 預設會把空白摺起來，
所以畫面上還是連在一起。那一格補一句 `white-space: pre-wrap` 就回來了，不用碰 `innerHTML`。

**不要把 markdown renderer 的產出直接丟進 `innerHTML`。**
`output.innerHTML = marked(answer)` 看起來像在用函式庫，不像在自己組 HTML，
所以它躲得過「不要自己拼 HTML」這種提醒。但 markdown 的規格本來就允許內嵌 HTML，
那一行等於把洞原樣裝回去。真要渲染，renderer 後面得接一個成熟的 sanitizer，
而且屬性、URL scheme、SVG、`style`、`srcdoc` 都要處理，只列一張標籤白名單不夠。

先換 `textContent` 的理由是「顯示得不夠漂亮」跟「別人的字串在你的頁面上執行」
不在同一個量級。

## 什麼情況不適用

**這支只涵蓋 `innerHTML` 這一個接收點。** 同一類的還有 `outerHTML`、
`insertAdjacentHTML`、`document.write`，以及把字串塞進 `href`、`src`、行內事件屬性的那些。
修法的形狀一樣（資料就當資料），但接收點要自己數過一遍。

**用框架的話接收點不叫這個名字。** React 的 `{answer}` 與 Vue 的 `{{ answer }}`
預設就會 escape，等於這裡的 `textContent`；真正對應 `innerHTML` 的是
`dangerouslySetInnerHTML` 與 `v-html`。搜不到 `innerHTML` 不代表沒事，
代表你要搜的是另一個名字。

**有 CSP 的頁面上，這兩條 payload 的判準會壞掉。** 如果 CSP 沒放行 inline 事件處理器，
`<img>` 照樣進得了 DOM，`onerror` 卻被瀏覽器擋掉，於是有洞的版本跟修好的版本都不跳。
那時候 Console 會留一行 CSP 違規訊息，那是判準壞掉的證據，不是修好了的證據。
要分清楚：CSP 擋掉的是**這一條 payload**，不是那個洞，換一條不靠 inline handler 的就過去了。
這支腳本跑在自己起的乾淨頁面上，沒有 CSP，所以四格是可信的；
搬到你有 CSP 的專案上要先確認這件事。

**兩條輸入不是一組完整的 XSS 攻擊集。** 它們是這條閉環的起點，用途是證明你的驗證
分得出兩種狀態。真正要涵蓋屬性上下文、URL 上下文與各種編碼繞法，得往上長。

**這裡的污染源是模型的回答，不是輸入框。** 所以只在輸入端做過濾擋不掉它：
`answer` 走的是另一條路進來，而模型的回答又可能來自它讀到的網頁或工具回傳的內容。
要擋在輸出端，也就是把字串交給瀏覽器的那一行。
