#!/usr/bin/env bash
# 這一份自己的檢查。一發模型都不打。
#
#   bash verify.sh
#   bash verify.sh 4      只跑第 4 條（mutations.sh 用）
#
# 這份 recipe 的產出是一張表跟兩份人填的判準檔。表算得對不對只是其中一半，
# 另一半是那兩份判準檔有沒有偷偷把東西藏起來，底下第 3、5、6、9 條守的是那一半。
#
# 離開碼：0 全部通過、1 有沒過的、2 環境不到位沒有結論。
set -u
export LC_ALL=C
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
STD=standard.tsv
UNC=uncovered.tsv
ONLY="${1:-}"

PASS=0; FAIL=0; SKIP=0
case_() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  通過\t%s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  沒過\t%s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  沒有結論\t%s\n' "$1"; SKIP=$((SKIP+1)); }
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
rows() { grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$' | tail -n +2; }

for f in "$STD" "$UNC" rollup.sh; do
  [ -r "$f" ] || { echo "找不到 $f，沒有結論" >&2; exit 2; }
done

if want 1; then
case_ "1 兩份判準檔的欄數與簽核格式"
M=0
N=$(rows "$STD" | grep -c .)
[ "$N" -ge 1 ] || { bad "standard.tsv 一列都沒有，這張表是空的"; M=1; }
while IFS="$(printf '\t')" read -r g expand src rerun stamp sign why; do
  [ -n "$g" ] || continue
  [ -n "$why" ] || { bad "「$g」那列欄數不對，最後一欄是空的"; M=1; }
  printf '%s' "$sign" | grep -qE '^[0-9]+/[0-9]+/[0-9]+$' \
    || { bad "「$g」的簽核欄不是三個數字：${sign}"; M=1; }
done <<EOF
$(rows "$STD")
EOF
NU=$(rows "$UNC" | grep -c .)
[ "$NU" -ge 1 ] || { bad "uncovered.tsv 一列都沒有。一張只列測過的東西的表，跟一張全部都測過的表長得一樣"; M=1; }
while IFS="$(printf '\t')" read -r item kind src why; do
  [ -n "$item" ] || continue
  [ -n "$why" ] || { bad "「$item」沒有寫為什麼沒進去"; M=1; }
  case "$kind" in 量錯對象|沒人打過) ;; *) bad "「$item」的類是「${kind}」，不在那兩個值裡"; M=1 ;; esac
done <<EOF
$(rows "$UNC")
EOF
[ "$M" = 0 ] && ok "standard.tsv ${N} 組、uncovered.tsv ${NU} 項，欄位都完整"
fi

if want 2; then
case_ "2 rollup.sh 算出來的跟簽核一樣"
OUT=$(bash rollup.sh 2>&1); RC=$?
case "$RC" in
  0) printf '%s\n' "$OUT" | grep -qF '每一組都跟簽核一樣' \
       && ok "$(printf '%s\n' "$OUT" | grep -F '合計')" \
       || bad "rollup.sh 回 0 卻沒印那句結論" ;;
  2) skip "rollup.sh 回 2，有一組跑不動" ;;
  *) bad "rollup.sh 回 ${RC}：$(printf '%s\n' "$OUT" | grep -F '對不上' | head -3)" ;;
esac
fi

if want 3; then
case_ "3 沒測那一欄，只有兩種列進得去"
# 這一條守的是最誘人的那個動作：把一件沒跑過的事簽成過了。
# 反方向也要守，但不能守死：「有指令卻簽成沒測」有一種是合法的，就是那條指令
# 這次跑不動（環境不到位，回 2）。第 28 天那支在託管機器上正是這一種，
# 把它跟「寫了指令沒跑」判成同一件事，等於逼人刪掉還沒跑得起來的指令。
M=0
ROLL=$(bash rollup.sh 2>&1)
while IFS="$(printf '\t')" read -r g expand src rerun stamp sign why; do
  [ -n "$g" ] || continue
  case "$rerun" in
    '（沒有）')
      [ "$sign" = "0/0/1" ] \
        || { bad "「$g」沒有重跑指令，簽核卻是 ${sign}。沒跑過的東西只能算沒測"; M=1; } ;;
    *)
      printf '%s' "$sign" | grep -qE '^0/0/[0-9]+$' || continue
      # 簽成沒測的，這次一定要真的跑不動。rollup 會在那一列後面標「跑不動」。
      printf '%s\n' "$ROLL" | grep -F "$g" | grep -qF '跑不動' \
        || { bad "「$g」有重跑指令（${rerun}）卻簽成沒測，而它這次跑得出結論"; M=1; } ;;
  esac
