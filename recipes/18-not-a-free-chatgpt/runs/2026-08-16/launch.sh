#!/usr/bin/env bash
# 2026-08-16 這一輪。跑法留在這裡，不留在某個人的終端機歷史裡。
set -u
cd "$(dirname "$0")/../.."
export MODEL_CMD='bash adapter.sh'
export CODEX_MODEL=gpt-5.6-sol
N=12 SEED=18 OUT=runs/2026-08-16/results.tsv bash run-suite.sh
