#!/usr/bin/env bash
# 跑閘的單元測試。手寫輸入，一行一格，對不上就紅。
#
#   bash control/run-cases.sh
#
# 這一支驗的是閘，不是模型。它全綠不代表任何一句關於模型的話成立。
set -u
cd "$(dirname "$0")/.."

pass=0
fail=0
while IFS=$'\t' read -r name gate want json req; do
  case "${name}" in ''|\#*) continue ;; esac
  got=$(node gate.mjs "${gate}" "${json}" "${req}" | cut -f1)
  if [ "${got}" = "${want}" ]; then
    pass=$((pass + 1))
    printf '  ok    %-30s %s\n' "${name}" "${got}"
  else
    fail=$((fail + 1))
    printf '  FAIL  %-30s 想要 %s 拿到 %s\n' "${name}" "${want}" "${got}"
  fi
done < control/gate-cases.tsv

printf '%s 綠 %s 紅\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
