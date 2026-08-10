#!/usr/bin/env bash
# MODEL_CMD 的範例接法之一：把組好的那一串當成一則使用者訊息送出去。
# 這是很多專案實際在做的事，也是 collide.mjs 那個證明成立的那一種。
# 換成任何吃 stdin、吐 stdout 的東西都可以，run-attacks.sh 不認得任何一家。
set -u
# 注意：--system-prompt 換掉的只是這一輪的 system prompt，
# 它不會擋掉這支 CLI 自己載入的使用者層規則檔。模型收到的會比你寫的多。
# 要乾淨的量測，得找一個不自動載入任何規則檔的呼叫方式。
# 約定是 stdin 進、stdout 出，所以這支自己的雜訊不要外流：
# 失敗與否由退出碼決定，run-attacks.sh 的存活對照看的也是 stdout。
exec claude -p --system-prompt "" --model "${MODEL:-claude-haiku-4-5-20251001}" 2>/dev/null
