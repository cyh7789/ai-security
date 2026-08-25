#!/usr/bin/env bash
# 這一天的檢查。跑：bash verify.sh
#
# 離開碼照 Day 22 那份公約：0 全綠、1 有紅、2 環境不到位或有節被跳過，沒有結論。
# 順序是先判紅：有紅就是 1，因為那是有結論的。
#
# 這一天的產出是一份候選清單的核對表，而核對表最容易壞的方式跟 Day 26 一樣：
# 跟存檔分岔。所以下面沒有一條在讀 FINDINGS.md 的形容詞，全部是拿 hunt/
# 那份存檔重新算一次，再問聲明對不對得上。
set -u
cd "$(dirname "$0")"
# LC_ALL=C 不能省。macOS 內建的 awk（20200816）在 UTF-8 locale 下，任何含非 ASCII
# 的字串比較都會回真，而底下整份核對都靠 $5=="指到" 這類比較在數。2026-08-25 實測。
export LC_ALL=C
G=0; B=0; S=0
case_() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  綠\t%s\n' "$1"; G=$((G+1)); }
bad()  { printf '  紅\t%s\n' "$1"; B=$((B+1)); }
skip() { printf '  沒有結論\t%s\n' "$1"; S=$((S+1)); }

MODEL="${ANTARES_MLX:-./antares-1b-mlx}"
PG=../../playground
[ -d "$PG" ] || { echo "找不到 $PG，沒有結論" >&2; exit 2; }
[ -r hunt/run.json ] || { echo "沒有 hunt/run.json，先跑 hunt.py，沒有結論" >&2; exit 2; }

cwes() { grep -v '^#' cwes.tsv | grep .; }
rows() { grep -v '^#' verdict.tsv | tail -n +2 | grep .; }

case_ "1 cwes.tsv 的形狀：十三個類別，六個在、七個不在"
N1=$(cwes | grep -c .)
IN=$(cwes | awk -F'\t' '$2 != "無"' | grep -c .)
OUT=$(cwes | awk -F'\t' '$2 == "無"' | grep -c .)
COLS=$(cwes | awk -F'\t' 'NF != 4' | grep -c .)
if [ "$N1" = 13 ] && [ "$IN" = 6 ] && [ "$OUT" = 7 ] && [ "$COLS" = 0 ]; then
  ok "13 個類別、6 個在、7 個不在，每列四欄"
else
  bad "13/6/7 對不上：共 ${N1}、在 ${IN}、不在 ${OUT}、欄數不對 ${COLS} 列"
fi

case_ "2 每個類別都留了原始輸出，而且秒數加得起來"
MISS=""
for cid in $(cwes | cut -f1); do
  [ -s "hunt/${cid}.txt" ] || MISS="${MISS} ${cid}"
done
if [ -n "$MISS" ]; then
  bad "這幾份存檔缺或空：${MISS}"
else
  python3 - <<'PY' && ok "13 份原始輸出都在，總秒數跟逐條對得起來" || bad "總秒數跟逐條對不上"
import json, sys
d = json.load(open('hunt/run.json'))
s = round(sum(r['seconds'] for r in d['results']), 1)
sys.exit(0 if abs(s - d['total_seconds']) < 0.05 else 1)
PY
fi

case_ "3 verdict.tsv 每一列的依據，逐字出自那個編號的存檔"
# 這一條是整份核對唯一的支撐，理由跟 Day 26 第 4 條一樣：讀過一次輸出，
# 一小時後回頭填表就變成「它好像有講到」。
NB=""
while IFS=$'\t' read -r cid _e _ans _got _v quote _note; do
  [ -n "$cid" ] || continue
  raw="hunt/${cid}.txt"
  [ -r "$raw" ] || { NB="${NB} ${cid}(沒有存檔)"; continue; }
  grep -Fq -- "$quote" "$raw" || NB="${NB} ${cid}(${quote:0:26}…)"
done < <(rows)
[ -z "$NB" ] && ok "$(rows | grep -c .) 列的依據全部在對應的存檔裡找得到" \
             || bad "這幾列的依據在存檔裡找不到：${NB}"

case_ "4 cwes.tsv 的編號跟核對表的編號，兩邊互相都不缺"
# 比集合不比計數。只比總數的話，漏記一條「亂指」再補一條重複的「指到」，
# 兩邊照樣一樣多，而成績會往「它比較好」的方向偏。
D4=$(diff <(cwes | cut -f1 | sort) <(rows | cut -f1 | sort) 2>&1)
[ -z "$D4" ] && ok "13 個編號兩邊一一對得起來" \
             || bad "兩邊對不起來：$(printf '%s' "$D4" | tr '\n' ' ')"

case_ "5 判定跟「這類在不在」相容"
# 「在」的那六列不可能出現「說沒有」或「亂指」，反過來也一樣。
# 這一條擋的是填表時把兩套詞彙混著用，那會讓下一條算出來的成績沒有意義。
BADV=""
while IFS=$'\t' read -r cid ex _ans _got v _q _n; do
  [ -n "$cid" ] || continue
  case "$ex/$v" in
    在/指到|在/指錯|在/沒交答案|不在/說沒有|不在/亂指) ;;
    *) BADV="${BADV} ${cid}(${ex}/${v})" ;;
  esac
done < <(rows)
[ -z "$BADV" ] && ok "十三列的判定都落在該落的那一組" || bad "這幾列的判定跟存在與否兜不起來：${BADV}"

