#!/usr/bin/env bash
# 清點這台機器上的 MCP server 設定，印成一張表。
#
#   bash inventory.sh              預設：只讀設定檔
#   MCP_LIST=on bash inventory.sh  另外把 `claude mcp list` 的輸出也算進來
#
# 這支只讀不寫：不改設定、不建檔案、不裝東西。預設那一路連外網都不碰。
#
# 為什麼不是直接跑 `claude mcp list` 就好：
#   那支印的是「這個工作目錄現在生效的那幾台」。專案級的設定住在
#   ~/.claude.json 的 projects.<路徑>.mcpServers 底下，一個專案一份，
#   你在別的目錄跑 `claude mcp list` 就看不到它們。
#   這台機器上實測：全域的 mcpServers 是空的 {}，但有 7 個專案各自帶設定、
#   合計 11 台，而在 repo 根目錄跑 `claude mcp list` 只印出 1 台。
#
# 為什麼 CLI 那一路預設是關的：
#   `claude mcp list` 會對每一台做健康檢查，也就是把你正要清點的東西
#   全部啟動一次（stdio 那幾台會真的 docker run / npx 起來），還會連出去。
#   清點不該有這種副作用，所以那一路要你自己打開。
#   打開它的價值是它看得到設定檔裡沒有的東西：這台機器上那台
#   claude.ai 的遠端連接器就不在 ~/.claude.json 裡。
#
# 兩個給測試與非標準安裝用的旗標：
#   MCP_CONFIG    設定檔路徑，預設 ~/.claude.json
#   MCP_LIST_CMD  取代 `claude mcp list`，verify.sh 靠它換上一支假的 CLI

set -u
HERE=$(cd "$(dirname "$0")" && pwd)

command -v node >/dev/null 2>&1 || { echo "沒有 node，這支跑不了"; exit 2; }

CFG=${MCP_CONFIG:-${HOME}/.claude.json}
LIST=${MCP_LIST:-off}
LIST_CMD=${MCP_LIST_CMD:-claude mcp list}

# 設定檔讀不到跟設定檔裡一台都沒有是兩件事，前者是我沒問到、後者是答案。
# 兩種都印一張空表的話，讀者會把「我沒讀到」讀成「我沒裝」。
if [ ! -r "${CFG}" ]; then
  printf '讀不到設定檔 %s。\n' "${CFG}"
  printf '這不是「你沒裝 MCP server」，是我沒讀到設定。要換路徑用 MCP_CONFIG。\n'
  exit 2
fi

ROWS=$(node "${HERE}/mcp-config.cjs" file) || exit 2

if [ "${LIST}" = "on" ]; then
  # CLI 那一路的輸出裡，stdio 那幾台的啟動命令列是原樣印的，包含 -e FOO=值。
  # 解析器不把值搬到輸出上，所以這裡也不需要先過一層遮蔽。
  cli=$(${LIST_CMD} 2>/dev/null | node "${HERE}/mcp-config.cjs" cli)
  ROWS=$(printf '%s\n%s\n' "${ROWS}" "${cli}" | grep -v '^$')
else
  printf 'CLI 那一路沒跑（預設是關的，MCP_LIST=on 打開）。\n'
  printf '打開它會讓 claude mcp list 對每一台做健康檢查，等於把你正要清點的東西全部啟動一次。\n'
  printf '代價是這一輪看不到只存在於 CLI 那一路的 server，例如遠端連接器。\n\n'
fi

printf '%s\n' "${ROWS}" | grep -v '^$' | node "${HERE}/mcp-config.cjs" table
