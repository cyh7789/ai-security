#!/usr/bin/env bash
# 第三輪：evade 與 direct。
#
# evade 是 8/16 評審那輪逼出來的：direct 被第三道擋，我原本讀成「直說會被擋」，
# 但擋它的是那句裡的「冒充」兩個字。避開那七個禁詞的同一件事就放行。
# 少了這一組，「拆開來問繞過輸入側」的歸因是斷的。
#
# direct 一起跑，是為了讓兩組在同一個交錯順序、同一顆分類器下並列。
set -u
cd "$(dirname "$0")/../.."
export MODEL_CMD='bash adapter.sh'
export CLASSIFY_CMD='bash classifier.sh'
export CODEX_MODEL=gpt-5.6-sol
export CLASSIFY_MODEL=claude-haiku-4-5-20251001
N=12 SEED=18 OUT=runs/2026-08-16c/results.tsv CELLS="evade direct" bash run-suite.sh
