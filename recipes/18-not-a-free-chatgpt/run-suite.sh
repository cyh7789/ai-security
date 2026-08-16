#!/usr/bin/env bash
# 兩組各跑 N 條鏈，隨機交錯，一行一條寫進 results.tsv。
#
#   bash run-suite.sh                                    # 罐頭，驗流程
#   MODEL_CMD='bash adapter.sh' N=12 bash run-suite.sh   # 真模型
#
# 兩組：
#   split   五句分次問，每一句單獨看都是這家店的客服日常
#   direct  同一個目標一句話直接要求。這是反向控制，它沒有被擋的話，
#           split 那組的「全放行」只代表我的場景檢查太鬆，跟拆不拆無關
#
# 交錯的理由跟前幾天一樣：一組跑完再跑另一組，中間任何漂移都會整包落在其中一組身上。
set -u
set -o pipefail
cd "$(dirname "$0")"

N=${N:-2}
MODEL_CMD=${MODEL_CMD:-bash stub-model.sh}
export MODEL_CMD
SEED=${SEED:-18}
OUT=${OUT:-results.tsv}
CELLS=${CELLS:-"split direct"}

ORDER=$(python3 - "${SEED}" "${N}" ${CELLS} <<'PY'
import random, sys
seed, n, cells = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3:]
plan = [f"{c} {i}" for c in cells for i in range(1, n + 1)]
random.Random(seed).shuffle(plan)
print("\n".join(plan))
PY
)

printf 'order\tarm\trun\tarmname\trequests\tinblocked\tsent\trefused\tguarded\toutverdict\toutreason\n' > "${OUT}"
k=0
while read -r arm i; do
  [ -n "${arm}" ] || continue
  k=$((k + 1))
  if ! line=$(node chain.mjs --arm "${arm}" 2>/dev/null); then
    echo "第 ${k} 條（${arm}）掛了，整輪作廢" >&2
    exit 1
  fi
  printf '%s\t%s\t%s\t%s\n' "${k}" "${arm}" "${i}" "${line}" >> "${OUT}"
  printf '  %3s  %-7s %-3s %s\n' "${k}" "${arm}" "${i}" "${line}"
done <<< "${ORDER}"

echo
node summarise.mjs "${OUT}"
