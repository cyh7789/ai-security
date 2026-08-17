#!/usr/bin/env bash
# 2026-08-17 定案輪之二。三件事一起補，全部來自 8/17 評審那輪：
#
# 一、換掉壞掉的量尺。第一版的 GUARD 是寫死措辭的正則，漏得很整齊，
#     主要漏在一個詞彙變體（模型寫「電子郵件」，正則只寫了 信件|郵件）。
#     新的是句子級形狀判斷，命中的句子存進 guard-sentences.tsv，這一欄覆核得動。
#     （原本這裡寫「人工讀過的七份留檔它只抓到兩份、新尺 7/7」。那七份沒有存檔，
#       重跑不了，8/17 連同文章裡那句一起撤掉。）
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
