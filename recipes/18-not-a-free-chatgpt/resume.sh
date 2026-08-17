#!/usr/bin/env bash
# 一輪跑到一半死掉的時候，只補缺的那幾條，不要整輪重來。
#
#   別直接這樣叫。每一輪的 runs/<日期>/relaunch.sh 才是正確入口，
#   它把那一輪的 MODEL_CMD / CLASSIFY_CMD / GUARD_LOG 逐字帶齊。
#   直接叫這一支而漏掉 MODEL_CMD，補回來的那幾條會是另一個模型跑的，
#   而且混在同一個檔裡看不出來，所以下面把它改成必填。
#
# run-suite.sh 一開跑就 `printf 表頭 > OUT`，所以直接重跑等於把已經打過的
# 模型呼叫全部丟掉。這一支讀現有的 results.tsv，算出還缺哪些 (arm, run)，
# 只跑那些，附加在後面。
#
# order 欄會從現有的最大值往下接，所以它不再等於原本那個交錯順序。
# 這件事要寫進該輪的 run-conditions.txt：補跑過的輪次，順序欄不能拿來當隨機化的證據。
set -u
set -o pipefail
cd "$(dirname "$0")"

N=${N:-12}
OUT=${OUT:?要指定 OUT}
CELLS=${CELLS:?要指定 CELLS}
# 必填，不給預設。run-suite.sh 可以有預設是因為它重建整個檔，整輪一致；
# 這一支是附加，預設值會讓罐頭資料混進真模型的檔。
MODEL_CMD=${MODEL_CMD:?要指定 MODEL_CMD（用該輪的 relaunch.sh）}
CLASSIFY_CMD=${CLASSIFY_CMD:?要指定 CLASSIFY_CMD（用該輪的 relaunch.sh）}
export MODEL_CMD CLASSIFY_CMD

[ -f "${OUT}" ] || { echo "${OUT} 不存在，這是全新的一輪，用 run-suite.sh"; exit 2; }

# 表頭要跟 run-suite.sh 現在寫的那一行逐字相同。欄位加過（8/17 加 perflag），
# 舊 schema 的檔附加新列不會報錯，但 summarise 會照表頭取欄，
# 新列的判決欄落在別的位置，那兩列就從三個計數桶裡一起消失，全程零警告。
WANT_HEAD=$(grep -oE "^printf '[^']*'" run-suite.sh | head -1 | sed "s/^printf '//; s/'$//")
HAVE_HEAD=$(head -1 "${OUT}")
if [ "$(printf '%b' "${WANT_HEAD}")" != "${HAVE_HEAD}
" ] && [ "$(printf '%b' "${WANT_HEAD}" | tr -d '\n')" != "${HAVE_HEAD}" ]; then
  echo "表頭跟現在的 run-suite.sh 對不上，附加會讓欄位錯位。" >&2
  echo "  檔案：${HAVE_HEAD}" >&2
  echo "  現在：$(printf '%b' "${WANT_HEAD}" | tr -d '\n')" >&2
  exit 2
fi

MISSING=$(python3 - "${OUT}" "${N}" ${CELLS} <<'PY'
import sys
path, n, cells = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
lines = open(path, encoding="utf8").read().strip().split("\n")
head = lines[0].split("\t")
ia, ir = head.index("arm"), head.index("run")
done = {(c[ia], c[ir]) for c in (l.split("\t") for l in lines[1:]) if len(c) > ir}
for c in cells:
    for i in range(1, n + 1):
        if (c, str(i)) not in done:
            print(f"{c} {i}")
PY
)

if [ -z "${MISSING}" ]; then
  echo "沒有缺的，${OUT} 已經齊了（$(( $(grep -c . "${OUT}") - 1 )) 條）"
  exit 0
fi

k=$(( $(grep -c . "${OUT}") - 1 ))
echo "缺 $(printf '%s\n' "${MISSING}" | grep -c .) 條，從第 $((k + 1)) 條接下去"
while read -r arm i; do
  [ -n "${arm}" ] || continue
  k=$((k + 1))
  if ! line=$(CHAIN_RUN="${i}" node chain.mjs --arm "${arm}" 2>/dev/null); then
    echo "第 ${k} 條（${arm} ${i}）掛了，停在這裡，再跑一次 resume 就好" >&2
    exit 1
  fi
  printf '%s\t%s\t%s\t%s\n' "${k}" "${arm}" "${i}" "${line}" >> "${OUT}"
  printf '  %3s  %-10s %-3s %s\n' "${k}" "${arm}" "${i}" "${line}"
done <<< "${MISSING}"

echo
node summarise.mjs "${OUT}"
