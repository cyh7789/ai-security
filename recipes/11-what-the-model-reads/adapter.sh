#!/usr/bin/env bash
# MODEL_CMD 的範例接法：把組好的那一串當成一則使用者訊息送出去。
# 換成任何吃 stdin、吐 stdout 的東西都可以，run-attacks.sh 不認得任何一家。
#
# 注意這支 CLI 會自己載入使用者層的規則檔，`--system-prompt` 換不掉它們，
# 所以模型收到的比你寫的多。要知道多了什麼，跑 probe-context.sh。
# 這支 CLI 有一個 `--bare` 可以跳過那些檔案，但它同時規定驗證只走 API key，
# 我這台機器上沒有，所以下面這一行是有汙染的版本。
set -u
# 約定是 stdin 進、stdout 出，所以這支自己的雜訊不要外流。
exec claude -p --system-prompt "" --model "${MODEL:-claude-haiku-4-5-20251001}" 2>/dev/null
