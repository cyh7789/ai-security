#!/usr/bin/env bash
# 2026-08-16 第五輪：onemsg，五句合成一則一次送出。
#
# 8/16 評審那輪抓到的對照缺口。split 相對 evade 同時動了兩個變數：
# （a）從一則變五則、（b）每一句都看不出意圖。稿子把結果全歸給 (a)，
# 但拿掉意圖不需要分成五則。這一組控制住 (b) 只動 (a)。
#
# 它是這一天唯一能回答「分次到底是不是變數」的那一格。
set -u
cd "$(dirname "$0")/../.."
export MODEL_CMD='bash adapter.sh'
export CLASSIFY_CMD='bash classifier.sh'
export CODEX_MODEL=gpt-5.6-sol
export CLASSIFY_MODEL=claude-haiku-4-5-20251001
N=12 SEED=18 OUT=runs/2026-08-16e/results.tsv CELLS="onemsg" bash run-suite.sh
