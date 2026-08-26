# 量測原始檔

Day 22 那篇文章裡的每個數字都從這裡來。放這份是為了讓你自己重跑，
不是為了讓你相信我。

## 環境

那幾次量測跑在 macOS 26.5.2（Darwin 25.5.0）、Apple silicon、Node 24。
CI 那半跑在 GitHub 的 `ubuntu-24.04` runner。
**牆上時間每次都不一樣**，尤其 `07` 那支要連外去問 npm registry。

## 檔案

| 檔 | 是什麼 |
|---|---|
| `timing-before-05-fix.tsv` | 修 `05` 之前，21 支序列跑一次。合計 568 秒 |
| `timing.tsv` | 修完之後同一份量測。同一天量過 73 秒與 90 秒兩次，差在 `07` 連外的快慢 |
| `parallel.tsv` | 18／20／21 序列 10 輪對平行 10 輪，共用同一個工作目錄 |
| `isolated.tsv` | 同樣平行 10 輪，但每一支拿自己一份完整 repo 複本 |
| `05-before.txt` | 把 `05` 修補之前那一版拉出來實跑：0 條通過、24 條沒過、469 秒 |

## 自己重跑

```bash
bash measure-timing.sh          # 21 支各跑一次，產 timing.tsv
bash measure-parallel.sh 10     # 序列對平行，產 parallel.tsv
bash measure-isolated.sh 10     # 各自一份複本平行跑，產 isolated.tsv
bash reproduce-05-before.sh     # 把 05 修補前那一版拉出來跑（要八分鐘）
```

跑出來的數字跟這裡不一樣是正常的，看的是差距不是絕對值：
`parallel.tsv` 那組的重點是「序列全部通過、平行卻沒過十幾次」，不是沒過幾次。

## 一份沒有搬過來的

`reproduce-05-before.sh` 原本住在那篇文章的目錄裡，那個 repo 沒有公開。
搬過來的這份改掉了寫死的路徑，用 `git rev-parse --show-toplevel` 找 repo 根目錄。
