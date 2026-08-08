#!/usr/bin/env bash
# 起一台本地 stdio MCP server，問它有哪些工具，把每個工具的完整描述原樣印出來。
#
#   bash list-tools.sh npx -y @modelcontextprotocol/server-filesystem /tmp/somewhere
#   bash list-tools.sh docker run -i --rm some/mcp-image
#
# 這支只讀不寫：不改設定、不建檔案。但它會啟動你給的那個指令，
# 所以你要先知道那個指令是什麼。這一份的規矩是不要跑你沒讀過的東西。
#
# 用途只有一個：證明你在 UI 上看到的那幾個工具名稱，跟模型收到的東西不是同一份。
# UI 給你一行名字，模型收到的是底下這幾百到幾千個字元，而那些字元是 server
# 作者寫的，隨著它更新而改，沒有人在你這邊審過。
#
# 描述一律原樣印、不截斷。截斷就是把要給讀者看的證據刪掉，
# 而植入的指令通常就藏在描述的後半段。

set -u
HERE=$(cd "$(dirname "$0")" && pwd)

command -v node >/dev/null 2>&1 || { echo "沒有 node，這支跑不了"; exit 2; }
[ "$#" -gt 0 ] || { echo "沒給啟動指令。用法：bash list-tools.sh <指令...>"; exit 2; }

# 讀者打的那串指令要回印一次，不然畫面上看不出這張清單是問誰問來的。
# 但那串裡面可能有 -e FOO=值，所以先過一層遮蔽再印。
CMDLINE=$(printf '%s ' "$@" | node "${HERE}/mcp-config.cjs" mask)

OUT=$(node "${HERE}/mcp-rpc.cjs" tools -- "$@" 2>&1); rc=$?

# 起不來、逾時、initialize 被拒絕都走這一條。
# 這裡不能印一張空清單然後回 0：「它沒有工具」跟「我沒問到」在畫面上長得一樣，
# 而後者的意思是你什麼都還不知道。
if [ "${rc}" != 0 ]; then
  printf '問不到這台：%s\n' "${CMDLINE% }"
  printf '%s\n' "${OUT}"
  printf '這不是「它沒有工具」，是我沒問到。離開碼 %s。\n' "${rc}"
  exit "${rc}"
fi

TOTAL=$(printf '%s\n' "${OUT}" | grep '^TOTAL	' | tail -1)
NTOOLS=$(printf '%s' "${TOTAL}" | cut -f2)
NCHARS=$(printf '%s' "${TOTAL}" | cut -f3)

printf '問的是這台：%s\n' "${CMDLINE% }"
printf '下面每一段都是它自己回報的描述，原樣，沒有截斷。\n'
printf '%s\n' "${OUT}" | grep -v '^TOTAL	'

# 沒有工具是一個合法的答案，但它跟「我沒問到」的差別要講清楚，不然這張空清單
# 會被讀成「這台很乾淨」。上面那個 rc 已經把「沒問到」擋在外面了，所以走到這裡
# 的 0 是真的 0。
if [ "${NTOOLS}" = 0 ]; then
  printf '\n════════ 這台回報 0 個工具 ════════\n'
  printf 'initialize 跟 tools/list 都答了，它就是沒宣告工具。這跟問不到不一樣。\n'
  exit 0
fi

printf '\n════════ %s 個工具，描述合計 %s 字元 ════════\n' "${NTOOLS}" "${NCHARS}"
printf '你在 UI 上挑的是那 %s 個名字，模型每一輪收到的是這 %s 個字元。\n' "${NTOOLS}" "${NCHARS}"
printf '這些字元是 server 作者寫的，它更新一次就換一份，你這邊沒有人審過。\n'
