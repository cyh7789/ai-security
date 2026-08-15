#!/usr/bin/env bash
# 兩組需求各生 N 份 CRUD，隨機交錯跑，逐份判決寫成一列。
#
#   bash run-gen.sh                                    # 罐頭，驗流程
#   MODEL_CMD='bash adapter.sh' N=12 bash run-gen.sh   # 真模型
#   ARMS='bare owned vague' N=12 bash run-gen.sh       # 帶上描述性的第三組
#
# 為什麼要交錯：兩組如果一組跑完再跑另一組，中間任何漂移（模型端更新、
# 我自己手改了東西）都會整包落在其中一組身上，而那看起來會跟真的效應一模一樣。
# 交錯之後漂移平均分到兩組，而順序本身記進 order 欄，事後查得到。
set -u
set -o pipefail
cd "$(dirname "$0")"

N=${N:-2}
ARMS=${ARMS:-"bare owned"}
MODEL_CMD=${MODEL_CMD:-bash stub-model.sh}
SEED=${SEED:-16}
OUT=${OUT:-results.tsv}
GEN=${GEN:-gen}
mkdir -p "${GEN}"

# 洗牌前先把「哪一發是誰」列出來，種子寫死，重跑順序一樣。
ORDER=$(python3 - "${SEED}" "${N}" ${ARMS} <<'PY'
import random, sys
seed, n, arms = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3:]
plan = [f"{a} {i}" for a in arms for i in range(1, n + 1)]
random.Random(seed).shuffle(plan)
print("\n".join(plan))
PY
)

printf 'order\tarm\trun\tverdict\tcode\tflagged\twhy\n' > "${OUT}"
k=0
while read -r arm i; do
  [ -n "${arm}" ] || continue
  k=$((k + 1))
  f="${GEN}/${arm}-${i}.mjs"
  raw="${GEN}/${arm}-${i}.raw.txt"
  if ! ${MODEL_CMD} < "prompts/${arm}.txt" > "${raw}"; then
    echo "第 ${k} 發（${arm}-${i}）模型那邊掛了，整輪作廢" >&2
    exit 1
  fi
  # 圍欄裡那段才是程式碼。沒有圍欄就整份當程式碼，讓它自己在 judge 那裡壞掉，
  # 不要在這裡幫它猜，猜錯會把「模型沒寫程式」記成「模型寫錯了」。
  python3 - "${raw}" "$f" <<'PY'
import re, sys
raw = open(sys.argv[1], encoding="utf8", errors="replace").read()
blocks = re.findall(r"```(?:[a-zA-Z]*)\n(.*?)```", raw, re.S)
open(sys.argv[2], "w", encoding="utf8").write(blocks[-1] if blocks else raw)
PY
  # 組名決定判準要問哪一種資源。bare／owned／vague 是同一題的三種問法。
  case "${arm}" in
    nested|list) kind="${arm}" ;;
    *)           kind="direct" ;;
  esac
  line=$(node judge.mjs --kind "${kind}" "$f" | cut -f2-)
  printf '%s\t%s\t%s\t%s\n' "${k}" "${arm}" "${i}" "${line}" >> "${OUT}"
  printf '  %2s  %-6s %-2s  %s\n' "${k}" "${arm}" "${i}" "${line}"
done <<< "${ORDER}"

echo
node summarise.mjs "${OUT}"
