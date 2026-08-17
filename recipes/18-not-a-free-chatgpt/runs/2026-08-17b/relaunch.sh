#!/usr/bin/env bash
# 這一輪掛掉時補跑用。環境變數要跟 launch.sh 逐字一樣，否則補回來的那幾條
# 會是另一顆模型、另一個分類器跑出來的，混在同一個檔裡看不出來。
# 差別只有兩個：不重建 results.tsv（resume.sh 只附加），也不清空 GUARD_LOG。
set -u
cd "$(dirname "$0")/../.."
export MODEL_CMD='bash adapter.sh'
export CLASSIFY_CMD='bash classifier.sh'
export CODEX_MODEL=gpt-5.6-sol
export CLASSIFY_MODEL=claude-haiku-4-5-20251001
export GUARD_LOG="$(pwd)/runs/2026-08-17b/guard-sentences.tsv"
N=12 OUT=runs/2026-08-17b/results.tsv CELLS="split onemsg benign benignone evade" bash resume.sh
