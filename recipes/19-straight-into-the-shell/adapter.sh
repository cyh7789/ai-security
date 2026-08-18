#!/usr/bin/env bash
# 一個 MODEL_CMD 的實作：stdin 進、stdout 出。換成 claude、curl、你公司的端點都可以，
# run-suite.mjs 不認得任何一家。
#
#   MODEL_CMD='bash adapter.sh' N=12 OUT=runs/2026-08-18 node run-suite.mjs
set -u
exec codex exec --model "${CODEX_MODEL:-gpt-5.6-sol}" --sandbox read-only 2>/dev/null
