#!/usr/bin/env bash
# 對紀錄裡的每一份生成程式碼問「擋下來之後還洩不洩漏這筆存不存在」。
#
#   bash enum-all.sh                       # 印到 stdout
#   bash enum-all.sh runs/2026-08-15/gen   # 指定目錄
#
# 每一組要用自己的資源形狀去問，用錯形狀會問到它根本沒在看的參數，
# 兩邊都回同一句參數錯誤，看起來像「分不開」，其實是問錯問題。
set -u
cd "$(dirname "$0")"
D="${1:-runs/2026-08-15/gen}"
[ -d "$D" ] || { echo "沒有 $D"; exit 2; }
node enumerable.mjs --kind direct "$D"/bare-*.mjs "$D"/owned-*.mjs "$D"/vague-*.mjs "$D"/nohint-*.mjs "$D"/patch-*.mjs
node enumerable.mjs --kind nested "$D"/nested-*.mjs
node enumerable.mjs --kind list   "$D"/list-*.mjs
