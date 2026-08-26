#!/usr/bin/env bash
# 守離開碼公約的那支。一發模型都不打。
#
#   bash check-convention.sh
#
# 公約（Day 22 定的）：
#   0 全部通過，而且真的驗過了
#   1 有沒過的，這是你要它擋你的那種
#   2 環境不到位或有節被跳過，沒有結論
#
# 為什麼需要一支東西來管：8/21 之前這 21 支對「跳過」有四種不同的處理，
# 最糟的是 01 抓不到 esbuild 直接 exit 0，而 07 對同一件事（沒網路）判的是沒過。
# 兩支腳本對同一個環境問題給出相反的判定，而分支保護就是拿這個判定決定擋不擋。
set -u
cd "$(dirname "$0")"
R=..

PASS=0; FAIL=0
ok()  { printf '  通過   %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  沒過   %s\n' "$1"; FAIL=$((FAIL+1)); }

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
# 掃到自己的突變程式碼會變成一條永遠沒過的假警報。
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

# 分級表跟 workflow 兩邊都是手寫的，沒有東西讀對方。22 自己就是這樣漏掉一天的：
# 這一份定了公約，卻沒被加進矩陣，而沒有任何一條檢查會發現。
printf '\n=== 分級表的每一支都在 workflow 或 nightly 裡 ===\n'
LV=${R}/22-when-should-it-stop-you/levels.tsv
WF=$(cat "${R}/../.github/workflows/checks.yml" "${R}/../.github/workflows/nightly.yml" 2>/dev/null)
MISS=""; EXTRA=""
while IFS="	" read -r name level _rest; do
  case "${name}" in ''|'#'*|recipe) continue ;; esac
  # E 級是宣告過的例外：託管 runner 上沒有那個硬體。要求它進矩陣只會得到一個
  # 永遠回 2 的 job。豁免寫在這裡而不是靠人記得，代價寫在 levels.tsv 那一欄。
  #
  # 但豁免不是免費的：E 級在 CI 上零覆蓋，唯一還會逼它證明自己的東西是
  # mutations.sh。沒有那一支就填 E，等於把一支沒人驗過的檢查合法化。
  if [ "${level}" = E ]; then
    if [ ! -f "${R}/${name}/mutations.sh" ]; then
      bad "${name} 填了 E 級（CI 上零覆蓋）卻沒有 mutations.sh"
    # 有那支還不夠：硬體不到位的時候它要說「沒有結論」，不是把整張表印成通過。
    # 26 就是這樣壞過一次（沒有模型時十條全是假通過，輸出跟真的跑過逐字相同）。
    elif ! grep -q 'exit 2' "${R}/${name}/mutations.sh"; then
      bad "${name} 的 mutations.sh 沒有「硬體不到位就回 2」的出口"
    else
      ok "${name}（E 級）有 mutations.sh，而且硬體不到位會回 2"
    fi
    continue
  fi
  # 兩種寫法都算數：矩陣那一行，或自己一個 job 裡 cd 進去。
  # 不可以只認「名字有出現」，因為 checks.yml 最後那個清潔檢查也會列名字，
  # 認名字的話從矩陣拿掉一支照樣通過（2026-08-22 實測，這條因此重寫過一次）。
  printf '%s' "${WF}" | grep -qE -- "^ +- ${name}\$|recipes/${name}" \
    || MISS="${MISS} ${name}(${level})"
done < "${LV}"
# 反過來：矩陣上有、分級表沒有的
for n in $(printf '%s' "${WF}" | sed -n 's/^ *- \([0-9][0-9]-[a-z0-9-]*\)$/\1/p' | sort -u); do
  grep -q "^${n}	" "${LV}" || EXTRA="${EXTRA} ${n}"
done
if [ -z "${MISS}" ] && [ -z "${EXTRA}" ]; then
  ok "分級表與 workflow 的 recipe 清單一致"
else
  [ -n "${MISS}" ] && bad "分級表有、workflow 沒有：${MISS}"
  [ -n "${EXTRA}" ] && bad "workflow 有、分級表沒有：${EXTRA}"
fi

printf '\n通過 %d、沒過 %d\n' "${PASS}" "${FAIL}"
[ "${FAIL}" != 0 ] && exit 1
exit 0
