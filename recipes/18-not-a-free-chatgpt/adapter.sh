#!/usr/bin/env bash
# 一個 MODEL_CMD 的實作：stdin 進、stdout 出，接 codex CLI。
# 換成 claude、curl、你公司內部的端點都可以，run-suite.sh 不認得任何一家。
#
#   MODEL_CMD='bash adapter.sh' N=12 bash run-suite.sh
#
# 只給客服助理用。第四道那顆分類器走 classifier.sh，是另一家的模型，
# 因為同一顆先產出五段再判斷自己拼起來的東西就是自評。
# （8/16 第一版兩邊共用這一支，讀者那輪抓到，8/17 這行註解才跟著改。）
# 那一顆該怎麼挑、怎麼驗是 Day 26。
set -u
exec codex exec --model "${CODEX_MODEL:-gpt-5.6-sol}" --sandbox read-only 2>/dev/null
