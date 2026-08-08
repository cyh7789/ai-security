# demo：全部是編的假設定

這幾份是假的，跟任何一台真的機器無關，存在的理由只有一個：讓文章裡的示範輸出
在別人的機器上也印得出同一份東西。指令跟每一條該印出什麼寫在上一層的 README，
那一節叫「重現文章裡的示範輸出」。

| 檔案 | 是什麼 |
|---|---|
| `claude.json` | 假的 `~/.claude.json`。兩個專案各有一台叫 `files`，允許目錄一個是 `.../docs` 一個是整個家目錄 |
| `.mcp.json` | 假的專案範圍設定。`shop-api` 的憑證明文寫在裡面，`search` 用 `${SEARCH_TOKEN}` |
| `fake-claude-cli.sh` | 假的 `claude mcp list`，形狀照真的那支。給 `MCP_LIST_CMD` 用 |
| `poisoned-stub.cjs` | 假的 MCP server，工具描述裡四類樣式全植入 |
| `poisoned-skill.md` | 假的 skill 指示檔，同樣四類全植入 |

裡面那幾串看起來像憑證的東西都以 `FAKEdemo` 開頭，`.invalid` 是保留給「一定解不到」
的網域，`/Users/you/...` 不是任何人的家目錄。

兩件事故意這樣做：

- `poisoned-skill.md` 沒有叫 `SKILL.md`。它裡面是一整段植入的指示，
  而會自己去找 `**/SKILL.md` 的工具不少，取這個名字它們就不會把它當成一個 skill 載進去。
- `.mcp.json` 放在這個資料夾底下，不在 repo 根目錄。專案範圍的設定是綁在專案根目錄的，
  所以它不會因為你打開這個 repo 就生效。不要 `cd demo` 之後在裡面開互動工作階段。
