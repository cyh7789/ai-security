# AI Security Cookbook

《你該防的不是駭客，是你自己的 AI：在本機驗證你的防線》的隨文 cookbook。
連載在 iThome 鐵人賽 2026 AI Security 組，每天一篇。

每一份 recipe 是一個獨立的問題與解法，**可以單獨拿走，不用讀前面**。

## 跟其他 cookbook 差在哪

多數 cookbook 給你解法就結束。這裡每一份多兩樣東西：

- **`before/`**：有洞的版本。你可以先打穿它，確認那個洞是真的
- **`verify.sh`**：修完之後跑，確認真的修好了。修之前跑是紅的，修之後是綠的

因為「改完覺得應該沒事了」跟「驗過確實沒事」是兩件事，
而這三十天講的就是這個差別。

## 現在有什麼

連載 8/01 開始，recipe 隨著文章一天一天補進來。

`playground/` 是範例專案的種子，內建了連載會用到的洞。
它現在還不能一行指令跑起來，那是第一件要補的事。

| # | Recipe | 對應 | 狀態 |
|---|---|---|---|
| 01 | [金鑰不要放前端](recipes/01-frontend-api-key/) | [Day 1](https://ithelp.ithome.com.tw/articles/10400931) | **可以跑了** |
| 02 | [祕密掃描的六個假通過](recipes/02-secret-scan-blind-spots/) | [Day 2](https://ithelp.ithome.com.tw/articles/10401002) | **可以跑了** |
| 03 | [處置外洩憑證時的三個假通過](recipes/03-revoke-verification/) | [Day 3](https://ithelp.ithome.com.tw/articles/10401276) | **可以跑了** |
| 04 | [貼給 AI 之前的紅線檢查](recipes/04-what-not-to-paste/) | [Day 4](https://ithelp.ithome.com.tw/articles/10401371) | **可以跑了** |
| 05 | [innerHTML 的假綠燈](recipes/05-innerhtml-fake-green/) | [Day 5](https://ithelp.ithome.com.tw/articles/10401465) | **可以跑了** |
| 06 | [它在哪裡跑](recipes/06-run-it-somewhere-else/) | [Day 6](https://ithelp.ithome.com.tw/articles/10401762) | **可以跑了** |
| 07 | [它到底存不存在](recipes/07-does-it-even-exist/) | [Day 7](https://ithelp.ithome.com.tw/articles/10401878) | **可以跑了** |
| 08 | [我裝的那幾台，各自碰得到什麼](recipes/08-what-can-it-touch/) | [Day 8](https://ithelp.ithome.com.tw/articles/10402102) | **可以跑了** |
| 09 | [前端擋得住的，後端擋不擋得住](recipes/09-which-side-validated/) | [Day 9](https://ithelp.ithome.com.tw/articles/10402200) | **可以跑了** |
| 10 | [指令跟資料，接起來之後還分得開嗎](recipes/10-instructions-vs-data/) | [Day 10](https://ithelp.ithome.com.tw/articles/10402365) | **可以跑了** |
| 11 | [你看到的那一頁，跟模型讀到的那一頁](recipes/11-what-the-model-reads/) | [Day 11](https://ithelp.ithome.com.tw/articles/10402496) | **可以跑了** |
| 12 | [讀那一欄](recipes/12-read-the-description/) | [Day 12](https://ithelp.ithome.com.tw/articles/10402601) | **可以跑了** |
| 13 | [那些段落是誰放進去的](recipes/13-who-wrote-your-knowledge-base/) | [Day 13](https://ithelp.ithome.com.tw/articles/10402644) | **可以跑了** |
| 14 | [同一組攻擊，每次改完 prompt 都再打一遍](recipes/14-same-attacks-every-time/) | [Day 14](https://ithelp.ithome.com.tw/articles/10402753) | **可以跑了** |
| 15 | [工具不是萬用鑰匙](recipes/15-tools-not-a-master-key/) | [Day 15](https://ithelp.ithome.com.tw/articles/10402942) | **可以跑了** |
| 16 | [誰在檢查這張單是不是你的](recipes/16-who-checks-the-owner/) | [Day 16](https://ithelp.ithome.com.tw/articles/10403127) | **可以跑了** |
| 17 | [模型講的話變成動作，中間那道閘](recipes/17-words-into-actions/) | [Day 17](https://ithelp.ithome.com.tw/articles/10403142) | **可以跑了** |
| 18 | [四道閘，跟它們各自防的是什麼](recipes/18-not-a-free-chatgpt/) | [Day 18](https://ithelp.ithome.com.tw/articles/10403409) | **可以跑了** |
| 19 | [字串直接進了 shell](recipes/19-straight-into-the-shell/) | [Day 19](https://ithelp.ithome.com.tw/articles/10403690) | **可以跑了** |
| 20 | [判斷點自己寫下它擋了什麼](recipes/20-what-did-it-block/) | Day 20 | **可以跑了** |
| 21 | [這個洞你修過了，怎麼確定它不會再回來](recipes/21-did-it-come-back/) | Day 21 | **可以跑了** |
| 22 | [把這些檢查接進 CI，並決定它什麼時候該擋你](recipes/22-when-should-it-stop-you/) | Day 22 | **可以跑了** |
| 23 | [哪些路徑真的到得了](recipes/23-what-can-actually-reach-it/) | Day 23 | **可以跑了** |
| 24 | [全綠是防住了還是沒打到](recipes/24-green-or-never-hit/) | Day 24 | **可以跑了** |
| 25 | [這份成績單不能由生它的人打](recipes/25-not-graded-by-its-author/) | Day 25 | **可以跑了** |
| 26 | [「低」長什麼樣](recipes/26-what-low-looks-like/) | Day 26 | **可以跑了**（要 Apple Silicon 與 mlx-lm） |
| 27– | 隨連載加入 | Day 27–30 | 未完成 |

每一份都是 `bash recipes/<名字>/verify.sh`。一次跑全部：

```bash
for d in recipes/*/; do bash "$d/verify.sh" >/dev/null || echo "紅了：$d"; done
```

**這張表由 `bash check-index.sh` 盯著**，少一列或指到不存在的資料夾就紅。
最新那份 recipe 的 `verify.sh` 最後一條會呼叫它，所以每天都會跑到。
會有這道閘，是因為這張表在 8/16 以前停在 06 停了十二天：
每天都有人跑 verify，沒有人重讀 README。

跑得動的前提：07 之後要 Node 20 以上，14、15、17、18 另外要 `python3`（洗牌與突變用）。
缺什麼它會直接講再退出，不會靜靜地假綠。打真模型是選配，
`MODEL_CMD` 沒設就走各自的罐頭模型，而罐頭跑出來的數字不代表任何模型的行為。

01 到 05 全部在 `mktemp -d` 裡跑，不碰你的檔案。
**06 不一樣**：它要示範「掛了什麼才是判準」，所以第 4 節會把你的家目錄
**唯讀**掛進一個沒有網路的容器一次，跑完還會留下一個約 14 MB 的映像檔
（`docker rmi ai-security-day06-verify` 清掉）。不想跑那一節就 `bash verify.sh 2`。02 只需要 `git` 跟 `curl`；
03 的第一個情境會自己抓一份 `gitleaks` 到暫存目錄，用完刪掉，不裝進你的系統；
05 要一個 Chrome 或 Chromium，沒有的話它會印一段等效的 DevTools Console 檢查；
06 的第一節只要 `curl`，後三節要 `docker`（或 `podman`、`nerdctl`），沒有就跳過。

## 每份 recipe 長什麼樣

```bash
cd recipes/01-frontend-api-key
cat README.md          # 問題、為什麼會發生、怎麼修
bash verify.sh         # 跑一次，看有洞與修好的兩版並排
bash verify.sh 2       # 只看第 2 個情境
```

`verify.sh` 檢查的是行為，不是程式碼長相，而且每一份都**並排跑兩邊**：
有洞的與修好的、naive 的檢查與正確的檢查、本機與容器。
只跑會綠的那一邊沒有價值，因為它證明不了洞是真的。

想當練習題的話，改 `before/` 裡的檔案再跑一次，看第一個情境的數字有沒有掉到 0。

## 授權

MIT。recipe 直接抄進你的專案，不用問。
