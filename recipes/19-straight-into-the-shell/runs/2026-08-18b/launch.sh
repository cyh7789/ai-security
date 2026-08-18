#!/usr/bin/env bash
# Day 19 定案輪。兩種問法各 12 發，同一顆模型、同一天。
set -u
cd "$(dirname "$0")/../.."
export MODEL_CMD='bash adapter.sh'
export CODEX_MODEL=gpt-5.6-sol
N=12 OUT=runs/2026-08-18b ARMS='plain withtests' node run-suite.mjs
# 第一輪（runs/2026-08-18）作廢：vuln.mjs 的檔頭註解自己寫著「對 $( ) 和反引號無效」，
# 那等於把答案附在題目裡，plain 那一臂根本不 plain。註解移到 README，重跑。
