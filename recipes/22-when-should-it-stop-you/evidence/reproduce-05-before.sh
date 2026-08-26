#!/usr/bin/env bash
# 把 05 修好之前那一版拉出來跑一次，證明「500 秒、0 條通過、26 條沒過」不是我記錯的。
#
#   bash reproduce-05-before.sh
#
# 這支要跑八分多鐘（那正是它的重點），所以不進 verify.sh 的常規流程，
# 產出的快照留在 sources/05-before.txt，verify.sh 讀那份。
#
# 在複本裡跑，不碰工作目錄那一份：這支的舊版會卡住 Chrome，
# 讓它去動本尊的目錄是自找麻煩。
set -u
cd "$(dirname "$0")"
AI=../../../ai-security
OUT=sources/05-before.txt

# 那個修補的 commit。它的父版本就是「還沒修」的狀態。
# 不要用 -S 找那個版本號：-S 算的是出現次數，而這次修補把它從路徑搬到註解，
# 次數沒變（1 → 1），-S 匹配不到，會一路找到建立這份 recipe 的那個 commit。
FIX=$(git -C "${AI}" log --all --format=%H \
        --grep='找瀏覽器不要把 puppeteer 的版本號寫死' | head -1)
[ -n "${FIX}" ] || { echo "找不到那個修補的 commit"; exit 2; }
BEFORE=$(git -C "${AI}" rev-parse "${FIX}^")

WS=$(mktemp -d)
trap 'rm -rf "${WS}"' EXIT INT TERM
git -C "${AI}" archive "${BEFORE}" | tar -x -C "${WS}"

LOG=${WS}/run.log
S=$(date +%s)
(cd "${WS}/recipes/05-innerhtml-fake-green" && bash verify.sh > "${LOG}" 2>&1)
RC=$?
E=$(date +%s)

{
  printf '# 這是 05 修好之前那一版（%s）跑出來的。\n' "$(git -C "${AI}" rev-parse --short "${BEFORE}")"
  printf '# 產生方式：bash posts/day22/reproduce-05-before.sh\n\n'
  printf '$ cd recipes/05-innerhtml-fake-green && bash verify.sh\n'
  grep -m1 'Trying to load the allocator' "${LOG}" | sed 's/^ */    /'
  printf '...\n'
  tail -2 "${LOG}"
  printf '\n離開碼 %s，跑了 %s 秒，FAIL 有 %s 行\n' \
    "${RC}" "$((E-S))" "$(grep -c '^  沒過' "${LOG}")"
} > "${OUT}" 2>&1

echo "存了 ${OUT}："
cat "${OUT}"
