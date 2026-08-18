#!/usr/bin/env bash
# Day 19 定案輪。兩種問法各 12 發，同一顆模型、同一天。
set -u
cd "$(dirname "$0")/../.."
export MODEL_CMD='bash adapter.sh'
export CODEX_MODEL=gpt-5.6-sol
N=12 OUT=runs/2026-08-18 ARMS='plain withtests' node run-suite.mjs
