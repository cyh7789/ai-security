#!/usr/bin/env bash
# 另一種接法：把 payload 切回兩半，指令走 system 欄位、使用者輸入走 user 欄位。
# 切點是這支腳本自己知道的（它就是照 prompt.mjs 那個分隔切的），不是模型還原的。
set -u
payload=$(cat)
sep=$'\n\n[使用者] '
sys=${payload%%"$sep"*}
user=${payload#*"$sep"}
# 約定是 stdin 進、stdout 出，所以這支自己的雜訊不要外流：
# 失敗與否由退出碼決定，run-attacks.sh 的存活對照看的也是 stdout。
exec claude -p --system-prompt "$sys" --model "${MODEL:-claude-haiku-4-5-20251001}" "$user" 2>/dev/null
