#!/usr/bin/env bash
# 這一天的檢查。跑：bash verify.sh
#
# 離開碼照 Day 22 那份公約：0 全綠、1 有紅、2 環境不到位沒有結論。
#
# 這一天的產出是一份「它能做到什麼」的聲明，而聲明最容易壞的方式是跟資料分岔：
# 存檔重跑一輪之後數字變了，聲明還停在上一輪。所以下面沒有一條在讀 POSITIONING.md
# 的形容詞，全部是拿 first-look/ 那份存檔重新算一次，再問聲明對不對得上。
set -u
cd "$(dirname "$0")"
export LC_ALL=C
G=0; B=0
case_() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  綠\t%s\n' "$1"; G=$((G+1)); }
bad()  { printf '  紅\t%s\n' "$1"; B=$((B+1)); }

MODEL="${ANTARES_MLX:-/Volumes/CyhSSD/Dev/models/antares-1b-mlx}"
PG=../../playground
[ -d "$PG" ] || { echo "找不到 $PG，沒有結論" >&2; exit 2; }
[ -r first-look/run.json ] || { echo "沒有 first-look/run.json，先跑 first-look.py，沒有結論" >&2; exit 2; }

rows() { grep -v '^#' verdict.tsv | tail -n +2 | grep -c .; }
col()  { grep -v '^#' verdict.tsv | tail -n +2 | awk -F'\t' -v c="$1" '{print $c}'; }

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

case_ "4 verdict.tsv 每一列的依據，逐字出自存檔"
# 這一條是這份核對唯一的支撐。憑印象寫「它好像有講到」在這裡會紅，
# 而那正是核對最容易出錯的地方：讀過一次輸出，之後就靠記憶回答。
NB=""
while IFS=$'\t' read -r _k file _item _cwe _v _mc _ml _al quote; do
  [ -n "$file" ] || continue
  raw="first-look/$(printf '%s' "$file" | tr '/' '_').txt"
  [ -r "$raw" ] || { NB="${NB} ${file}(沒有存檔)"; continue; }
  grep -Fq -- "$quote" "$raw" || NB="${NB} ${file}(${quote:0:30}…)"
done < <(grep -v '^#' verdict.tsv | tail -n +2 | grep .)
[ -z "$NB" ] && ok "$(rows) 列的依據全部在存檔裡找得到" || bad "這幾列的依據在存檔裡找不到：${NB}"

case_ "5 已知問題六條、乾淨對照兩檔，一條不多一條不少"
K=$(col 1 | grep -c '^已知$'); C=$(col 1 | grep -c '^乾淨$')
[ "$K" = 6 ] && [ "$C" = 2 ] && ok "已知 6、乾淨 2" || bad "已知 ${K}、乾淨 ${C}"

case_ "6 POSITIONING.md 寫的命中數，跟 verdict.tsv 算出來的一樣"
HIT=$(paste <(col 1) <(col 5) | awk -F'\t' '$1=="已知" && $2=="指到"' | grep -c .)
CN=$(python3 -c "
import re;t=open('POSITIONING.md').read()
m=re.search(r'六個已知問題裡指出(.)個',t);print({'一':1,'二':2,'三':3,'四':4,'五':5,'六':6}.get(m.group(1),-1) if m else -1)")
[ "$HIT" = "$CN" ] && ok "都是 ${HIT} 個" || bad "存檔算出來 ${HIT} 個，聲明寫 ${CN} 個"

case_ "7 聲明說「三條指到的候選，行號一條都沒對」，逐列驗一次"
# 只算判定是「指到」的那幾列。判成別的東西的那條候選也帶行號，而它剛好落在
# server/orders.js 第 6 行，也就是真的有問題的那一行——它指對了位置、講錯了機制。
# 把它算進來，這句聲明會變成假的紅；把它算成命中，那更糟。
WRONG=0; RIGHT=""
while IFS=$'\t' read -r _k file _i _c v _mc ml al _q; do
  [ "$v" = 指到 ] || continue
  [ -n "$ml" ] && [ "$ml" != - ] && [ "$al" != - ] || continue
  if printf '%s' ",$al," | grep -q ",$ml,"; then RIGHT="${RIGHT} ${file}:${ml}"; else WRONG=$((WRONG+1)); fi
done < <(grep -v '^#' verdict.tsv | tail -n +2 | grep .)
[ -z "$RIGHT" ] && ok "${WRONG} 條有行號的候選，沒有一條指對" || bad "這幾條其實指對了：${RIGHT}，聲明要改"

case_ "8 POSITIONING.md 四個小節都在"
S=""
for h in "## 一句話" "## 它做得到" "## 它做不到" "## 所以我怎麼用它"; do
  grep -qF "$h" POSITIONING.md || S="${S} ${h}"
done
[ -z "$S" ] && ok "四節都在" || bad "缺這幾節：${S}"

case_ "9 重跑一輪，跟存檔逐字相同"
if [ "${SKIP_RERUN:-}" = 1 ]; then
  # mutations.sh 拿它跳過這一條：那一輪要 33 秒，而前八條的突變一條都碰不到它。
  printf '  跳過\tSKIP_RERUN=1\n'
elif [ -r "$MODEL/config.json" ]; then
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  if python3 first-look.py "$MODEL" "$T" >/dev/null 2>&1; then
    D=""
    for f in first-look/*.txt; do
      cmp -s "$f" "$T/$(basename "$f")" || D="${D} $(basename "$f")"
    done
    [ -z "$D" ] && ok "七份逐字相同（--temp 0，同一份權重）" || bad "這幾份重跑出來不一樣：${D}"
  else
    bad "重跑跑不動"
  fi
else
  printf '  沒有結論\t找不到模型（%s），第 9 條跳過。設 ANTARES_MLX 指過去\n' "$MODEL"
  printf '\n綠 %s、紅 %s，第 9 條沒有結論\n' "$G" "$B"
  exit 2
fi

printf '\n綠 %s、紅 %s\n' "$G" "$B"
[ "$B" = 0 ] || exit 1
