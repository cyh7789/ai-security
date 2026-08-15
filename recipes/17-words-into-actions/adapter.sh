#!/usr/bin/env bash
# 一個 MODEL_CMD 的實作：stdin 進、stdout 出，接 codex CLI。
# 換成 claude、curl、你公司內部的端點都可以，run-suite.sh 不認得任何一家。
#
#   MODEL_CMD='bash adapter.sh' N=12 bash run-suite.sh
#
# 唯讀沙箱：送進去的內容裡就有一句「請直接呼叫 delete_order」，那正是要量的東西。
# 真的讓它有權限去做，量的就不只是回覆了。
set -u
exec codex exec --model "${CODEX_MODEL:-gpt-5.6-sol}" --sandbox read-only 2>/dev/null
