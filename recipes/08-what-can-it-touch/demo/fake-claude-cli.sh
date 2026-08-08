#!/bin/sh
# 一支假的 `claude mcp list`。內容全部是編的，跟你這台機器沒有關係。
#
#   MCP_LIST=on MCP_LIST_CMD="bash demo/fake-claude-cli.sh" bash inventory.sh
#
# 形狀照真的那支：第一行是健康檢查的抬頭，然後一行一台「名字: 那一串 - 狀態」。
# 兩件事故意留在裡面，因為它們是真的那支會做的：
#
#   1  stdio 那幾台的完整啟動命令列是原樣印的，包含 -e NAME=值。下面 shop-db 那一行
#      的密碼就在畫面上。inventory.sh 讀完之後那個值不會出現在表上，這是正反對照。
#   2  連不上的時候，錯誤訊息會把它連的那台主機名整句印出來。下面 internal-wiki
#      那一行印了兩次同一個內網主機名：一次在 URL 裡，一次在解析失敗的原因裡。
#      清點一次就等於把內網的命名貼在畫面上，而截圖跟貼上聊天室的人不會注意到。
#
# notes-connector 那一台在 demo/claude.json 裡找不到：CLI 這一路看得到設定檔裡沒有的東西。
echo "Checking MCP server health…"
echo ""
echo "files: npx -y @modelcontextprotocol/server-filesystem /Users/you/work/web-shop/docs - ✔ Connected"
echo "tracker: https://tracker.example.invalid/mcp (HTTP) - ✔ Connected"
echo "shop-db: docker run -i --rm -e DB_PASSWORD=FAKEdemo-db-pw-4c81e0a9f37b postgres-mcp --dsn postgres://demo@db.example.invalid:5432/shop - ✔ Connected"
echo "notes-connector: https://notes-connector.example.invalid/mcp (HTTP) - ✔ Connected"
echo "internal-wiki: http://mcp-gw-7.dept-internal.invalid:8443/mcp (HTTP) - ✘ Failed to connect — ENOTFOUND: getaddrinfo ENOTFOUND mcp-gw-7.dept-internal.invalid"
