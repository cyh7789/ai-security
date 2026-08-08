# 08 我裝的那幾台，各自碰得到什麼

對應 [Day 8](https://ithelp.ithome.com.tw/users/20138924/ironman/9086)。

```bash
bash inventory.sh                         清點本機所有 MCP server 設定，印成一張表
MCP_ROOTS=~/work/a:~/work/b bash inventory.sh   換掉要找 .mcp.json 的那幾個目錄
bash list-tools.sh npx -y @modelcontextprotocol/server-filesystem@2026.7.10 /tmp/x   問它有哪些工具，印完整描述
bash scan-descriptions.sh npx -y @modelcontextprotocol/server-filesystem@2026.7.10 /tmp/x   掃描述裡有沒有在對模型下指令
bash scan-descriptions.sh --files ~/.claude/skills   同一批樣式掃 SKILL.md 這類指示檔
bash probe.sh                             收窄範圍之前後各讀一次同一個檔，證明收窄真的生效
bash verify.sh                            全部
bash verify.sh 4                          只跑「probe.sh 的結束碼分得開」那節
bash mutations.sh                         反過來：把腳本弄壞 44 種，看上面那支會不會抓到
```

## 先讀這個：`claude mcp list` 會把你正要清點的東西全部啟動一次

直覺會想「清點嘛，跑一下官方的 `claude mcp list` 就好」。那支不是唯讀的，兩件事要先知道。

**第一，它會對每一台做健康檢查。** 那不是讀設定，是把你正要清點的東西全部起一次：
`stdio` 那幾台會真的 `docker run` 或 `npx` 起來，遠端那幾台會連出去。
沒有旗標可以關掉它，`claude mcp list --help` 底下只有 `-h`，而說明自己就寫著
（2026-08-08 實測，Claude Code 2.1.226）：

```
List configured MCP servers. Unapproved .mcp.json servers are shown as ⏸ Pending
approval and not connected to; approved servers are health-checked.
```

只有還沒核准的 `.mcp.json` 那幾台例外，核准過的一律連。清點一台你根本不信的 server
之前先把它啟動一次，順序是反的。

**第二，連不上的時候，錯誤訊息會把它連的那台主機名整句印出來。**
用一份自製的假設定實測到的原文（主機名是編的，`.invalid` 保證解不到）：

```
internal-wiki: http://mcp-gw-7.dept-internal.invalid:8443/mcp (HTTP) - ✘ Failed to connect — ENOTFOUND: getaddrinfo ENOTFOUND mcp-gw-7.dept-internal.invalid
```

同一個內網主機名出現兩次：一次在 URL 裡，一次在解析失敗的原因裡。
一張清點表就把內網的命名規則貼在畫面上，而截圖貼進聊天室的人不會注意到那半行。

所以 `inventory.sh` 預設只讀設定檔，CLI 那一路要 `MCP_LIST=on` 自己打開。
預設那一輪會印一行講清楚代價是什麼，因為**檢查沒跑跟檢查跑完沒事，畫面上必須長得不一樣**。
打開它的價值是它看得到設定檔裡沒有的東西：這台機器上那台遠端連接器就不在任何一份設定檔裡。

## 跑之前先讀腳本

這個系列的規矩是不要跑你沒讀過的東西，而這一份講的正好是「你裝的那幾台你根本沒讀過」。
四支主腳本加三支共用的 `.cjs` 一共 1024 行（`verify.sh` 與 `mutations.sh` 另外 980 行），
只用 `bash` 跟 `node`，不裝任何套件、不需要 `npm install`。

**只有 `probe.sh` 會在你機器上留東西**，而且只在 `/tmp/mcp-probe` 底下，跑完刪掉。
另外三支唯讀：不改設定、不建檔案。`inventory.sh` 預設連外網都不碰。
**這一份從頭到尾不會動你的 `~/.claude.json`，也不會動任何 `.mcp.json`**，
`verify.sh` 每一條都在 `mktemp -d` 裡自己造一份假設定。

`probe.sh` 要用 `npx` 抓官方的 filesystem server，所以它會連外網、會寫 npm 快取。
它開頭先量 `npx` 在不在、註冊處問不問得到，缺了就印明確訊息並停在結束碼 2，
不靜默跳過。

需要 `bash`、`node`，`probe.sh` 另外需要 `npx` 與 `curl`。
2026-08-08 在 macOS 上實測（bash 3.2.57、node 24.3.0、npm 11.4.2），
工具用 PATH 影子目錄拔掉、斷線用一支一律回非零的 `curl` 替身模擬：

| 情況 | verify.sh 的反應 |
|---|---|
| 什麼都有 | 74 綠 / 0 紅 / 0 跳過，結束碼 0 |
| 沒有 `node` | 1 綠 / 0 紅 / 7 跳過，結束碼 1 |
| 沒有 `npx` | 65 綠 / 0 紅 / 3 跳過，結束碼 1 |
| 沒有 `curl` | 63 綠 / 0 紅 / 1 跳過，結束碼 1 |
| `curl` 在，但問不到註冊處 | 67 綠 / 0 紅 / 1 跳過，結束碼 1 |

（2026-08-08 重量。缺工具那幾列的量法是把 `PATH` 上所有可執行檔連到一個暫存目錄、
只少掉指定那一支，這樣 `command -v` 才真的找不到它。用「放一支回傳 127 的假工具」
量會得到一堆紅，那是量法的錯不是降級壞了。）

沒有任何一種缺法會印出紅燈：**紅燈的意思是你要驗的東西壞了，不是這台機器不適用。**
反過來說跳過也不算通過，所以它把結束碼推到 1。
`bash verify.sh && echo 通過` 不該在一台連 `node` 都沒有的機器上印出那句話。

四種缺法下都還綠著的只有第 1 節那條把 `PATH` 清空、看 `inventory.sh` 會不會當場停在
結束碼 2 的檢查。它不需要任何工具在，所以少了什麼都驗得到。

打錯節號會直接停：`bash verify.sh 9` 印「沒有第 9 節」、結束碼 2。
不擋的話那會是 0 綠 0 紅 0 跳過然後結束碼 0，也就是這一份最想抓的那種假綠燈。
`bash mutations.sh 99` 同理，印「一種突變都沒跑到。沒有第 99 種，可用的是 1 到 41」、結束碼 2。

## 這裡面有什麼

| 檔案 | 是什麼 |
|---|---|
| `inventory.sh` | 清點。三個來源都看，憑證只印變數名 |
| `list-tools.sh` | 問一台 server 有哪些工具，**描述原樣印、不截斷**，最後給字元數 |
| `scan-descriptions.sh` | 拿工具描述或指示檔掃四類可疑樣式，命中 rc=1，**乾淨的要 rc=0** |
| `probe.sh` | 閉環那一步。自己造正反兩組，寬範圍要讀到、收窄後要讀不到 |
| `mcp-rpc.cjs` | 共用：一支最小的 MCP 客戶端，JSON-RPC 走 stdin／stdout |
| `mcp-config.cjs` | 共用：設定解析與遮蔽。**遮蔽只寫在這一支裡** |
| `desc-scan.cjs` | 共用：四類樣式表與掃描。**樣式表只有這一份**，兩個入口共用 |
| `demo/` | 全部是編的假設定，用來重現文章裡的示範輸出。裡面沒有一個真的東西 |
| `verify.sh` | 七節：清點與遮蔽／描述沒被截斷／掃描器的正反對照／探針的四種結束碼／`.mcp.json` 那一路／掃指示檔那一路／`demo/` 跑得動 |
| `mutations.sh` | **故意把腳本弄壞四十一種，看 `verify.sh` 會不會紅。** 有一種沒紅就是假綠燈 |

三支 `.cjs` 是共用的，複製這一份出去的時候要一起帶走。副檔名不是 `.js`：
這個 repo 的 `package.json` 寫了 `"type": "module"`，底下的 `.js` 會被當成 ES module，
`require` 就會炸；而只把這個資料夾複製出去的時候沒有 `package.json`，`.js` 又變成
CommonJS。`.cjs` 兩種情況都是 CommonJS。

## 設定住在三個地方，只讀一個就下全稱結論會錯

官方講的是三個安裝範圍（[MCP installation scopes](https://code.claude.com/docs/en/mcp)），
對應到兩個檔案：

| 範圍 | 住在哪 | 誰看得到 |
|---|---|---|
| user | `~/.claude.json` 頂層的 `mcpServers` | 你所有的專案 |
| local | `~/.claude.json` 的 `projects.<路徑>.mcpServers` | 只有那一個專案，只有你 |
| project | **專案根目錄的 `.mcp.json`** | 那一個專案，而且**跟著版本庫給全隊** |

`inventory.sh` 三個都讀。`.mcp.json` 那一路預設只看目前工作目錄，因為專案範圍就是綁在
你現在站的地方；要一次看好幾個專案自己給 `MCP_ROOTS=~/work/a:~/work/b`。

這一段之所以講得這麼細，是因為它上一版就漏了。當時只讀 `~/.claude.json`，
量完之後的結論是「這台機器上沒有任何一台 server 的 args 裡帶 `-e`」。
那句話對那一個來源是真的，對這台機器是假的：同一台機器的 `.mcp.json` 裡就有一台
`docker exec -i -e SOME_TOKEN=<48 個字元> ...`。
**少一個來源就下全稱結論，錯的方向剛好是「看起來很乾淨」那一邊。**

2026-08-08 在同一台實際在用的 macOS 上量到的數字：

| 問法 | 看到幾台 |
|---|---|
| `~/.claude.json` 全域的 `mcpServers` | 0 台（那個欄位是個空物件 `{}`） |
| `~/.claude.json` 的 `projects.*.mcpServers` | **11 台，散在 7 個專案底下** |
| 開發目錄底下往下三層的 `.mcp.json` | **6 份檔案，裡面 14 台** |
| 在一個沒有專案設定的目錄跑 `claude mcp list` | 1 台（一台遠端連接器，它不在任何設定檔裡） |

那 11 台裡 7 台寫 `http`、2 台寫 `sse`、1 台寫 `stdio`，剩下 1 台**沒寫 `type`**，
只有 `command` 跟 `args`。用 `type === "stdio"` 去判斷傳輸方式的話那一台會變成
「不明」，然後它的檔案系統範圍不會被推。所以 `inventory.sh` 的判斷是
「有 `command` 就是 stdio」，`type` 只當補充。

`.mcp.json` 那 14 台更值得看：宣告出來的 4 個憑證，**4 個全部是明文，沒有一個用 `${VAR}`**，
而其中一份 `.mcp.json` 已經 commit 進版本庫，3 個憑證值就躺在 git 歷史裡。
那個檔案的設計目的就是進版控，所以它是三個來源裡最會把憑證帶出門的一路。

**三個來源沒有一個是另一個的超集**，所以要每一邊都問。

## 明文寫在檔案裡，跟 `${VAR}`，是兩件事

官方在 `.mcp.json`（`~/.claude.json` 也一樣）支援 `${VAR}` 與 `${VAR:-預設}` 展開，
`command`、`args`、`env`、`url`、`headers` 五個地方都能用。這個語法存在的理由就是
上一節那件事：檔案要進版控，值不能寫在裡面。

`inventory.sh` **從來不展開它**。展開等於把環境變數的值搬到輸出上，而這支的規矩是值一律不搬。
看到 `${...}` 就照原樣印，於是憑證欄有三種形狀：

| 印出來長這樣 | 意思 |
|---|---|
| `DB_PASSWORD=***` | 有一個值，明文寫在檔案裡，我判定它是憑證，不給你看 |
| `Authorization=${TRACKER_TOKEN}` | 值不在檔案裡，指向一個環境變數。原樣印，沒有展開 |
| `SHOP_API_BASE_URL` | 宣告了這個變數，名字不像憑證，值一樣不給你看 |

`${VAR:-預設}` 算在明文那一邊：那個預設值是真的寫在檔案裡的，所以它也不印。
判不出來的時候一律往嚴的算，因為反過來的失手成本是漏報一個真的外流。

表尾把**明文寫在 `.mcp.json` 裡**的那幾台單獨點名，跟用 `${VAR}` 的分開兩段。
混成一段的話，一份安全的設定跟一份會跟著 git 走出去的設定在表上長得一樣，
而那正好是這一節唯一想講的事。

收尾點名印的是「來源/名稱」不是光禿禿的名字：server 名字在來源之間不是唯一的。
同一個 `files` 可以在兩個專案裡各有一份，允許目錄一個是 `.../docs`、一個是整個家目錄，
而範圍最寬的那一台正好最需要指得準。

## 憑證：不是遮起來，是根本不搬

`claude mcp list` 會把 `stdio` 那幾台的完整啟動命令列印出來，包含
`-e SOME_TOKEN=<值>`，值是原樣印的。用一份自製的假設定實測過：印出來的那一行裡
就是那四十個字元的完整 token。

直覺的做法是「名字看起來像憑證就把值換成 `***`」。那個做法的失手成本是印出一個真的
憑證，而樣式清單永遠會漏。同一台機器上就有一個叫 `mcp-cluster-id` 的 header，
`TOKEN`／`KEY`／`SECRET`／`PASSWORD`／`CREDENTIAL`／`API_KEY` 六個常見字樣一個都不沾，
值是 36 個字元。

所以這裡的規矩是**值一律不搬**：`inventory.sh` 從來沒有一條把值放進輸出的路。
變數名照樣全部列出來，看起來像憑證的後面補值的形狀，其餘只印名字。
這樣一來，樣式清單漏掉一個名字的後果只剩少一個提醒，而不是外流。

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

你在 UI 上挑的是那 14 個名字。這台 server 備好要餵給模型的是那 4108 個字元，
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
| 標籤 | `<IMPORTANT>`、`&lt;system&gt;`、`<CRITICAL>`、`<INSTRUCTION>` 這類假裝是系統指令的標記 |
| 路徑 | `~/.ssh`、`id_rsa`、`id_ed25519`、`.env`、`mcp.json`、`.aws/credentials`、`.npmrc` |
| 隱瞞 | do not mention、don't tell、without telling、do not reveal、keep this secret |
| 覆寫 | ignore previous、ignore the above、disregard previous、override your instructions |

**乾淨的 server 要 rc=0**，這條是正對照，沒有它整支腳本沒有判別力：
一支一律回 1 的腳本在「四類都抓得到」那幾條上全部會過關。
官方那台 filesystem server 實測 rc=0。

結束碼有三種，因為「乾淨」跟「我沒問到」不能混在一起：問不到的時候是 2 不是 0。
server 起不來、逾時、`initialize` 被拒絕都走那一條。

樣式命中不等於那台有惡意，沒中也不等於它安全。這四類是已經公開過的手法的形狀，
換一種寫法就繞得過去。它擋的是抄現成的那一批。

### 同一批樣式要掃第二次：skill 的指示檔

工具描述不是唯一一批「別人寫的字，會被送進模型的上下文」。skill 是另一批：
你在畫面上看到一個名字跟一行描述，載進來的是整份 `SKILL.md`。同一批樣式該掃兩次。

```bash
bash scan-descriptions.sh --files ~/.claude/skills   # 目錄，往下找 markdown
bash scan-descriptions.sh --files some-skill/SKILL.md   # 直接指名一個檔
```

結束碼跟另一個入口同一套：命中 1、乾淨 0、**沒東西可掃 2**。
路徑打錯是 2，目錄底下一份 markdown 都沒有也是 2，因為那兩種的意思都是「我什麼都沒掃」，
而 0 會被讀成「掃過了、沒問題」。

樣式表只有一份（`desc-scan.cjs`），兩個入口共用。分兩份寫的話，補了一邊漏了另一邊的時候
畫面上看不出來，`mutations.sh` 有兩條就是在驗這件事：拿掉一類樣式，兩個入口要各自紅。

## 重現文章裡的示範輸出

`demo/` 底下那批設定全部是編的：沒有真的 token、沒有真的專案路徑、沒有真的服務名。
看起來像憑證的字串一律以 `FAKEdemo` 開頭，網域一律是保證解不到的 `.invalid`。
文章裡的示範輸出就是下面這幾條指令印的，你在自己機器上跑會拿到同一份。

**一、三個來源併成一張表。** 假的 `~/.claude.json`、假的專案級 `.mcp.json`、假的 `claude mcp list`：

```bash
MCP_CONFIG=demo/claude.json MCP_ROOTS=demo MCP_LIST=on \
  MCP_LIST_CMD="bash demo/fake-claude-cli.sh" bash inventory.sh
```

該印出十二列。看四件事：

- 兩列都叫 `files`，一列範圍是 `.../docs`，另一列是 `~ (whole home)`：同名不同範圍
- `shop-db` 那一列印 `DB_PASSWORD=***`，而假 CLI 的原始輸出裡那個密碼是完整的
- `tracker` 與 `search` 印 `Authorization=${TRACKER_TOKEN}` 跟 `Authorization=${SEARCH_TOKEN}`，沒有被展開
- 表尾「憑證是明文寫在 .mcp.json 裡」那一段點名 `mcp.json:demo/shop-api`，而 `mcp.json:demo/search` 在下一段

**二、假 CLI 自己印的原文**，也就是上面那張表的正對照：

```bash
bash demo/fake-claude-cli.sh
```

`shop-db` 那一行的 `DB_PASSWORD=FAKEdemo-...` 是完整的，`internal-wiki` 那一行把
同一個內網主機名印了兩次。這兩件事都是真的那支會做的。

**三、四類樣式全命中的工具描述：**

```bash
bash scan-descriptions.sh node demo/poisoned-stub.cjs
```

結束碼 1，命中 4 條，每一條點得出是哪一個工具（`lookup_order`）跟哪一類。

**四、同一批樣式掃指示檔：**

```bash
bash scan-descriptions.sh --files demo/poisoned-skill.md
```

結束碼 1，命中 4 條，每一條帶檔名跟行號。

那份檔故意不叫 `SKILL.md`：它裡面是一整段植入的指示，而會自己去找 `**/SKILL.md`
的工具不少，換個名字它們就不會把它當成一個 skill 載進去。

`verify.sh` 第 7 節在盯上面這四條。`demo/` 爛掉的話那一節會紅，
不然它會靜靜地爛在那裡，而文章裡的示範輸出對不上任何東西。

## 閉環那一步：收窄之後要真的讀不到

`probe.sh` 是整份的核心，因為前面三支只回答「它宣告了什麼」，
而宣告跟實際碰得到什麼是兩件事。它自己造正反兩組：

1. 建 `/tmp/mcp-probe/allowed/ok.txt` 與 `/tmp/mcp-probe/denied/secret.txt`
2. **寬範圍**（允許目錄給 `/tmp/mcp-probe`）起 filesystem server，讀
   `denied/secret.txt` → 必須讀到。這是正對照
3. **收窄後**（允許目錄只給 `/tmp/mcp-probe/allowed`）起同一台，同一個呼叫 → 必須被拒
4. 跑完清掉 `/tmp/mcp-probe`

結束碼分四種，而**第 2 步失敗跟第 3 步失敗一定要分開**：

| 結束碼 | 意思 | 你要修什麼 |
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
- **範圍那一欄不會去展開 `${VAR}`。** 允許目錄寫成 `${PROJECT_DIR}/docs` 的話，
  推不出路徑，那一欄是 `unknown`。展開它就等於把環境變數搬到輸出上。
- **`--files` 那一路會把你給的路徑印出來**，因為命中之後你要找得到那一行。
  它跟清點表不一樣：清點表印的是它自己找到的東西，所以只印最後一段。
- **「路徑」那一類樣式會抓 `mcp.json` 這個字串本身。** 拿 `--files` 去掃一份在講
  MCP 設定的文件，它會亮。樣式命中的意思一直都是「這裡有個已知形狀，自己去看」。
- **工具描述乾淨不等於那台乾淨。** 描述是它自己報的，它可以報一份、做另一件事。
  「執行的時候把它關在哪裡」是另一件事，[Day 6](../06-run-it-somewhere-else/) 那份處理。
- **`probe.sh` 驗的是 filesystem server 的允許目錄機制**，不是你那幾台。
  同一套流程套到你的 server 上要換掉那兩行啟動指令，而它有沒有「允許目錄」
  這個概念本身就要先確認。
