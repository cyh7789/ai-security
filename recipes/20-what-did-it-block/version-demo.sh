#!/usr/bin/env bash
# 判準改一個字，紀錄上的版本號會不會自己跟著變。
#
#   bash version-demo.sh
#
# 做法是暫時去 recipe 18 的黑名單裡加一個詞，重跑一次 demo，然後還原。
# 這支腳本會動到另一個 recipe 的檔案，所以還原走 trap：中途 Ctrl-C 也會還原。
# 跑完自己會核對檔案有沒有回到原樣，沒回到就報紅。這種腳本最糟的失敗是
# 「示範跑完了，然後把別人的判準留在改過的狀態」。
set -u
set -o pipefail
cd "$(dirname "$0")"

GATES=../18-not-a-free-chatgpt/gates.mjs
BAK=$(mktemp)
cp "$GATES" "$BAK"
restore() { [ -f "$BAK" ] && cp -f "$BAK" "$GATES" && rm -f "$BAK"; return 0; }
trap restore EXIT INT TERM

before=$(node -e 'import("./points.mjs").then(m=>console.log(m.INPUT_VERSION))')
printf "改之前\tinput-gate 判準版本\t%s\n" "$before"

python3 - "$GATES" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'export const OUT_OF_SCOPE = ["騙", "詐", "冒充", "假冒", "偽裝成", "誘導", "套出"];'
new = 'export const OUT_OF_SCOPE = ["騙", "詐", "冒充", "假冒", "偽裝成", "誘導", "套出", "代刷"];'
assert s.count(old) == 1, "黑名單那一行找不到，這支示範就沒有意義了"
open(p, "w").write(s.replace(old, new))
PY

after=$(node -e 'import("./points.mjs").then(m=>console.log(m.INPUT_VERSION))')
printf "加一個詞\tinput-gate 判準版本\t%s\n" "$after"

restore
trap - EXIT INT TERM
back=$(node -e 'import("./points.mjs").then(m=>console.log(m.INPUT_VERSION))')
printf "還原之後\tinput-gate 判準版本\t%s\n" "$back"

# 反向的那一半：改一個沒有餵進雜湊的東西，號碼不該動。
# 這一半才證明得了「雜湊只吃得到你餵給它的東西」。少了它，
# 上面那個「改判準號碼就變」只說明了一半，讀者會以為它什麼都涵蓋得到。
POINTS=points.mjs
PBAK=$(mktemp)
cp "$POINTS" "$PBAK"
# 用 -f 判一下：這支會被 trap 呼叫第二次（正常結束時已經還原過了），
# 少了它就會印一行 cp 找不到檔案的錯誤，而那看起來像示範失敗。
restore_points() { [ -f "$PBAK" ] && cp -f "$PBAK" "$POINTS" && rm -f "$PBAK"; return 0; }
trap 'restore; restore_points' EXIT INT TERM
printf '\n// 這一行是 version-demo.sh 暫時加的，跑完會拿掉。\n' >> "$POINTS"
outside=$(node -e 'import("./points.mjs").then(m=>console.log(m.INPUT_VERSION))')
restore_points
trap restore EXIT INT TERM
printf "改沒餵進去的\tinput-gate 判準版本\t%s\n" "$outside"

fail=0
[ "$before" != "$after" ] || { echo "紅：判準改了，版本號沒變。"; fail=1; }
[ "$before" = "$outside" ] || { echo "紅：改了沒餵進雜湊的地方，版本號竟然變了。"; fail=1; }
[ "$before" = "$back" ] || { echo "紅：還原之後版本號對不回去，gates.mjs 可能沒還原乾淨。"; fail=1; }
[ "$fail" = 0 ] && echo "餵進去的改了號碼就變，沒餵進去的改了號碼不動，還原之後回到原值。"
exit "$fail"
