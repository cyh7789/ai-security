# 來源快照

文章引的那幾個數字跟那幾句規格，原句都在這裡，不用相信轉述。抓於 2026-08-07。

| 檔案 | 來源 | 撐住什麼 |
|---|---|---|
| `arxiv-2406.10279-abstract.txt` | Spracklen et al.《We Have a Package for You!》USENIX Security 2025，<https://arxiv.org/abs/2406.10279> | 幻覺率 5.2%／21.7%、205,474 個不重複的幻覺套件名、576,000 個樣本 |
| `arxiv-2406.10279-fulltext.txt` | 同一篇的 v3 全文，<https://arxiv.org/html/2406.10279v3> | 重複率（RQ3）：抽 500 個提問各重跑十次，43% 十次全中、39% 一次都沒重複、58% 重複超過一次 |
| `npm-ci-docs.txt` | npm CLI v11 `npm ci`，<https://docs.npmjs.com/cli/v11/commands/npm-ci> | 沒有 lockfile 會失敗、對不上是報錯而不是改 lockfile |
| `npm-audit-signatures.txt` | npm CLI v11 `npm audit`，<https://docs.npmjs.com/cli/v11/commands/npm-audit> | 簽章驗的是下載到的檔案完整性，不是發布者可信 |
| `claims.tsv` | 對照表：主張代號、快照檔、原句、線上比對網址、正文留的片段 |
| `fetch.sh` | 重抓，覆寫快照 |

想自己核一遍：

```bash
tail -n +2 sources/claims.tsv | while IFS=$'\t' read -r k f q u s; do
  grep -qF -- "$q" "sources/$f" && echo "OK   $k" || echo "MISS $k"
done
```

快照會過期，`bash sources/fetch.sh` 重抓之後**再跑一次上面那段檢查**。
（`verify.sh` 不做來源比對，它管的是查詢腳本分不分得出「沒有」跟「沒問到」。這一層要你自己按。）

頁面改版導致對不上，是頁面變了不是這裡寫錯，但那時候文章那句話就要跟著改。

## 摘要跟全文是兩份，別互相代用

`arxiv-2406.10279-abstract.txt` 只有摘要頁，`arxiv-2406.10279-fulltext.txt` 才是 v3 全文。
`claims.tsv` 每一條都指名它住哪一份，重複率那三條在全文那份、只在全文那份。
引用之前先看第 2 欄，不要因為「都是同一篇」就把摘要裡沒有的句子算成摘要撐住的。
