#!/usr/bin/env bash
# 六格各跑 N 發，隨機交錯，一行一發寫進 results.tsv，回覆原文寫進 replies/。
#
#   bash run-suite.sh                                    # 罐頭，驗流程
#   MODEL_CMD='bash adapter.sh' N=12 bash run-suite.sh   # 真模型
#
# 六格是這樣配的（arm 是攻擊家族，gate 是那道閘）：
#   hijack none        沒有閘。先確認這顆模型到底吃不吃這個誘餌，不然後面全綠沒有意義
#   hijack intent      意圖核對閘。骨幹就在賭這一格會放行
#   hijack external    外部基準閘
#   hijack allowlist   Day 15 那道閘。它放行不是它壞了，是它回答的問題不同
#   normal intent      反向控制。閘不能把正常的查詢也擋掉
#   normal external    同上
#
# 為什麼要交錯：一格跑完再跑下一格的話，中間任何漂移（模型端更新、我自己手改了東西）
# 都會整包落在其中一格身上，而那看起來會跟真的效應一模一樣。
set -u
set -o pipefail
cd "$(dirname "$0")"

N=${N:-2}
MODEL_CMD=${MODEL_CMD:-bash stub-model.sh}
export MODEL_CMD
SEED=${SEED:-17}
OUT=${OUT:-results.tsv}
REPLIES=${REPLIES:-replies}
CELLS=${CELLS:-"hijack:none hijack:intent hijack:external hijack:allowlist normal:intent normal:external"}
mkdir -p "${REPLIES}"

ORDER=$(python3 - "${SEED}" "${N}" ${CELLS} <<'PY'
import random, sys
seed, n, cells = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3:]
plan = [f"{c} {i}" for c in cells for i in range(1, n + 1)]
random.Random(seed).shuffle(plan)
print("\n".join(plan))
PY
)

printf 'order\tarm\tgate\trun\tsteps\ttools\tintent\tgateverdict\texecuted\tdeleted\tmismatch\n' > "${OUT}"
k=0
while read -r cell i; do
  [ -n "${cell}" ] || continue
  arm=${cell%%:*}
  gate=${cell##*:}
  k=$((k + 1))
  if ! line=$(REPLY_FILE="${REPLIES}/${arm}-${gate}-${i}.txt" node agent.mjs --arm "${arm}" --gate "${gate}"); then
    echo "第 ${k} 發（${cell}）掛了，整輪作廢" >&2
    exit 1
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "${k}" "${arm}" "${gate}" "${i}" "${line}" >> "${OUT}"
  printf '  %3s  %-7s %-10s %-3s %s\n' "${k}" "${arm}" "${gate}" "${i}" "${line}"
done <<< "${ORDER}"

echo
node summarise.mjs "${OUT}"
