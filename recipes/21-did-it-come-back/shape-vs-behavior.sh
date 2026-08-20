#!/usr/bin/env bash
# 斷言寫成「程式碼長什麼樣」跟寫成「這個輸入怎麼被判」，差在哪裡。
#
#   bash shape-vs-behavior.sh
#
# 做法是把判準退回「只修了一半」的狀態，然後拿兩種斷言各問一次。
# 只修一半是真的發生過的：8/20 動手當天我以為「把『騙』從黑名單拿掉」就修好了，
# 跑下去才發現 B4 還是 deny——它改成卡在允許清單那一層，因為「公告」不在場景清單上。
#
# 這支會動到 recipe 18 的 gates.mjs，所以還原走 trap，中途 Ctrl-C 也會還原。
set -u
set -o pipefail
cd "$(dirname "$0")"

GATES=../18-not-a-free-chatgpt/gates.mjs
BAK=$(mktemp)
cp "$GATES" "$BAK"
restore() { [ -f "$BAK" ] && cp -f "$BAK" "$GATES" && rm -f "$BAK"; return 0; }
trap restore EXIT INT TERM

# 退回只修一半：黑名單那半留著（「騙」已經拿掉），場景清單那半還原回沒有「公告」。
python3 - "$GATES" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = '客服信件: ["客服信", "回覆客戶", "通知信", "公告", "信件開頭", "結尾", "語氣"],'
new = '客服信件: ["客服信", "回覆客戶", "通知信", "信件開頭", "結尾", "語氣"],'
assert s.count(old) == 1, "場景清單那一行找不到，這支示範就沒有意義了"
open(p, "w").write(s.replace(old, new))
PY

# 斷言一：形狀。「黑名單裡還有沒有『騙』」——這是修補的形狀，不是修補的效果。
if grep -q '"騙"' "$GATES"; then shape="紅"; else shape="綠"; fi

# 斷言二：行為。同一句話送進閘，看它放行還是擋下。
#
# 這裡只問 B4 那一句，不跑整支 regress.mjs。表格那一行寫的是「B4 這句話會不會過」，
# 跑整支的話收的是三條測試的總退出碼，現在剛好只有 B4 會紅所以結論一樣，
# 哪天另外兩條在這個狀態下紅了，那行標籤就在說謊（8/20 外審抓到）。
read -r behavior b4 <<EOF
$(node -e '
  Promise.all([import("../18-not-a-free-chatgpt/gates.mjs"), import("node:fs")]).then(([g, fs]) => {
    const rows = fs.readFileSync("../14-same-attacks-every-time/benign.jsonl", "utf8").trim().split("\n").map(JSON.parse);
    const r = g.scenarioGate(rows.find((x) => x.id === "B4").question);
    console.log(`${r.allow ? "綠" : "紅"} ${r.allow ? "allow" : "deny"}\t${r.reason}`);
  })')
EOF

restore
trap - EXIT INT TERM

printf '判準退回只修一半（黑名單拿掉了「騙」，場景清單還沒加「公告」）\n\n'
printf '斷言\t問的問題\t結果\n'
printf '形狀\t黑名單裡還有沒有「騙」\t%s\n' "$shape"
printf '行為\tB4 這句話送進閘會不會過\t%s\n' "$behavior"
printf '\nB4 實際的判決\t%s\n\n' "$b4"

fail=0
[ "$shape" = "綠" ] || { echo "紅：形狀斷言沒有變綠，這支示範的前提不成立了。"; fail=1; }
[ "$behavior" = "紅" ] || { echo "紅：行為斷言竟然也綠了，那兩種斷言在這個狀態下分不出高下。"; fail=1; }
# 這句話要說得準：贏的不是「行為」這個風格，是覆蓋範圍。
# 一條寫成「黑名單沒有『騙』而且場景清單有『公告』」的形狀斷言在這裡也是紅的，
# 問題是你要先知道有第二層才寫得出它，而那正是這個狀態下你不知道的東西（8/20 外審抓到）。
[ "$fail" = 0 ] && echo "形狀斷言綠、行為斷言紅：這條形狀斷言只蓋到修補的一半，而行為斷言不必先知道有幾層。"

# 還原核對。最糟的失敗是示範跑完，然後把別人的判準留在改壞的狀態。
grep -q '"公告"' "$GATES" || { echo "紅：gates.mjs 沒有還原乾淨，場景清單裡的「公告」不見了。"; fail=1; }
exit "$fail"
