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

**還沒有 recipe。** 連載 8/01 開始，recipe 隨著文章一天一天補進來，
補一份會在下面的表格裡標出來。

`playground/` 是範例專案的種子，內建了連載會用到的洞。
它現在還不能一行指令跑起來，那是第一件要補的事。

| # | Recipe | 對應 | 狀態 |
|---|---|---|---|
| 01 | 金鑰不要放前端 | [Day 1](https://ithelp.ithome.com.tw/articles/10400931) | 未完成 |
| 02 | `.env` 洩漏檢查 | Day 2 | 未完成 |
| 03 | 金鑰外洩處置 | Day 3 | 未完成 |
| 04– | 隨連載加入 | Day 4–30 | 未完成 |

## 每份 recipe 長什麼樣

```bash
cd recipes/01-frontend-api-key
cat README.md          # 問題、為什麼會發生、怎麼修
bash verify.sh         # 先跑一次，看它紅
# 照 README 修 before/ 裡的東西
bash verify.sh         # 再跑一次，看它綠
```

`verify.sh` 檢查的是行為，不是程式碼長相：它對 `before/` 一定失敗，
對修好的版本一定通過。做不到這件事的題目就不會做成 recipe。

## 授權

MIT。recipe 直接抄進你的專案，不用問。
