#!/usr/bin/env bash
# 兩份存檔逐條對照，印每一條往哪個方向動了。
#
#   bash compare.sh before after-default
#
# 離開碼照 Day 22 那份公約：0 兩份對得起來、1 案例集合對不上、2 檔案讀不到。
#
# 方向不在這裡重算。run.sh 的 direction() 是唯一一份，這裡用 RUN_SH_LIB 接縫
# 把它叫進來。抄一份的話兩邊會分岔，而分岔的那天這張對照表還是印得出漂亮的字。
set -u
cd "$(dirname "$0")"
export LC_ALL=C
R=..

A="${1:-}"; B="${2:-}"
[ -n "$A" ] && [ -n "$B" ] || { echo "用法：bash compare.sh <前> <後>" >&2; exit 2; }
FA="$A/run.tsv"; FB="$B/run.tsv"
for f in "$FA" "$FB"; do [ -r "$f" ] || { echo "讀不到 ${f}" >&2; exit 2; }; done

# 在 recipe 24 那個目錄裡把它 source 起來問一次。run.sh 讀得到 cases.tsv 才肯進 lib 模式，
# 而那個檔在它自己的目錄裡。24/verify.sh 第 17 條用的也是這個接縫。
#
# 兩個值走位置參數進去，不是拼字串。存檔是這一支要查的對象，
# 它的每一格都要當成敵意輸入：拼進 bash -c 的話，一格寫成
# 「擋 沒擋; touch /tmp/x; :」就會在對照的時候被執行，而這張表照樣印乾淨的方向。
direction() {  # $1=期望 $2=前面那一份的實測
  (cd "$R/24-green-or-never-hit" && RUN_SH_LIB=1 bash -c 'source ./run.sh; direction "$1" "$2"' _ "$1" "$2")
}

meta() { sed -n "s/^# $2\t//p" "$1"; }
rows() { grep -v '^#' "$1" | tail -n +2; }

CA=$(meta "$FA" commit); CB=$(meta "$FB" commit)
printf '%s\t%s\t%s\n' 前 "$A" "$CA"
printf '%s\t%s\t%s\n' 後 "$B" "$CB"
if [ "$CA" = "$CB" ]; then
  # 同一個 commit 上的兩份，中間沒有東西可以改變行為。跑出差異的話那個差異
  # 來自別的地方（未提交的改動、環境、隨機），不能拿來當「修補生效了」的證據。
  printf '⚠️\t兩份跑在同一個 commit 上，這張表證明不了修補做了什麼\n'
fi
printf '\n'

printf 'case\tpath\t期望\t前\t後\t變化\n'
rc=0
while IFS=$'\t' read -r c path want _now got _res; do
  [ -n "$c" ] || continue
  line=$(rows "$FB" | awk -F'\t' -v k="$c" '$1==k')
  if [ -z "$line" ]; then
    printf '%s\t%s\t%s\t%s\t-\t後面那份沒有這條\n' "$c" "$path" "$want" "$got"
    rc=1; continue
  fi
  after=$(printf '%s' "$line" | awk -F'\t' '{print $5}')
  if [ "$after" = "$got" ]; then
    chg=不變
  else
    chg=$(direction "$want" "$got")
    # 問不出方向就是這一列的欄位不對（缺欄、值域外）。空白印出去的話，
    # 一列壞掉的存檔在表上長得像一列沒有變化的正常資料。
    [ -n "$chg" ] || { chg=方向算不出來; rc=1; }
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$c" "$path" "$want" "$got" "$after" "$chg"
done < <(rows "$FA")

EXTRA=$(comm -13 <(rows "$FA" | cut -f1 | sort) <(rows "$FB" | cut -f1 | sort) | tr '\n' ' ')
if [ -n "$(printf '%s' "$EXTRA" | tr -d ' ')" ]; then
  printf '\n後面那份多出來的案例：%s　前面那份沒有它們，這幾條沒有 before\n' "$EXTRA"
  rc=1
fi
exit "$rc"
