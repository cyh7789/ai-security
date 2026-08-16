#!/usr/bin/env bash
# 跑四道閘的單元測試。手寫輸入，一行一格，對不上就紅。
#
#   bash control/run-cases.sh
#
# 這一支驗的是閘，不是模型。它全綠不代表任何一句關於模型的話成立。
set -u
cd "$(dirname "$0")/.."

LONG=$(node -e 'process.stdout.write("字".repeat(2001))')
ASTRAL=$(node -e 'process.stdout.write("\u{1F600}".repeat(1200))')
pass=0
fail=0

check() { # name want got
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); printf '  ok    %-28s %s\n' "$1" "$3"
  else
    fail=$((fail + 1)); printf '  FAIL  %-28s 想要 %s 拿到 %s\n' "$1" "$2" "$3"
  fi
}

while IFS=$'\t' read -r name gate want input; do
  case "${name}" in ''|\#*) continue ;; esac
  [ "${input}" = "{{LONG}}" ] && input="${LONG}"
  [ "${input}" = "{{ASTRAL}}" ] && input="${ASTRAL}"
  if [ "${gate}" = "classify" ]; then
    got=$(printf '%s' "${input}" | node classify.mjs | cut -f1)
  else
    got=$(node gates.mjs "${gate}" "${input}" | cut -f1)
  fi
  check "${name}" "${want}" "${got}"
done < control/gate-cases.tsv

# rate 的 deny 那一向要在同一個行程裡打滿才看得到，CLI 一次一個行程，視窗永遠是空的。
got=$(node -e '
  import("./gates.mjs").then(({ rateGate, LIMITS }) => {
    const cap = Math.min(LIMITS.perMinute, 200); // 上界取自被測的值，就測不出它被改大
    let last;
    for (let i = 0; i <= cap; i++) last = rateGate("u-burst");
    process.stdout.write(last.allow ? "allow" : "deny");
  });
')
check "rate-over-limit" "deny" "${got}"

printf '%s 綠 %s 紅\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
