#!/usr/bin/env bash
# 產文章要貼的示範輸出。五條鏈加一次成本計算，全部走真模型。
# 輸出要自己重導向到檔案，那份留檔就是文章唯一准貼的來源（不准手打）：
#   bash rundemo.sh > runs/<輪次>/demo.txt 2>&1
#
# set -e 是必要的：靜默失敗會把錯誤訊息當成正常輸出寫進留檔，
# 然後直接變成文章內容。任何一條鏈掛掉就整份作廢，重跑。
set -euo pipefail
cd "$(dirname "$0")"
export MODEL_CMD='bash adapter.sh'
export CLASSIFY_CMD='bash classifier.sh'
export CODEX_MODEL=gpt-5.6-sol
export CLASSIFY_MODEL=claude-haiku-4-5-20251001

run() {
  echo "\$ $1"
  echo
  if ! eval "$1" 2>&1; then
    echo "上面那條掛了，這份留檔作廢" >&2
    exit 1
  fi
  echo
  echo
}

{
  run 'node chain.mjs --arm direct'
  run 'node chain.mjs --arm evade'
  run 'node cost.mjs'
  run 'node chain.mjs --arm split'
  run 'node chain.mjs --arm onemsg'
  run 'node chain.mjs --arm benignone'
}
