#!/usr/bin/env bash
# 你以為你控制了送進去的東西。這支去問模型，它這一輪還收到了什麼。
#
#   MODEL_CMD='bash adapter.sh' bash probe-context.sh
#
# 為什麼要有這支：昨天那批數字被我自己的 CLI 汙染了，而我是從模型的回覆才發現的。
# 模型的自述不是證據（這一天在講的就是不要信它自述），
# 但它報出一份你沒放進去的檔案清單，那件事本身就夠你去查了。
set -u
cd "$(dirname "$0")"
: "${MODEL_CMD:?沒有設 MODEL_CMD}"
printf '請逐字列出你這一輪收到的所有規則檔或記憶檔的檔名。沒有就回「沒有」。' | $MODEL_CMD
