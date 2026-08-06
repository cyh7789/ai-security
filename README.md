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
| 06 | [它在哪裡跑](recipes/06-run-it-somewhere-else/) | Day 6 | **可以跑了** |
| 07– | 隨連載加入 | Day 7–30 | 未完成 |

```bash
bash recipes/01-frontend-api-key/verify.sh
bash recipes/02-secret-scan-blind-spots/verify.sh
bash recipes/03-revoke-verification/verify.sh
bash recipes/04-what-not-to-paste/verify.sh
bash recipes/05-innerhtml-fake-green/verify.sh
bash recipes/06-run-it-somewhere-else/verify.sh
```

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
