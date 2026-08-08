# 08 我裝的那幾台，各自碰得到什麼

對應 [Day 8](https://ithelp.ithome.com.tw/users/20138924/ironman/9086)。

```bash
bash inventory.sh                         清點本機所有 MCP server 設定，印成一張表
bash list-tools.sh npx -y @modelcontextprotocol/server-filesystem /tmp/x   問它有哪些工具，印完整描述
bash scan-descriptions.sh npx -y @modelcontextprotocol/server-filesystem /tmp/x   掃描述裡有沒有在對模型下指令
bash probe.sh                             收窄範圍之前後各讀一次同一個檔，證明收窄真的生效
bash verify.sh                            全部
bash verify.sh 4                          只跑「probe.sh 的離開碼分得開」那節
bash mutations.sh                         反過來：把腳本弄壞 33 種，看上面那支會不會抓到
```

**跑之前先讀腳本。** 這個系列的規矩是不要跑你沒讀過的東西，而這一份講的正好是
「你裝的那幾台你根本沒讀過」。四支主腳本加兩支共用的 `.cjs` 一共 747 行（`verify.sh` 與 `mutations.sh` 另外 688 行），
只用 `bash` 跟 `node`，不裝任何套件、不需要 `npm install`。

**只有 `probe.sh` 會在你機器上留東西**，而且只在 `/tmp/mcp-probe` 底下，跑完刪掉。
另外三支唯讀：不改設定、不建檔案。`inventory.sh` 預設連外網都不碰。
**這一份從頭到尾不會動你的 `~/.claude.json`**，`verify.sh` 每一條都在 `mktemp -d`
裡自己造一份假設定。

`probe.sh` 要用 `npx` 抓官方的 filesystem server，所以它會連外網、會寫 npm 快取。
它開頭先量 `npx` 在不在、註冊處問不問得到，缺了就印明確訊息並停在離開碼 2，
不靜默跳過。

需要 `bash`、`node`，`probe.sh` 另外需要 `npx` 與 `curl`。
2026-08-08 在 macOS 上實測（bash 3.2.57、node 24.3.0、npm 11.4.2），
工具用 PATH 影子目錄拔掉、斷線用一支一律回非零的 `curl` 替身模擬：

| 情況 | verify.sh 的反應 |
|---|---|
| 什麼都有 | 40 綠 / 0 紅 / 0 跳過，離開碼 0 |
| 沒有 `node` | 1 綠 / 0 紅 / 4 跳過，離開碼 1 |
| 沒有 `npx` | 31 綠 / 0 紅 / 3 跳過，離開碼 1。前三節照跑 |
| 沒有 `curl` | 29 綠 / 0 紅 / 1 跳過，離開碼 1。第 4 節整節不適用 |
| `curl` 在，但問不到註冊處 | 33 綠 / 0 紅 / 1 跳過，離開碼 1 |

沒有任何一種缺法會印出紅燈：**紅燈的意思是你要驗的東西壞了，不是這台機器不適用。**
反過來說跳過也不算通過，所以它把離開碼推到 1。
`bash verify.sh && echo 通過` 不該在一台連 `node` 都沒有的機器上印出那句話。

四種缺法下都還綠著的只有第 1 節那條把 `PATH` 清空、看 `inventory.sh` 會不會當場停在
離開碼 2 的檢查。它不需要任何工具在，所以少了什麼都驗得到。

打錯節號會直接停：`bash verify.sh 9` 印「沒有第 9 節」、離開碼 2。
不擋的話那會是 0 綠 0 紅 0 跳過然後離開碼 0，也就是這一份最想抓的那種假綠燈。
`bash mutations.sh 99` 同理，印「一種突變都沒跑到。沒有第 99 種，可用的是 1 到 33」、離開碼 2。

## 這裡面有什麼

| 檔案 | 是什麼 |
|---|---|
| `inventory.sh` | 清點。兩個來源都看，憑證只印變數名 |
| `list-tools.sh` | 問一台 server 有哪些工具，**描述原樣印、不截斷**，最後給字元數 |
| `scan-descriptions.sh` | 拿上面那份描述掃四類可疑樣式，命中 rc=1，**乾淨的要 rc=0** |
| `probe.sh` | 閉環那一步。自己造正反兩組，寬範圍要讀到、收窄後要讀不到 |
| `mcp-rpc.cjs` | 共用：一支最小的 MCP 客戶端，JSON-RPC 走 stdin／stdout |
| `mcp-config.cjs` | 共用：設定解析與遮蔽。**遮蔽只寫在這一支裡** |
| `verify.sh` | 四節：清點與遮蔽／描述沒被截斷／掃描器的正反對照／探針的四種離開碼 |
| `mutations.sh` | **故意把腳本弄壞三十三種，看 `verify.sh` 會不會紅。** 有一種沒紅就是假綠燈 |

兩支 `.cjs` 是共用的，複製這一份出去的時候要一起帶走。副檔名不是 `.js`：
這個 repo 的 `package.json` 寫了 `"type": "module"`，底下的 `.js` 會被當成 ES module，
`require` 就會炸；而只把這個資料夾複製出去的時候沒有 `package.json`，`.js` 又變成
CommonJS。`.cjs` 兩種情況都是 CommonJS。

## 只跑 `claude mcp list` 會漏掉一整批

`claude mcp list` 印的是「你現在這個工作目錄生效的那幾台」。專案級的設定住在
`~/.claude.json` 的 `projects.<路徑>.mcpServers` 底下，一個專案一份，
你在別的目錄跑那支就看不到它們。

2026-08-08 在一台實際在用的 macOS 上量到的數字：

| 問法 | 看到幾台 |
|---|---|
| 全域的 `mcpServers` | 0 台（那個欄位是個空物件 `{}`） |
| `~/.claude.json` 的 `projects.*.mcpServers` | **11 台，散在 7 個專案底下** |
| 在 repo 根目錄跑 `claude mcp list` | 1 台 |

那 11 台裡 6 台是 `http`、2 台是 `sse`、2 台是 `stdio`，剩下 1 台**沒寫 `type`**，
只有 `command` 跟 `args`。用 `type === "stdio"` 去判斷傳輸方式的話那一台會變成
「不明」，然後它的檔案系統範圍不會被推。所以 `inventory.sh` 的判斷是
「有 `command` 就是 stdio」，`type` 只當補充。

反過來說，`claude mcp list` 也看得到設定檔裡沒有的東西：那一台是遠端連接器，
它不在 `~/.claude.json` 的任何地方。**兩個來源都不是彼此的超集**，所以要兩邊都問。

### CLI 那一路預設是關的

`claude mcp list` 沒有「只列出來、不要連線」的旗標（`claude mcp list --help`
只有 `-h`）。它一定會對每一台做健康檢查，也就是**把你正要清點的東西全部啟動一次**：
`stdio` 那幾台會真的 `docker run` 或 `npx` 起來，遠端那幾台會連出去。

清點不該有這種副作用，所以 `inventory.sh` 預設只讀設定檔，CLI 那一路要
`MCP_LIST=on` 自己打開。預設那一輪會印一行講清楚代價是什麼，因為
**檢查沒跑跟檢查跑完沒事，畫面上必須長得不一樣**。

## 憑證：不是遮起來，是根本不搬

`claude mcp list` 會把 `stdio` 那幾台的完整啟動命令列印出來，包含
`-e SOME_TOKEN=<值>`，值是原樣印的。用一份自製的假設定實測過：印出來的那一行裡
就是那四十個字元的完整 token。

直覺的做法是「名字看起來像憑證就把值換成 `***`」。那個做法的失手成本是印出一個真的
憑證，而樣式清單永遠會漏。同一台機器上就有一個叫 `mcp-cluster-id` 的 header，
`TOKEN`／`KEY`／`SECRET`／`PASSWORD`／`CREDENTIAL`／`API_KEY` 六個常見字樣一個都不沾，
值是 36 個字元。

所以這裡的規矩是**值一律不搬**：`inventory.sh` 從來沒有一條把值放進輸出的路。
變數名照樣全部列出來，看起來像憑證的後面補 `=***`，其餘只印名字。
`***` 的意思是「這裡有個值，我判定它是憑證，不給你看」，光禿禿的名字是
「宣告了這個變數，值一樣不給你看」。這樣一來，樣式清單漏掉一個名字的後果
只剩少一個提醒，而不是外流。

憑證住在三個地方，只看一個會漏掉另外兩個：

| 住在哪 | 長什麼樣 | 只看 `env` 會怎樣 |
|---|---|---|
| `env` | `"env": {"FOO_TOKEN": "..."}` | 看得到 |
| `headers` | `"headers": {"FOO_API_KEY": "..."}` | 漏掉。遠端那幾台的憑證都在這裡 |
| `args` | `docker run -e FOO_TOKEN=...` | 漏掉。值是真的會傳進去的 |

`claude mcp list` 對遠端那幾台只印 URL，`headers` 它不印。所以走 CLI 那一路的
遠端 server，憑證欄印的是 `?` 不是 `no`：**沒看到不等於沒有。**

專案路徑只印最後一段。整條路徑印出來的話，一張清點表就把你的目錄樹交出去了。
但「整台機器」跟「整個家目錄」這兩種要看得出來，所以允許目錄是 `/` 的時候印的是
`/ (whole machine)`，不是被 basename 吃掉的空字串。

## UI 給你名字，模型收到的是幾千個字元

`list-tools.sh` 對官方的 filesystem server 問一次，2026-08-08 實測：
**14 個工具，描述合計 4108 字元。** 最長的一個是 `read_text_file` 的 457 字元。

你在 UI 上挑的是那 14 個名字。模型每一輪收到的是那 4108 個字元，
而那些字元是 server 作者寫的，它更新一次就換一份，你這邊沒有人審過。
`npx -y ...@latest` 那個 `@latest` 的意思就是「每次都拿最新的那一份」。

描述一律原樣印、不截斷。截斷就是把要給讀者看的證據刪掉，
而植入的指令通常就藏在描述的後半段。`verify.sh` 用一支測試樁驗這件事：
每個描述的最後一行是同一個尾端記號，記號不見了就代表被截斷了。
光重算字元數是不夠的，**一支同時把文字跟數字都截短的腳本會自己對得上自己**，
所以那條檢查的外部依據是測試樁的原始碼，不是腳本自己印的數字。

## 掃描器的四類樣式，跟它擋不住的東西

`scan-descriptions.sh` 掃四類，大小寫不敏感：

| 類 | 抓什麼 |
|---|---|
| 標籤 | `<IMPORTANT>`、`<SYSTEM>`、`<CRITICAL>`、`<INSTRUCTION>` 這類假裝是系統指令的標記 |
| 路徑 | `~/.ssh`、`id_rsa`、`id_ed25519`、`.env`、`mcp.json`、`.aws/credentials`、`.npmrc` |
| 隱瞞 | do not mention、don't tell、without telling、do not reveal、keep this secret |
| 覆寫 | ignore previous、ignore the above、disregard previous、override your instructions |

**乾淨的 server 要 rc=0**，這條是正對照，沒有它整支腳本沒有判別力：
一支一律回 1 的腳本在「四類都抓得到」那幾條上全部會過關。
官方那台 filesystem server 實測 rc=0。

離開碼有三種，因為「乾淨」跟「我沒問到」不能混在一起：問不到的時候是 2 不是 0。
server 起不來、逾時、`initialize` 被拒絕都走那一條。

樣式命中不等於那台有惡意，沒中也不等於它安全。這四類是已經公開過的手法的形狀，
換一種寫法就繞得過去。它擋的是抄現成的那一批。

## 閉環那一步：收窄之後要真的讀不到

`probe.sh` 是整份的核心，因為前面三支只回答「它宣告了什麼」，
而宣告跟實際碰得到什麼是兩件事。它自己造正反兩組：

1. 建 `/tmp/mcp-probe/allowed/ok.txt` 與 `/tmp/mcp-probe/denied/secret.txt`
2. **寬範圍**（允許目錄給 `/tmp/mcp-probe`）起 filesystem server，讀
   `denied/secret.txt` → 必須讀到。這是正對照
3. **收窄後**（允許目錄只給 `/tmp/mcp-probe/allowed`）起同一台，同一個呼叫 → 必須被拒
4. 跑完清掉 `/tmp/mcp-probe`

離開碼分四種，而**第 2 步失敗跟第 3 步失敗一定要分開**：

| 離開碼 | 意思 | 你要修什麼 |
|---|---|---|
| 0 | 兩步都符合預期 | 沒事 |
| 1 | 第 3 步失敗：收窄之後它還是讀到了 | 降權沒生效，去修設定 |
| 2 | 前置條件不到位（沒有 `npx`／沒有 `curl`／連不到外網） | 環境，而且什麼都還沒驗到 |
| 3 | 第 2 步失敗：寬範圍也讀不到 | 探針壞了，這一輪的第 3 步不算數 |

2 跟 3 分開的理由是那句要記住的話：**寬範圍讀不到的時候，收窄之後當然也讀不到，
於是第 3 步會「通過」。** 那是一顆假綠燈，而它跟真的降權成功在畫面上長得一樣。

判準是「那個記號字串有沒有出現」，不是「呼叫有沒有成功」。

### 拒絕不走 JSON-RPC 的 error 欄位

這是這一份最容易寫錯的一個地方。filesystem server 拒絕存取的時候，
回的**不是** JSON-RPC 的 error，而是一個成功的 result，裡面 `isError` 是 `true`、
理由塞在 `content` 的文字裡。只看 RPC 層有沒有 error 的客戶端會把「被拒絕」
讀成「讀到了」，而那正好是這支腳本最不能搞錯的一件事。
所以 `mcp-rpc.cjs` 把那種情形叫 `TOOLERR`，跟 `OK`、`RPCERR`、`FATAL` 分開。

拒絕的原文（2026-08-08 實測，`@modelcontextprotocol/server-filesystem` 經 `npx -y` 取得）：

```
Access denied - path outside allowed directories: /tmp/mcp-probe/denied/secret.txt not in /tmp/mcp-probe/allowed, /private/tmp/mcp-probe/allowed
```

允許目錄那一串出現兩次是因為它把你給的路徑跟它的 realpath 都登記了：
macOS 上 `/tmp` 是 `/private/tmp` 的符號連結。`verify.sh` 有一條盯著
`Access denied - path outside allowed directories` 這句原文，上游改掉的話它會紅，
因為 README 引了它。

## 邊界

這一份管的是「它宣告碰得到什麼、實際碰得到什麼」，判準只到檔案系統範圍。

- **遠端那幾台（`http`／`sse`）碰得到什麼，你的設定檔看不出來。** 範圍那一欄印
  `remote` 的意思是「我推不出來」，不是「它碰不到東西」。要知道它碰得到什麼，
  只有問它自己：`bash list-tools.sh <啟動指令>`，而那對遠端 server 不適用。
- **`stdio` 那幾台的範圍是從啟動參數裡的路徑推的。** 一台不吃路徑參數的 server
  可能自己寫死了範圍，也可能整台都能碰，所以推不到的時候印 `unknown` 不印「無」。
- **工具描述乾淨不等於那台乾淨。** 描述是它自己報的，它可以報一份、做另一件事。
  「執行的時候把它關在哪裡」是另一件事，[Day 6](../06-run-it-somewhere-else/) 那份處理。
- **`probe.sh` 驗的是 filesystem server 的允許目錄機制**，不是你那幾台。
  同一套流程套到你的 server 上要換掉那兩行啟動指令，而它有沒有「允許目錄」
  這個概念本身就要先確認。
