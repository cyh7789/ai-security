#!/usr/bin/env bash
# 2026-08-16 第二輪。第一輪（runs/2026-08-16/）少了兩樣，讀者那輪抓到的：
#
#   一、輸出側沒有反向控制。12/12 標記可能代表分類器有效，
#       也可能代表它對任何客服信都按 flag，兩種在只有一組資料時長得一樣。
#   二、產出跟判決是同一顆模型，那是自評（Day 14 立過的規矩）。
#
# 所以這一輪：分類器換一顆模型，並且加 benign 組。split 要跟著重跑，
# 因為換了分類器，第一輪的 12/12 就不能跟 benign 放在同一張表上比。
# direct 不用重跑，它在第三道就被規則式的閘擋掉，模型從頭到尾沒參與。
set -u
cd "$(dirname "$0")/../.."
export MODEL_CMD='bash adapter.sh'        # 客服助理
export CLASSIFY_CMD='bash classifier.sh'  # 第四道，另一顆
export CODEX_MODEL=gpt-5.6-sol
export CLASSIFY_MODEL=claude-haiku-4-5-20251001
N=12 SEED=18 OUT=runs/2026-08-16b/results.tsv CELLS="split benign" bash run-suite.sh
