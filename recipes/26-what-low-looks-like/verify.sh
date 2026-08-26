#!/usr/bin/env bash
# 這一天的檢查。跑：bash verify.sh
#
# 離開碼照 Day 22 那份公約：0 全部通過、1 有沒過的、2 環境不到位或有節被跳過，沒有結論。
# 順序是先判有沒有沒過的：有就是 1，因為那是有結論的（recipes/24 的收尾同一套寫法）。
#
# 這一天的產出是一份「它能做到什麼」的聲明，而聲明最容易壞的方式是跟資料分岔。
# 所以下面沒有一條在讀 POSITIONING.md 的形容詞，全部是拿 first-look/ 那份存檔
# 重新算一次，再問聲明對不對得上。
set -u
cd "$(dirname "$0")"
# LC_ALL=C 不能省。macOS 內建的 awk（20200816）在 UTF-8 locale 下，任何含非 ASCII
# 的字串比較都會回真：底下拿 $5=="指到" 數命中數，不設這一行會數到全部九列，
# 而那個錯誤的方向剛好是「聲明看起來對得上」。2026-08-25 實測。
export LC_ALL=C
G=0; B=0; S=0
case_() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  通過\t%s\n' "$1"; G=$((G+1)); }
bad()  { printf '  沒過\t%s\n' "$1"; B=$((B+1)); }
skip() { printf '  沒有結論\t%s\n' "$1"; S=$((S+1)); }

MODEL="${ANTARES_MLX:-./antares-1b-mlx}"
PG=../../playground
[ -d "$PG" ] || { echo "找不到 $PG，沒有結論" >&2; exit 2; }
[ -r first-look/run.json ] || { echo "沒有 first-look/run.json，先跑 first-look.py，沒有結論" >&2; exit 2; }

rows() { grep -v '^#' verdict.tsv | tail -n +2 | grep .; }

