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
restore() { cp -f "$BAK" "$GATES"; rm -f "$BAK"; }
trap restore EXIT INT TERM

before=$(node -e 'import("./points.mjs").then(m=>console.log(m.INPUT_VERSION))')
echo "改之前　input-gate 判準版本　$before"

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
echo "加一個詞　input-gate 判準版本　$after"

restore
trap - EXIT INT TERM
back=$(node -e 'import("./points.mjs").then(m=>console.log(m.INPUT_VERSION))')
echo "還原之後　input-gate 判準版本　$back"

fail=0
[ "$before" != "$after" ] || { echo "紅：判準改了，版本號沒變。"; fail=1; }
[ "$before" = "$back" ] || { echo "紅：還原之後版本號對不回去，gates.mjs 可能沒還原乾淨。"; fail=1; }
[ "$fail" = 0 ] && echo "判準變、號碼跟著變，還原之後回到原值。"
exit "$fail"
