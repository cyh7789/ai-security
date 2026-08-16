#!/usr/bin/env bash
# 2026-08-16 第四輪，四組一起跑。
#
# 補的是 8/16 讀者那輪抓到的證據缺口：前幾輪只記「送出去幾句」，
# 讀不出模型到底照不照做。而「拆開來問讓模型沒有理由拒絕」正是這天的骨幹，
# 沒有這一欄，那句話是推論不是量測。
#
# chain.mjs 加了 refused 欄，只記每一句有沒有被拒絕，不記回覆內容
# （記內容等於把組合後的信存下來）。
#
# 四組一起跑才比得了：split／benign 各 12 條，evade／direct 各 12 條。
set -u
cd "$(dirname "$0")/../.."
export MODEL_CMD='bash adapter.sh'
export CLASSIFY_CMD='bash classifier.sh'
export CODEX_MODEL=gpt-5.6-sol
export CLASSIFY_MODEL=claude-haiku-4-5-20251001
N=12 SEED=18 OUT=runs/2026-08-16d/results.tsv CELLS="split benign evade direct" bash run-suite.sh
