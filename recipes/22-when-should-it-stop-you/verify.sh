#!/usr/bin/env bash
# 這一份自己的檢查。一發模型都不打。
#
#   bash verify.sh
#
# 這份 recipe 的產出有兩個：一張分級表（levels.tsv）跟一個 CI 設定
# （.github/workflows/checks.yml）。兩份東西講同一件事就會分岔，
# 所以這裡第一件事就是對帳。
set -u
cd "$(dirname "$0")"
R=..
WF=../../.github/workflows/checks.yml
command -v node >/dev/null || { echo "這份要 Node 才能跑，先裝 Node 再來。"; exit 2; }

PASS=0; FAIL=0; SKIP=0
case_() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  通過   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  沒過   %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  沒有結論 %s\n' "$1"; SKIP=$((SKIP+1)); }

# ── 1 表裡的每一支都真的存在 ──────────────────────────
case_ "1 levels.tsv 列的 recipe 都在"
M=""
while IFS=$'\t' read -r r lv sec why; do
  case "${r}" in \#*|""|recipe) continue ;; esac
  [ -d "${R}/${r}" ] || M="${M} ${r}"
done < levels.tsv
[ -z "${M}" ] && ok "$(grep -cvE '^#|^recipe|^$' levels.tsv) 支都對得上目錄" || bad "找不到：${M}"

# ── 2 每一支 recipe 都有被分級 ────────────────────────
# 漏掉一支的話它不會出現在任何 CI 路徑上，而那件事沒有人會發現。
case_ "2 沒有 recipe 漏掉分級"
M=""
for d in "${R}"/*/; do
  r=$(basename "${d}")
  [ -f "${d}verify.sh" ] || continue
  [ "${r}" = "22-when-should-it-stop-you" ] && continue
  grep -q "^${r}	" levels.tsv || M="${M} ${r}"
done
[ -z "${M}" ] && ok "每一支有 verify.sh 的 recipe 都在表上" || bad "漏了：${M}"

# ── 3 表跟 workflow 沒有分岔 ──────────────────────────
case_ "3 levels.tsv 說 A 的，workflow 真的擋合併"
if [ ! -f "${WF}" ]; then
  skip "找不到 ${WF}"
else
  M=""
  while IFS=$'\t' read -r r lv sec why; do
    case "${r}" in \#*|""|recipe) continue ;; esac
    [ "${lv}" = "A" ] || continue
    # 21 刻意拆成兩個 job（防線一個、缺口樁一個），不在 matrix 裡
    [ "${r}" = "21-did-it-come-back" ] && continue
    grep -q "          - ${r}$" "${WF}" || M="${M} ${r}"
  done < levels.tsv
  [ -z "${M}" ] && ok "A 級都在 blocking 的 matrix 裡" || bad "表說 A 但 workflow 沒放：${M}"
fi

# ── 4 缺口樁那個 job 不能跟防線混在一起 ─────────────────
# 兩種沒過的正確處置相反：缺口樁沒過就是去改期望值，
# 防線沒過還去改期望值等於把防線關掉。走同一個 job 會把後者訓練成前者。
case_ "4 21 的防線與缺口樁是兩個 job"
if [ ! -f "${WF}" ]; then
  skip "找不到 ${WF}"
elif grep -q '^  regression-line:' "${WF}" && grep -q '^  gap-stake:' "${WF}"; then
  ok "regression-line 與 gap-stake 分開"
else
  bad "21 沒有拆成兩個 job：兩種沒過會走同一封通知"
fi

# ── 5 B 級不准用 continue-on-error ────────────────────
# 那個旗標把沒過顯示成通過。不擋合併跟看不見是兩回事。
case_ "5 沒有人用 continue-on-error 把沒過藏起來"
if [ ! -f "${WF}" ]; then
  skip "找不到 ${WF}"
elif grep -nE '^[^#]*continue-on-error' "${WF}" | grep -qv '^\s*[0-9]*:\s*#'; then
  # 只看真的設定行。workflow 的註解裡就寫著「不用 continue-on-error」，
  # 掃註解會讓這一條永遠沒過。
  bad "workflow 裡有 continue-on-error：$(grep -nE '^[^#]*continue-on-error' "${WF}" | head -2 | tr '\n' ' ')"
else
  ok "沒有 continue-on-error"
fi

# ── 6 離開碼公約 ──────────────────────────────────────
case_ "6 離開碼公約那道檢查自己是通過的"
if bash check-convention.sh > /tmp/r22-conv.out 2>&1; then
  ok "$(tail -1 /tmp/r22-conv.out)"
else
  bad "check-convention.sh 判沒過：$(grep '^  沒過' /tmp/r22-conv.out | head -2 | tr '\n' ' ')"
fi

# ── 7 那道檢查抓得到 ──────────────────────────────────
# 沒有真的失敗過的檢查不算數。把 01 的收尾改回 exit 0，第 6 條該沒過。
case_ "7 把 01 改回 exit 0，公約那道檢查會沒過"
T=../01-frontend-api-key/verify.sh
BAK=$(mktemp)
cp "${T}" "${BAK}"
restore7() { cp -f "${BAK}" "${T}"; rm -f "${BAK}"; }
trap restore7 EXIT INT TERM
python3 - "${T}" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '全部跳過"; exit 2; }'
assert s.count(old) == 1, "01 的收尾不是預期的樣子"
p.write_text(s.replace(old, '全部跳過"; exit 0; }'))
PY
if bash check-convention.sh > /dev/null 2>&1; then
  bad "01 跳過整支還回 0，公約那道檢查竟然沒抓到"
else
  ok "改回去就沒過，還原之後通過"
fi
restore7
trap - EXIT INT TERM
bash check-convention.sh > /dev/null 2>&1 || bad "還原之後那道檢查還是沒過，01 沒有回到原樣"

printf '\n════════ 通過 %s／沒過 %s／沒有結論 %s ════════\n' "${PASS}" "${FAIL}" "${SKIP}"

# 離開碼的意思，全 repo 一致（Day 22 定的）：
#   0 全部通過，而且真的驗過了
#   1 有沒過的，這是你要它擋你的那種
#   2 環境不到位或有節被跳過，沒有結論。跳過不是通過
[ "${FAIL}" != 0 ] && exit 1
[ "${SKIP}" != 0 ] && exit 2
exit 0