done <<EOF
$(rows "$STD")
EOF
[ "$M" = 0 ] && ok "沒測那一欄裡只有沒有指令的、跟指令跑不動的"
fi

if want 4; then
case_ "4 重跑指令指到的東西真的在"
M=0
C=0
while IFS="$(printf '\t')" read -r g expand src rerun stamp sign why; do
  [ -n "$g" ] || continue
  [ "$rerun" != '（沒有）' ] || continue
  C=$((C+1))
  # 撈指令裡的那個路徑。指到不存在的檔，這條重跑指令就是一句空話。
  P=$(printf '%s' "$rerun" | grep -oE 'recipes/[0-9a-z./-]+' | head -1)
  [ -n "$P" ] || { bad "「$g」的重跑指令裡沒有 recipes/ 路徑：${rerun}"; M=1; continue; }
  [ -e "$ROOT/$P" ] || { bad "「$g」的重跑指令指到不存在的 ${P}"; M=1; }
done <<EOF
$(rows "$STD")
EOF
[ "$C" -ge 1 ] || { bad "一條重跑指令都沒有，這張表沒有東西撐著"; M=1; }
[ "$M" = 0 ] && ok "${C} 條重跑指令指到的檔都在"
fi

if want 5; then
case_ "5 被掃描過卻沒人打過的那幾支，數字是數出來的"
STAMP=$ROOT/recipes/28-what-was-it-run-with/stamp.json
if [ ! -r "$STAMP" ]; then
  skip "找不到成分表，掃描過哪幾支檔比不了"
elif ! python3 -c "pass" >/dev/null 2>&1; then
  skip "沒有 python3，數不了"
