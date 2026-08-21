#!/usr/bin/env bash
# 離開碼公約的閘。一發模型都不打。
#
#   bash check-convention.sh
#
# 公約（Day 22 定的）：
#   0 綠，而且真的驗過了
#   1 紅，這是你要它擋你的那種
#   2 環境不到位或有節被跳過，沒有結論
#
# 為什麼需要一支閘來管這件事：8/21 之前這 21 支對「跳過」有四種不同的處理，
# 最糟的是 01 抓不到 esbuild 直接 exit 0，而 07 對同一件事（沒網路）給的是紅燈。
# 兩支腳本對同一個環境問題給出相反的顏色，而分支保護就是拿這個顏色決定擋不擋。
set -u
cd "$(dirname "$0")"
R=..

PASS=0; FAIL=0
ok()  { printf '  [OK]   %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }

# 有跳過概念的那幾支，收尾一定要把 SKIP 分出來。
# 沒有 SKIP 變數的支數不在這裡管：它們只會是 0 或 1，本來就符合公約。
printf '\n=== 有 SKIP 計數的那幾支，收尾要分得出 2 ===\n'
for f in "${R}"/*/verify.sh; do
  r=$(basename "$(dirname "${f}")")
  grep -q 'SKIP=\$((SKIP+1))' "${f}" || continue
  if grep -q '\[ "\${\?SKIP}\?" != 0 \] && exit 2' "${f}"; then
    ok "${r}"
  else
    bad "${r} 有跳過的節，但收尾沒有 exit 2：跳過會被當成通過"
  fi
done

# 沒有任何一支可以在「什麼都沒驗」的情況下回 0。
printf '\n=== 沒有人在跳過整支的時候回 0 ===\n'
# 排掉自己這一份：22/verify.sh 第 7 條會故意把那個字串寫進 01 再還原，
# 掃到自己的突變程式碼會變成一條永遠紅的假警報。
HITS=$(grep -n '全部跳過"; exit 0' "${R}"/*/verify.sh 2>/dev/null \
  | grep -v '^\.\./22-when-should-it-stop-you/' || true)
if [ -z "${HITS}" ]; then
  ok "沒有「全部跳過然後 exit 0」這種寫法"
else
  bad "這些支跳過整支還回 0：${HITS}"
fi

# 公約要寫在腳本裡，不是只寫在文章裡。改的人看得到才算數。
printf '\n=== 公約有寫進腳本 ===\n'
N=$(grep -l '離開碼' "${R}"/*/verify.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "${N}" -ge 8 ]; then
  ok "${N} 支的收尾附近寫了離開碼的意思"
else
  bad "只有 ${N} 支寫了，改的人看不到公約就會照舊寫"
fi

printf '\n%d 綠 %d 紅\n' "${PASS}" "${FAIL}"
[ "${FAIL}" != 0 ] && exit 1
exit 0
