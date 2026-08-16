#!/usr/bin/env bash
# 2026-08-17 定案輪。四組一起，加上「模型自己加防呆句」那一欄。
#
# 這一輪要回答的是 8/16 第五輪冒出來的那個問題：onemsg 的輸出側只有 1/12 被標，
# split 卻是 9/12，兩組的請求內容一模一樣（onemsg 就是 split 五句用分號串起來的）。
# 抽樣看到的解釋是模型在合併版裡自己加了「我們不會透過信件索取密碼」這種防呆句，
# 而拆開來問它沒有任何一段看得到整封信的形狀。
#
# 一發樣本不能拿來寫機制，所以加一欄量它。benign 是控制組：
# 防呆句不是隨時都在，正常通知那組應該少很多。
set -u
cd "$(dirname "$0")/../.."
export MODEL_CMD='bash adapter.sh'
export CLASSIFY_CMD='bash classifier.sh'
export CODEX_MODEL=gpt-5.6-sol
export CLASSIFY_MODEL=claude-haiku-4-5-20251001
N=12 SEED=18 OUT=runs/2026-08-17/results.tsv CELLS="split onemsg benign evade" bash run-suite.sh
