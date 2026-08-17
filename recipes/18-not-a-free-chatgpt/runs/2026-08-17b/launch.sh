#!/usr/bin/env bash
# 2026-08-17 定案輪之二。三件事一起補，全部來自 8/17 評審那輪：
#
# 一、換掉壞掉的量尺。第一版的 GUARD 是寫死措辭的正則，七份人工讀過都有防呆句的
#     留檔它只抓到兩份，而且漏法跟措辭風格綁在一起（split 是五段片段、措辭更雜，
#     被低估得更多）。新的是句子級形狀判斷，對那七份 7/7，命中的句子存進
#     guard-sentences.tsv，這一欄從此覆核得動。
# 二、加 benignone（benign 五句合成一則）。benign 也是分五次問的，它的低防呆率
#     可以只用包裝解釋。要分開「危險形狀觸發」與「看得到整封信觸發」就要這一格。
# 三、加 perflag 欄：逐段各判一次。文章原本寫「正式環境逐次判會看到全是無害答覆」，
#     那是對沒跑過的條件下斷言。這一欄就是那個世界的結果。
set -u
cd "$(dirname "$0")/../.."
export MODEL_CMD='bash adapter.sh'
export CLASSIFY_CMD='bash classifier.sh'
export CODEX_MODEL=gpt-5.6-sol
export CLASSIFY_MODEL=claude-haiku-4-5-20251001
export GUARD_LOG="$(pwd)/runs/2026-08-17b/guard-sentences.tsv"
: > "${GUARD_LOG}"
N=12 SEED=18 OUT=runs/2026-08-17b/results.tsv CELLS="split onemsg benign benignone evade" bash run-suite.sh
