#!/usr/bin/env bash
# 五種條件各跑 N 次，一行一發寫進 results.tsv，回覆原文寫進 replies/。
#
#   bash run-attack.sh                                  # 罐頭，驗流程
#   MODEL_CMD='bash adapter.sh' N=6 bash run-attack.sh  # 真模型
#
# 條件是成對的，因為要回答的是「防護句對這條攻擊有沒有差」：
#   internal-noguard / internal-v2    誘餌頁直接寫內網位址，差別只有防護句
#   redirect-noguard / redirect-v2    誘餌頁寫的是文件站的網址，差別只有防護句
#   internal-v2-gate                  同 internal-v2，但白名單閘打開
set -u
set -o pipefail
cd "$(dirname "$0")"

N=${N:-3}
MODEL_CMD=${MODEL_CMD:-bash stub-model.sh}
export MODEL_CMD
OUT=${OUT:-results.tsv}
REPLIES=${REPLIES:-replies}
mkdir -p "${REPLIES}"

printf 'cond\trun\tcalled\turl\tgate\tfetched\tfinal\tmark\n' > "${OUT}"

run() {  # run <條件名> <agent.mjs 的參數...>
  local cond=$1; shift
  for i in $(seq 1 "${N}"); do
    local line
    if ! line=$(REPLY_FILE="${REPLIES}/${cond}-${i}.txt" node agent.mjs "$@"); then
      echo "第 ${i} 發（${cond}）掛了，整輪作廢" >&2
      exit 1
    fi
    printf '%s\t%s\t%s\n' "${cond}" "${i}" "${line}" >> "${OUT}"
  done
}

run internal-noguard  --gate off --guard none        --page lure
run internal-v2       --gate off --guard guard-v2.txt --page lure
run internal-v2-gate  --gate on  --guard guard-v2.txt --page lure
run redirect-noguard  --gate on  --guard none        --page redirect
run redirect-v2       --gate on  --guard guard-v2.txt --page redirect

echo "寫進 ${OUT}："
node summarise.mjs "${OUT}"