else
  # 「掃描過」的正本是成分表裡那份語料清單，不是我用 find 掃出來的目錄。
  # 用 find 的話 test/setup.js 會被算進去，而第 26、27 天根本沒餵它。
  FILES=$(python3 -c "
import json,sys
print('\n'.join(json.load(open('$STAMP'))['corpus']['檔']))")
  TOTAL=$(printf '%s\n' "$FILES" | grep -c .)
  HIT=0; MISS=0
  for f in $FILES; do
    b=$(basename "$f")
    # 一支檔算被打過，條件是 standard.tsv 某一組的重跑指令跑到的程式裡提到它。
    if grep -rqF "$b" $(rows "$STD" | cut -f4 | grep -oE 'recipes/[0-9a-z./-]+\.(mjs|sh)' | sed "s|^|$ROOT/|") 2>/dev/null; then
      HIT=$((HIT+1))
    else
      MISS=$((MISS+1))
    fi
  done
  CN=$(python3 -c "
n=int('$MISS'); cn=['零','一','二','三','四','五','六','七','八','九','十']
print(cn[n] if n<=10 else str(n))")
  TCN=$(python3 -c "
n=int('$TOTAL'); cn=['零','一','二','三','四','五','六','七','八','九','十']
print(cn[n] if n<=10 else str(n))")
  M=0
  [ "$MISS" -ge 1 ] || { bad "算出來每一支都被打過了，那 uncovered.tsv 那一列就該刪掉"; M=1; }
  grep -qF "那七支 .js" "$UNC" || { bad "uncovered.tsv 沒寫語料是七支"; M=1; }
  [ "$TOTAL" = 7 ] || { bad "成分表的語料現在是 ${TOTAL} 支，uncovered.tsv 還寫七支"; M=1; }
  grep -qF "其餘${CN}支" "$UNC" \
    || { bad "uncovered.tsv 寫的數字跟算出來的對不上，算出來是${CN}支沒被打過"; M=1; }
  [ "$M" = 0 ] && ok "語料${TCN}支，被打到的 ${HIT} 支，沒人打過的${CN}支"
fi
fi

if want 6; then
case_ "6 每一支 recipe 都有分級，重跑入口接得回 CI"
LV=$ROOT/recipes/22-when-should-it-stop-you/levels.tsv
if [ ! -r "$LV" ]; then
  skip "找不到 levels.tsv"
else
  M=0
  for d in "$ROOT"/recipes/*/; do
    n=$(basename "$d")
    grep -qE "^${n}	" "$LV" || { bad "${n} 沒有分級，它不在 CI 的任何一個矩陣裡"; M=1; }
  done
  [ "$M" = 0 ] && ok "$(ls -d "$ROOT"/recipes/*/ | wc -l | tr -d ' ') 支都在 levels.tsv 上"
fi
fi

if want 7; then
case_ "7 跑完之後工作目錄要是乾淨的"
if ! (cd "$ROOT" && git rev-parse --git-dir >/dev/null 2>&1); then
  skip "不是 git 倉庫，比不了"
else
  # 比的是 rollup.sh 跑之前跟跑之後的差，不是「工作目錄有沒有未提交的東西」。
  # 後者在寫這份 recipe 的當下永遠成立，一條每次都會叫的檢查等於沒有檢查。
  # 狀態要連內容一起看。只比 git status 的話，一支「每跑一次就往某個檔加一個字」的
  # 腳本會在第 2 節先把那個檔弄成已修改，這裡前後拿到同一行 M，看起來就沒事。
  snap() { (cd "$ROOT" && git status --porcelain -- recipes playground 2>/dev/null
            git -C "$ROOT" diff -- recipes playground 2>/dev/null | shasum -a 256); }
  B=$(snap)
  bash rollup.sh >/dev/null 2>&1
  A=$(snap)
  [ "$B" = "$A" ] && ok "rollup.sh 重跑了三組來源，前後的工作目錄狀態一樣" \
    || bad "rollup.sh 改到了東西：$(diff <(printf '%s' "$B") <(printf '%s' "$A") | head -3 | tr '\n' ' ')"
fi
fi

if want 8; then
case_ "8 README 的索引跟 recipes/ 對得上"
OUT=$(cd "$ROOT" && bash check-index.sh 2>&1) && ok "$OUT" || bad "$OUT"
fi

if want 9; then
case_ "9 每一列都答得出「這個結果是拿什麼跑出來的」"
# 第 28 天問的那句要落到每一列上。這一欄只有兩個值，而「不適用」要說得出理由：
# 那一組的判準不看模型說了什麼，換一份權重不會改變結果。
M=0
NA=0; NEED=0
while IFS="$(printf '\t')" read -r g expand src rerun stamp sign why; do
  [ -n "$g" ] || continue
  case "$stamp" in
    不適用)
      NA=$((NA+1))
      # 「不適用」不是宣告就算數。那條重跑指令跑到的腳本如果認得某個打真模型的
      # 開關，這一列的結果就可能依賴某一份模型，而它沒有成分表。
      P=$(printf '%s' "$rerun" | grep -oE 'recipes/[0-9a-z./-]+' | head -1)
      [ -n "$P" ] || continue
      D=$ROOT/$P; [ -d "$D" ] || D=$(dirname "$ROOT/$P")
      if grep -rqE 'MODEL_CMD|ANTARES_MLX' "$D" 2>/dev/null && [ -n "${MODEL_CMD:-}${ANTARES_MLX:-}" ]; then
        bad "「$g」標不適用，但它跑的東西吃 MODEL_CMD／ANTARES_MLX，而環境裡設了。這一列現在依賴某一份模型，卻沒有成分表"
        M=1
      fi ;;
    需要)
      NEED=$((NEED+1))
      # 「需要」而拿不出對得上的成分表，只能算沒測。這張表現在沒有一列拿得出來。
      [ "$sign" = "0/0/1" ] \
        || { bad "「$g」的結果要靠某一份模型，卻簽成 ${sign}。拿不出成分表的列只能算沒測"; M=1; } ;;
    *)
      bad "「$g」的成分表欄是「${stamp}」，不在那兩個值裡"; M=1 ;;
  esac
done <<EOF
$(rows "$STD")
EOF
[ "$M" = 0 ] && ok "不適用 ${NA} 列（判準不看模型說了什麼）、需要 ${NEED} 列（拿不出成分表，算沒測）"
fi

printf '\n通過 %s、沒過 %s、沒有結論 %s\n' "$PASS" "$FAIL" "$SKIP"
# 離開碼公約（Day 22）：0 全部通過、1 有沒過的、2 有節被跳過，沒有結論。
[ "$FAIL" != 0 ] && exit 1
[ "$SKIP" != 0 ] && exit 2
exit 0
