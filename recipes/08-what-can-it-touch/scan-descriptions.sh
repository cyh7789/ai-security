#!/usr/bin/env bash
# 掃「別人寫的、會被送進模型上下文的字」有沒有在對模型下指令。兩個入口：
#
#   bash scan-descriptions.sh npx -y @modelcontextprotocol/server-filesystem@2026.7.10 /tmp/somewhere
#   bash scan-descriptions.sh --files ~/.claude/skills
#
# 第一個入口問一台 MCP server 要工具描述，第二個入口讀 SKILL.md 這類 markdown 指示檔。
# 兩批都是別人寫的字、都會被送進模型的上下文、都是你在畫面上只看到一個名字的東西，
# 所以同一份樣式表要對兩批各掃一次。樣式表住在 desc-scan.cjs，只有一份。
#
# 離開碼分三種，因為「乾淨」跟「我沒掃到」不能混在一起：
#   0  掃到了，四類樣式一個都沒中
#   1  掃到了，命中，逐條點名在上面
#   2  沒掃到（server 起不來、逾時、路徑讀不到、沒給東西）。這不是乾淨。
#
# 這支只讀不寫。MCP 那一路會啟動你給的那個指令，理由跟 list-tools.sh 一樣；
# --files 那一路只讀檔。
#
# MCP 那一路掃的是描述的原文，所以它跟 list-tools.sh 走同一條資料路徑：
# list-tools.sh 一截斷，這支就掃不到藏在後半段的東西。故意這樣接的，
# 這樣「描述被截斷」這個壞法會同時讓兩支失效，而 mutations.sh 打得到它。
#
# 樣式命中不等於那份東西有惡意，也不等於沒中就安全：
# 這四類是已經公開過的手法的形狀，換一種寫法就繞得過去。它擋的是抄現成的那一批。

set -u
HERE=$(cd "$(dirname "$0")" && pwd)

command -v node >/dev/null 2>&1 || { echo "沒有 node，這支跑不了"; exit 2; }
[ "$#" -gt 0 ] || { echo "沒給東西。用法：bash scan-descriptions.sh <啟動指令...>，或 --files <路徑...>"; exit 2; }

# ── --files：skill 那一批指示檔 ───────────────────────────
# 這一路不啟動任何東西，只讀檔。離開碼由 desc-scan.cjs 自己決定，三種一樣分得開。
if [ "$1" = "--files" ]; then
  shift
  node "${HERE}/desc-scan.cjs" files "$@"
  exit $?
fi

OUT=$(bash "${HERE}/list-tools.sh" "$@"); rc=$?
if [ "${rc}" != 0 ]; then
  printf '%s\n' "${OUT}"
  printf '沒問到就沒有掃到，離開碼 2。這不是「乾淨」。\n'
  exit 2
fi

printf '%s\n' "${OUT}" | head -1
printf '%s\n' "${OUT}" | node "${HERE}/desc-scan.cjs" tools