case_ "6 兩個成績，跟核對表算出來的一樣"
HIT=$(rows | awk -F'\t' '$2=="在" && $5=="指到"' | grep -c .)
SAYNONE=$(rows | awk -F'\t' '$2=="不在" && $5=="說沒有"' | grep -c .)
MADEUP=$(rows | awk -F'\t' '$2=="不在" && $5=="亂指"' | grep -c .)
N=0
[ "$HIT" = 4 ] || { bad "埋了六類指到幾類：核對表 ${HIT}"; N=1; }
[ "$SAYNONE" = 1 ] || { bad "不存在的七類說了幾次沒有：核對表 ${SAYNONE}"; N=1; }
[ "$MADEUP" = 6 ] || { bad "不存在的七類亂指幾次：核對表 ${MADEUP}"; N=1; }
grep -qF "六類裡指到四類" FINDINGS.md || { bad "FINDINGS.md 沒寫「六類裡指到四類」"; N=1; }
grep -qF "七類裡亂指六類" FINDINGS.md || { bad "FINDINGS.md 沒寫「七類裡亂指六類」"; N=1; }
[ "$N" = 0 ] && ok "指到 ${HIT}/6、說沒有 ${SAYNONE}/7、亂指 ${MADEUP}/7"

case_ "7 「指到」那幾列真的指對，「亂指」那幾列沒有答案可指"
# 沒有這一條，第 6 條數的只是那一欄填了什麼字。
W=""
while IFS=$'\t' read -r cid _e ans got v _q _n; do
  case "$v" in
    指到) [ "$ans" = "$got" ] || W="${W} ${cid}(答案${ans}／它說${got})" ;;
    指錯) [ "$ans" = "$got" ] && W="${W} ${cid}(判指錯卻跟答案一樣)" ;;
    亂指|說沒有) [ "$ans" = "-" ] || W="${W} ${cid}(這類不在，答案欄卻是${ans})" ;;
  esac
done < <(rows)
[ -z "$W" ] && ok "四條指到的檔案跟答案逐字相同，七條不存在的答案欄都是 -" \
            || bad "這幾列兜不起來：${W}"

case_ "8 改名對照組：換掉檔名，它指的還是同一個底層檔案"
# 少了這一組，「它挑對了」有可能只是它認得 tools.js 這個名字。
if [ ! -r hunt-renamed/run.json ]; then
  skip "沒有 hunt-renamed/（跑 hunt.py <模型> --rename）"
else
  python3 - <<'PY' && ok "78、22、79 三條改名之後指的還是 tools.js、files.js、render.js" \
                   || bad "改名之後對不回同一個檔"
import json, re, sys
d = json.load(open('hunt-renamed/run.json'))
alias = d['alias']
expect = {'CWE-78': 'server/tools.js', 'CWE-22': 'server/files.js', 'CWE-79': 'src/render.js'}
bad = []
for cid, want in expect.items():
    t = open(f'hunt-renamed/{cid}.txt').read()
    hits = {alias[m] for m in alias if re.search(r'(?<![\w/])' + re.escape(m) + r'\b', t)}
    if hits != {want}:
        bad.append(f'{cid}: {sorted(hits)} != [{want}]')
if bad:
    print('  ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PY
fi

case_ "9 模型指出來的那個檔，真的打得進去"
# 候選清單到這裡才變成發現。這一步模型做不到，它只會說「可能」。
bash confirm.sh > /tmp/d27-confirm.$$ 2>&1; RC=$?
case "$RC" in
  0) ok "$(grep '^綠' /tmp/d27-confirm.$$ | sed 's/^綠：//')" ;;
  2) skip "confirm.sh 回 2（環境不到位，多半是沒有 node）" ;;
  *) bad "confirm.sh 回 ${RC}：$(grep '^紅' /tmp/d27-confirm.$$ | tr '\n' ' ')" ;;
esac
rm -f /tmp/d27-confirm.$$

case_ "10 重跑一輪，跟存檔逐字相同"
# 跳過不是通過。這一條沒跑成，整支的離開碼是 2，不是 0。
if [ "${SKIP_RERUN:-}" = 1 ]; then
  skip "SKIP_RERUN=1（mutations.sh 拿它跳過這一條，前九條的突變一條都碰不到它）"
elif [ ! -r "$MODEL/config.json" ]; then
  skip "找不到模型（$MODEL），設 ANTARES_MLX 指過去"
else
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  python3 hunt.py "$MODEL" "$T" >/dev/null 2>&1; RC=$?
  if [ "$RC" = 2 ]; then
    skip "hunt.py 回 2（環境不到位，多半是 mlx-lm 沒裝）"
  elif [ "$RC" != 0 ]; then
    bad "重跑回 ${RC}"
  else
    D=""
    for f in hunt/*.txt; do
      cmp -s "$f" "$T/$(basename "$f")" || D="${D} $(basename "$f")"
    done
    [ -z "$D" ] && ok "13 份逐字相同（--temp 0，同一份權重）" || bad "這幾份重跑出來不一樣：${D}"
  fi
fi

case_ "11 README 那張索引表跟資料夾對得上"
if bash ../../check-index.sh >/dev/null 2>&1; then
  ok "索引表沒有少列，也沒有指到不存在的資料夾"
else
  bad "$(bash ../../check-index.sh 2>&1 | tail -3 | tr '\n' ' ')"
fi

printf '\n綠 %s、紅 %s、沒有結論 %s\n' "$G" "$B" "$S"
[ "$B" = 0 ] || exit 1
[ "$S" = 0 ] || exit 2
exit 0
