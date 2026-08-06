# 來源快照

文章裡每個旗標的官方說明，原句都在這裡，不用相信轉述。

| 檔案 | 來源 |
|---|---|
| `docker-network-none.txt` | Docker 官方文件，None network driver |
| `docker-cli-run.txt` | Docker 官方文件，`docker container run` 的旗標一覽 |
| `claims.tsv` | 對照表：主張代號、快照檔、原句、線上比對網址 |
| `embracethered-copilot-cve.txt` | CVE-2025-53773 的揭露文（Johann Rehberger） |
| `msrc-cve-2025-53773.txt` | 微軟 MSRC 的 CVRF 條目，CVE 頁本身是前端渲染抓不到內文 |
| `claims.tsv` 的第 4 欄 | 線上比對網址 |
| `fetch.sh` | 重抓，覆寫快照 |

想自己核一遍：

```bash
tail -n +2 sources/claims.tsv | while IFS=$'\t' read -r k f q u s; do
  grep -qF -- "$q" "sources/$f" && echo "OK   $k" || echo "MISS $k"
done
```

快照會過期，`fetch.sh` 重抓之後**再跑一次上面那段檢查**。
（`verify.sh` 不做來源比對，它管的是隔離。這一層要你自己按。）

頁面改版導致對不上，是頁面變了不是這裡寫錯，
但那時候文章那句話就要跟著改。
