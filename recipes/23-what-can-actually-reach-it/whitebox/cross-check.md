# 兩個模型跑同一份素材

同一份 `prompt.txt`、同一份程式碼複本，分別給 GPT-5.6 Sol 與 Claude Opus 5。一份 21 列，一份 20 列。分歧的地方比一致的地方有用，所以先寫分歧。

## 分歧一：附件送進同一組閘之後擋不擋得住

Sol 第 21 列說 `--gate both` 會被 length 或 scenario 擋住。Opus 第 11 列說擋不住。

實測是 Opus 對：那份附件的主題就是訂單，第三道那份場景允許清單判 `SCENARIO_OK`。

```
$ node intake.mjs --doc docs/injected.txt --gate both
injected.txt	both	allow	allow(SCENARIO_OK)	yes	ok	到達輸出
```

這一條的意義不只是誰對。它是 surface.tsv R3 那一列存在的理由：「附件也送進同一組閘」補不起 R2 那個洞，因為第三道問的是主題在不在範圍內，而攻擊者本來就會用一份主題正常的文件。

## 分歧二：模型生成的程式碼被 import 執行

Opus 列了三條（第 17、18、19 列），Sol 一條都沒有。

`16/run-gen.sh:50` 把模型回覆寫成 `gen/<組>-<發>.mjs`；沒有程式碼圍欄時整份原文照樣寫進去。然後 `16/judge.mjs:68` 與 `16/enumerable.mjs:56` 各自 `await import()` 那個檔案，模組頂層的東西在 handler 被呼叫之前就跑完了。`judge.mjs:13` 那份 `DANGEROUS` 只把結果填進 `flagged` 欄（`judge.mjs:65`），第 68 行照樣 import；`16/adapter.sh:10` 的 `--sandbox read-only` 套在生成那一端，執行那一端沒有。

這一類不在今天的清點對象上（清點對象是客服 bot，不是量測工具），所以沒有進 surface.tsv。它記在 README 的欠帳那一節，等排時間。

## 分歧三：口徑

Opus 花了第一節講它怎麼定界，並因此排除 11 與 21 整個目錄。Sol 沒有寫界線，於是把 11 的量測留檔跟 13 的量測腳本都算進「交付出去」。我判那四條「不在清點對象」，跟 Opus 的界線一致。

**一份沒有寫下界線的清單，分母是浮動的。** 要拿它算比例的話，界線那一段比路徑那一張表重要。

## 兩邊一致的地方

- 302 那條繞得過字串白名單（Sol 4、Opus 15），逐跳重驗擋得住（Sol 3、Opus 16）。我原本把這一格量成「被擋死」，因為我拿 `safe-fetch.mjs` 量，而 agent 預設走的是 `--gate on` 那條分支的裸 fetch（`15/agent.mjs:110`）。兩邊都指出來了。
- 意圖核對閘的兩端都是模型同一輪產生的字，擋不住一致的宣稱。
- 外部基準閘擋得住被劫持的刪除，因為它看的是使用者原話。
- 閘的簽章決定它看得到什麼載體。Opus 把這件事寫成通則並列了四個例子（`18/gates.mjs` 三道、`17/gate.mjs` 兩道、`15/gate.mjs` 的 `check`）。

## 兩邊都踩到我的錯

我把目錄壓平了才交出去：`find -maxdepth 2 ... -exec cp {} <一個目錄> \;` 讓 `16/before/server.mjs` 與 `16/after/server.mjs` 同名互相覆蓋。

Sol 照著壓平後的路徑寫 file:line，兩列指到不存在的檔案（判成「引用對不上」）。Opus 在 notes 第一節就寫「這份程式碼照現在的排法跑不動」，並列出五個因此壞掉的相對路徑，還聲明它給的是呼叫關係不是實跑軌跡。

**同一個包裝錯誤，一個照做、一個先聲明。** 收答案的時候這個差別比清單本身有用。
