#!/usr/bin/env bash
# 第四道那顆分類器，走跟客服助理不同的模型。
#
#   MODEL_CMD='bash adapter.sh' CLASSIFY_CMD='bash classifier.sh' node chain.mjs --arm split
#
# 為什麼要分開：同一顆模型先產出五段、再判斷自己拼起來的東西，那是自評。
# Day 14 已經立過同一條規矩（出題的跟被測的不要是同一個），這裡是它的第二次應用。
# 8/16 第一版兩邊共用一支 adapter，是讀者那輪抓到的。
set -u
exec claude -p --model "${CLASSIFY_MODEL:-claude-haiku-4-5-20251001}" 2>/dev/null