case_ "1 存檔收的檔案，跟 playground 現在有的一樣"
HAVE=$(cd "$PG" && find . -name '*.js' -not -path './test/*' | sed 's|^\./||' | sort | tr '\n' ' ')
GOT=$(python3 -c "
import json;print(' '.join(sorted(r['file'] for r in json.load(open('first-look/run.json'))['results']))+' ')")
if [ "$HAVE" = "$GOT" ]; then
  ok "七個檔對得上：${GOT}"
else
  bad "存檔收的是 ${GOT}／現在有的是 ${HAVE}"
fi

case_ "2 每個檔都留了原始輸出，而且不是空的"
MISS=""
while IFS=$'\t' read -r f raw; do
  [ -s "first-look/$raw" ] || MISS="${MISS} ${f}"
done < <(python3 -c "
import json
for r in json.load(open('first-look/run.json'))['results']: print(r['file'], r['raw'], sep='\t')")
[ -z "$MISS" ] && ok "七份原始輸出都在" || bad "這幾份缺或空：${MISS}"

case_ "3 各檔耗時加起來等於存檔記的總秒數"
python3 - <<'PY' && ok "加得起來" || bad "總秒數跟逐檔對不上"
import json, sys
d = json.load(open('first-look/run.json'))
s = round(sum(r['seconds'] for r in d['results']), 1)
sys.exit(0 if abs(s - d['total_seconds']) < 0.05 else 1)
PY

case_ "4 verdict.tsv 每一列的依據，逐字出自那個檔的存檔"
# 這一條是這份核對唯一的支撐。憑印象寫「它好像有講到」在這裡會沒過，
# 而那正是核對最容易出錯的地方：讀過一次輸出，之後就靠記憶回答。
NB=""
while IFS=$'\t' read -r _k file _item _cwe _v _mc _ml _al quote _rev; do
  [ -n "$file" ] || continue
  raw="first-look/$(printf '%s' "$file" | tr '/' '_').txt"
  [ -r "$raw" ] || { NB="${NB} ${file}(沒有存檔)"; continue; }
  grep -Fq -- "$quote" "$raw" || NB="${NB} ${file}(${quote:0:30}…)"
done < <(rows)
[ -z "$NB" ] && ok "$(rows | grep -c .) 列的依據全部在對應的存檔裡找得到" \
             || bad "這幾列的依據在存檔裡找不到：${NB}"

case_ "5 存檔裡每一條合格候選，核對表都記到了"
# 核對表本來是單向的：拿已知問題去找候選。反方向沒人守的話，模型多吐的候選
# 會靜靜消失，而誤報數、行號命中率、編號命中率三個聲明會同時被低估。
#
# 比的是集合不是計數。只比總數的話，刪掉那條誤報、再補一列重記已經記過的候選，
# 兩邊照樣一樣多，而誤報數會從 1 變成 0（實測）。
D5=$(diff <(cat first-look/*.txt | grep '^CWE-[0-9]* | line ' | sort) \
          <(rows | awk -F'\t' '$6 != "-" {print $9}' | sort) 2>&1)
[ -z "$D5" ] && ok "存檔的候選跟核對表記的，逐條對得起來（$(cat first-look/*.txt | grep -c '^CWE-[0-9]* | line ') 條）" \
             || bad "存檔與核對表的候選對不起來：$(printf '%s' "$D5" | tr '\n' ' ')"

case_ "6 判定「沒指到」的那幾列，反向驗一次"
# 拿另一個問題的候選當依據，證不出「它沒講到這件事」。這裡問的是
# 整份存檔的候選行裡，那個問題的核心字眼有沒有出現過。
NR_=""
while IFS=$'\t' read -r _k _f _i _c v _mc _ml _al _q rev; do
  [ "$v" = 沒指到 ] || continue
  [ -n "$rev" ] && [ "$rev" != - ] || { NR_="${NR_} (有列沒填反向關鍵字)"; continue; }
  # 關鍵字是填表的人自己選的，不加約束的話填一個必不出現的字就永遠通過。
  # 它至少要真的是那個檔裡的東西：user_id 在 orders.js:18、err.message 在 files.js:14。
  grep -qF -- "$rev" "$PG/$_f" \
    || { NR_="${NR_} ${rev}(不在 ${_f} 的原始碼裡)"; continue; }
  cat first-look/*.txt | grep '^CWE-[0-9]* | line ' | grep -qF -- "$rev" \
    && NR_="${NR_} ${rev}"
done < <(rows)
[ -z "$NR_" ] && ok "那幾列的關鍵字，候選行裡一次都沒出現" \
              || bad "這幾個關鍵字其實出現在候選行裡：${NR_}"

case_ "7 POSITIONING.md 的四個數字，跟核對表算出來的一樣"
HIT=$(rows | awk -F'\t' '$1=="已知" && $5=="指到"' | grep -c .)
CWEOK=$(rows | awk -F'\t' '$5=="指到" && $4==$6' | grep -c .)
FP=$(rows | awk -F'\t' '$5=="誤報"' | grep -c .)
SEC=$(python3 -c "import json;print(json.load(open('first-look/run.json'))['total_seconds'])")
PEAK=$(python3 -c "
import json;d=json.load(open('first-look/run.json'))
print(f\"{max(float(r['peak'].split()[0]) for r in d['results']):.2f}\")")
N=0
grep -qF "指出三個" POSITIONING.md && [ "$HIT" = 3 ] || { bad "命中數：核對表 ${HIT}"; N=1; }
grep -qF "CWE 編號只有一條對" POSITIONING.md && [ "$CWEOK" = 1 ] || { bad "編號命中數：核對表 ${CWEOK}"; N=1; }
grep -qF "${SEC} 秒" POSITIONING.md || { bad "聲明沒寫 ${SEC} 秒"; N=1; }
grep -qF "${PEAK} GB" POSITIONING.md || { bad "聲明沒寫峰值 ${PEAK} GB"; N=1; }
# FP 以前只印在訊息裡沒有被斷言過。「乾淨檔案上會報東西」那一條沒人守，
# 而它剛好是刪掉一列就會從 1 掉到 0 的那個數。
grep -qF "乾淨檔案上會報東西" POSITIONING.md && [ "$FP" = 1 ] || { bad "誤報數：核對表 ${FP}"; N=1; }
[ "$N" = 0 ] && ok "指到 ${HIT}、編號對 ${CWEOK}、誤報 ${FP}、${SEC} 秒、峰值 ${PEAK} GB"

case_ "8 聲明說「五條有得對照的候選，只有一條行號對」，逐條驗一次"
RIGHT=""; TOTAL=0
while IFS=$'\t' read -r _k file _i _c _v _mc ml al _q _rev; do
  # 乾淨檔上那條 CWE-420 也有行號，但沒有真洞就沒有位置可對，所以不算分母。
  # 存檔裡合格候選一共六條，這裡數到的是五條。
  [ -n "$ml" ] && [ "$ml" != - ] && [ "$al" != - ] || continue
  TOTAL=$((TOTAL+1))
  printf '%s' ",$al," | grep -q ",$ml," && RIGHT="${RIGHT} ${file}:${ml}"
done < <(rows)
if [ "$TOTAL" = 5 ] && [ "$RIGHT" = " server/orders.js:6" ]; then
  ok "五條裡對的只有 server/orders.js:6，而那條把機制講錯了"
else
  bad "${TOTAL} 條裡對的是：${RIGHT}，聲明那句要跟著改"
fi

case_ "9 POSITIONING.md 四個小節都在"
SEC_MISS=""
for h in "## 一句話" "## 它做得到" "## 它做不到" "## 所以我怎麼用它"; do
  grep -qF "$h" POSITIONING.md || SEC_MISS="${SEC_MISS} ${h}"
done
[ -z "$SEC_MISS" ] && ok "四節都在" || bad "缺這幾節：${SEC_MISS}"

case_ "10 重跑一輪，跟存檔逐字相同"
# 跳過不是通過。這一條沒跑成，整支的離開碼是 2，不是 0。
if [ "${SKIP_RERUN:-}" = 1 ]; then
  skip "SKIP_RERUN=1（mutations.sh 拿它跳過這一條，前九條的突變一條都碰不到它）"
elif [ ! -r "$MODEL/config.json" ]; then
  skip "找不到模型（$MODEL），設 ANTARES_MLX 指過去"
else
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  python3 first-look.py "$MODEL" "$T" >/dev/null 2>&1; RC=$?
  if [ "$RC" = 2 ]; then
    skip "first-look.py 回 2（環境不到位，多半是 mlx-lm 沒裝）"
  elif [ "$RC" != 0 ]; then
    bad "重跑回 ${RC}"
  else
    D=""
    for f in first-look/*.txt; do
      cmp -s "$f" "$T/$(basename "$f")" || D="${D} $(basename "$f")"
    done
    [ -z "$D" ] && ok "七份逐字相同（--temp 0，同一份權重）" || bad "這幾份重跑出來不一樣：${D}"
  fi
fi

printf '\n通過 %s、沒過 %s、沒有結論 %s\n' "$G" "$B" "$S"
[ "$B" = 0 ] || exit 1
[ "$S" = 0 ] || exit 2
exit 0
