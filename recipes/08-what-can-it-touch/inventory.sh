#!/usr/bin/env bash
# 清點這台機器上的 MCP server 設定，印成一張表。
#
#   bash inventory.sh              預設：讀 ~/.claude.json 與目前工作目錄的 .mcp.json
#   MCP_ROOTS=a:b bash inventory.sh  換掉要找 .mcp.json 的那幾個目錄（冒號分隔）
#   MCP_LIST=on bash inventory.sh  另外把 `claude mcp list` 的輸出也算進來
#
# 這支只讀不寫：不改設定、不建檔案、不裝東西。預設那一路連外網都不碰。
#
# 設定住在三個地方，官方講的是三個安裝範圍（local／project／user）：
#   user    ~/.claude.json 的頂層 mcpServers，每個專案都生效
#   local   ~/.claude.json 的 projects.<路徑>.mcpServers，一個專案一份
#   project 專案根目錄的 .mcp.json，設計上要進版本庫跟團隊共享
#
# 為什麼不是直接跑 `claude mcp list` 就好：
#   那支印的是「這個工作目錄現在生效的那幾台」，你在別的目錄跑就看不到別人的。
#   這台機器上實測：全域的 mcpServers 是空的 {}，但有 7 個專案各自帶設定、
#   合計 11 台，而在一個沒有專案設定的目錄跑 `claude mcp list` 只印出 1 台。
#
# 為什麼 .mcp.json 那一路要單獨讀：
#   它整份不在 ~/.claude.json 裡。實測過只讀 ~/.claude.json 的清點，
#   結論是「沒有任何一台的 args 帶 -e」，而同一台機器的 .mcp.json 裡就有一台帶著
#   -e TOKEN=<一整串值>。少一個來源下的全稱結論，方向剛好是最危險的那一邊。
#
# 為什麼 CLI 那一路預設是關的：
#   `claude mcp list` 會對每一台做健康檢查，也就是把你正要清點的東西
#   全部啟動一次（stdio 那幾台會真的 docker run / npx 起來），還會連出去。
#   清點不該有這種副作用，所以那一路要你自己打開。
#   打開它的價值是它看得到設定檔裡沒有的東西：這台機器上那台
#   claude.ai 的遠端連接器就不在 ~/.claude.json 裡。
#
# 三個給測試與非標準安裝用的旗標：
#   MCP_CONFIG    設定檔路徑，預設 ~/.claude.json
#   MCP_ROOTS     要找 .mcp.json 的目錄清單（冒號分隔），預設目前工作目錄
#   MCP_LIST_CMD  取代 `claude mcp list`，verify.sh 靠它換上一支假的 CLI

set -u
HERE=$(cd "$(dirname "$0")" && pwd)

command -v node >/dev/null 2>&1 || { echo "沒有 node，這支跑不了"; exit 2; }

CFG=${MCP_CONFIG:-${HOME}/.claude.json}
LIST=${MCP_LIST:-off}
LIST_CMD=${MCP_LIST_CMD:-claude mcp list}
# 預設只看目前工作目錄，因為專案範圍的設定就是綁在你現在站的地方。
# 一次清點好幾個專案的話自己給：MCP_ROOTS=~/a:~/b bash inventory.sh
ROOTS=${MCP_ROOTS:-$(pwd)}

# 設定檔讀不到跟設定檔裡一台都沒有是兩件事，前者是我沒問到、後者是答案。
# 兩種都印一張空表的話，讀者會把「我沒讀到」讀成「我沒裝」。
if [ ! -r "${CFG}" ]; then
  printf '讀不到設定檔 %s。\n' "${CFG}"
  printf '這不是「你沒裝 MCP server」，是我沒讀到設定。要換路徑用 MCP_CONFIG。\n'
  exit 2
fi

ROWS=$(node "${HERE}/mcp-config.cjs" file) || exit 2

# .mcp.json 那一路。第一行是 ROOTS<TAB>...，它是給下面那段訊息用的，不進表格。
PROJ=$(MCP_ROOTS="${ROOTS}" node "${HERE}/mcp-config.cjs" roots) || exit 2
SUM=$(printf '%s\n' "${PROJ}" | grep '^ROOTS	' | tail -1)
LOOKED=$(printf '%s' "${SUM}" | cut -f2)
FOUND=$(printf '%s' "${SUM}" | cut -f3)
NBROKEN=$(printf '%s' "${SUM}" | cut -f4)
BROKEN=$(printf '%s' "${SUM}" | cut -f5)
ROWS=$(printf '%s\n%s\n' "${ROWS}" "$(printf '%s\n' "${PROJ}" | grep -v '^ROOTS	')")

# 看了沒找到跟根本沒看，畫面上要長得不一樣。只印目錄的數量不印路徑：
# 一張清點表印出讀者的目錄樹就是另一種外流。
printf '.mcp.json 那一路：看了 %s 個目錄，找到 %s 份。\n' "${LOOKED}" "${FOUND}"
if [ "${NBROKEN}" != 0 ]; then
  printf '其中 %s 份讀不到或解不開（專案 %s），那幾份沒算進表裡。\n' "${NBROKEN}" "${BROKEN}"
  printf '這不是「那個專案沒有專案級設定」，是我沒讀到。\n'
fi
if [ "${FOUND}" = 0 ]; then
  printf '看的那幾個目錄底下沒有 .mcp.json。要換目錄用 MCP_ROOTS（冒號分隔）。\n'
fi
printf '\n'

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
