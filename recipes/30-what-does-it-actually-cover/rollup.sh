#!/usr/bin/env bash
# 把前二十九天的驗證紀錄收成一張三欄表：過了、沒過、沒測。
#
#   bash rollup.sh          # 重跑各組的來源，算一次，跟 standard.tsv 的簽核欄比
#   bash rollup.sh --list   # 只印標準與沒測清單，一發都不跑
#
# 判準的正本是 standard.tsv 與 uncovered.tsv，兩份都是人填的。
# 這支只做兩件事：把那幾條重跑指令跑一次，然後比對。它不決定任何一列該算哪一欄。
#
# 離開碼照 Day 22 那份公約：
#   0  每一組算出來的三個數字都跟簽核欄一樣
#   1  有一組跟簽核對不上。有東西動了，人要回去重新看一次再簽
#   2  有一組跑不動，沒有結論
#
# ⚠️ 「沒過 7」不會讓這支回 1。那七條是簽核過的已知缺口，每天擋你一次的話
# 三週後就沒有人看它了。會讓它回 1 的是「跟簽核不一樣」，包括從沒過變成過了。
set -u
export LC_ALL=C
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
STD=standard.tsv
UNC=uncovered.tsv

for f in "$STD" "$UNC"; do
  [ -r "$f" ] || { echo "找不到 $f，判準的正本不在，沒有結論" >&2; exit 2; }
done

# 一組一組算。每一組回三個數字：過了 沒過 沒測。
measure() {
  case "$1" in
    攻防案例)
      OUT=$(cd "$ROOT/recipes/24-green-or-never-hit" && bash run.sh 2>/dev/null); RC=$?
      [ "$RC" = 2 ] && { echo "0 0 0"; return 2; }
      N=$(printf '%s\n' "$OUT" | grep -c '^C[0-9]')
      P=$(printf '%s\n' "$OUT" | grep -c '	符合$')
      F=$(printf '%s\n' "$OUT" | grep -c '	缺口$')
      # run.sh 的結果欄有八個值，只有「符合」跟「缺口」是這張表讀得懂的。
      # 剩下六個（補起來了、退步了、誤擋了、放行了、打空氣、沒有結論）都代表
      # 那份紀錄跟這次實測不一樣，這時候整組判沒有結論，不能挑一邊當結果。
      # 這裡不列舉那六個字，改成數對不對得起來：run.sh 哪天多一個判定值也接得住。
      [ "$((P+F))" = "$N" ] && [ "$N" -ge 1 ] || { echo "0 0 0"; return 2; }
      echo "$P $F 0"; return 0 ;;
    輸入側回歸)
      (cd "$ROOT/recipes/14-same-attacks-every-time" && bash verify.sh >/dev/null 2>&1); RC=$?
      case "$RC" in
        0) echo "1 0 0"; return 0 ;;
        2) echo "0 0 1"; return 2 ;;
        *) echo "0 1 0"; return 0 ;;
      esac ;;
    鏈的出口那半)
      command -v node >/dev/null 2>&1 || { echo "0 0 1"; return 2; }
      (cd "$ROOT" && node -e "import('jsdom')" >/dev/null 2>&1) || { echo "0 0 1"; return 2; }
      OUT=$(cd "$ROOT/recipes/29-single-checks-combined" && node chain-exec.mjs 2>&1)
      # 兩句都要在：有洞版真的成立（對照組），修好版擋下來（要驗的那一半）。
      # 只看修好版的話，一支什麼都不做的 render 也會過。
      if printf '%s' "$OUT" | grep -qF 'XSS 成立' \
         && printf '%s' "$OUT" | grep -qF '只當文字顯示，擋下'; then
        echo "1 0 0"; return 0
      fi
      echo "0 1 0"; return 0 ;;
    整條鏈)
      # 沒有重跑指令的東西不會有結果。這一列永遠是沒測，直到有人寫得出那條指令。
      echo "0 0 1"; return 0 ;;
    *)
      echo "0 0 0"; return 2 ;;
  esac
}

rows() { grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$' | tail -n +2; }

if [ "${1:-}" = "--list" ]; then
  printf '評分標準（standard.tsv）\n\n'
  rows "$STD" | while IFS="$(printf '\t')" read -r g e s r sign why; do
    printf '  %s\t簽核 %s\t重跑：%s\n' "$g" "$sign" "$r"
  done
  printf '\n沒進表的東西（uncovered.tsv）\n\n'
  rows "$UNC" | while IFS="$(printf '\t')" read -r item kind src why; do
    printf '  %s\t%s\n' "$item" "$kind"
  done
  exit 0
fi

TP=0; TF=0; TU=0; BAD=0; UNK=0
# 每一欄自己帶標籤，不排版對齊：printf 的欄寬數的是位元組，中文組名一長
# 整張表就歪掉，而歪掉的表會讓人不想讀。
printf '\n表：本系列固定案例的通過狀況\n\n'
while IFS="$(printf '\t')" read -r g expand src rerun sign why; do
  [ -n "$g" ] || continue
  GOT=$(measure "$g"); MRC=$?
  set -- $GOT
  P=$1; F=$2; U=$3
  MINE="$P/$F/$U"
  MARK=""
  if [ "$MRC" = 2 ]; then MARK="  ← 跑不動，沒有結論"; UNK=$((UNK+1));
  elif [ "$MINE" != "$sign" ]; then MARK="  ← 跟簽核 ${sign} 對不上"; BAD=$((BAD+1)); fi
  printf '  %s\t過了 %s、沒過 %s、沒測 %s（簽核 %s）%s\n' "$g" "$P" "$F" "$U" "$sign" "$MARK"
  TP=$((TP+P)); TF=$((TF+F)); TU=$((TU+U))
done <<EOF
$(rows "$STD")
EOF

printf '\n  合計 %s 列：過了 %s、沒過 %s、沒測 %s\n' "$((TP+TF+TU))" "$TP" "$TF" "$TU"

printf '\n沒進這張表的東西（uncovered.tsv，%s 項）\n\n' "$(rows "$UNC" | grep -c .)"
while IFS="$(printf '\t')" read -r item kind src why; do
  [ -n "$item" ] || continue
  printf '  %s（%s）\n    %s\n' "$item" "$kind" "$why"
done <<EOF
$(rows "$UNC")
EOF

printf '\n這張表回答的是「這些案例現在走不走得通」，不回答涵蓋率。\n'
[ "$UNK" = 0 ] || { printf '有 %s 組跑不動。\n' "$UNK"; exit 2; }
[ "$BAD" = 0 ] || { printf '有 %s 組跟簽核對不上，回去重新看過再簽。\n' "$BAD"; exit 1; }
printf '每一組都跟簽核一樣。\n'
exit 0
