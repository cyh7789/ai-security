#!/usr/bin/env bash
# 把 recipe 24 那份攻擊集完整跑一次，連同「這一跑是在哪個版本上跑的」一起存檔。
#
#   bash snapshot.sh before        # 修補前
#   bash snapshot.sh after-default # 改完出廠預設
#   bash snapshot.sh after-gate    # 再改完訂單那條路徑的預設閘
#
# 離開碼照 Day 22 那份公約：0 存好了、1 這一跑有案例沒有結論、2 環境不到位。
#
# 為什麼要存版本資訊：這一天唯一的產出是「它修補前真的紅過」，
# 而一份只有結果沒有版本的表格證明不了那件事。存了 commit，
# 任何人都可以 checkout 回去自己跑一次；沒存的話，這份 before 跟
# 事後從版控挖出來再補一個檔案，在檔案系統上長得一模一樣。
#
# 工作區髒的時候照樣存，但要標出來。擋掉的話會逼人先 commit 一份還沒驗過的東西，
# 而標出來讀者自己就分得出這一份能不能重現。
set -u
cd "$(dirname "$0")"
export LC_ALL=C
R=..

LABEL="${1:-}"
case "$LABEL" in
  ''|-*) echo "要給一個標籤，例如 bash snapshot.sh before" >&2; exit 2 ;;
esac
case "$LABEL" in
  */*) echo "標籤不能有斜線：${LABEL}" >&2; exit 2 ;;
esac

RUNSH="$R/24-green-or-never-hit/run.sh"
[ -r "$RUNSH" ] || { echo "讀不到 ${RUNSH}，這一跑沒有結論" >&2; exit 2; }

HEAD=$(git rev-parse HEAD 2>/dev/null) || { echo "這裡不是 git 工作區，存不了版本" >&2; exit 2; }
# 「髒」問的是被量的那些 recipe 有沒有沒提交的改動，所以把 recipe 25 自己排掉：
# 這一份是紀錄不是被量的東西，它每存一次自己就會變髒，於是每一份都標 yes，
# 那一欄就永遠不會是 no，也就永遠不帶資訊。
SELF=$(basename "$(pwd -P)")
if [ -n "$(git status --porcelain -- "$R" ":(exclude)$R/$SELF" 2>/dev/null)" ]; then DIRTY=yes; else DIRTY=no; fi

OUT=$(bash "$RUNSH" 2>/dev/null); RC=$?
# 離開碼 1 是 recipe 24 的常態：清單上有已知的缺口。2 才是真的沒結論。
[ "$RC" = 2 ] && { echo "run.sh 回 2，有案例跑不動，這一份不存" >&2; exit 2; }

mkdir -p "$LABEL"
{
  printf '# 標籤\t%s\n' "$LABEL"
  printf '# 跑的時間\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
  printf '# commit\t%s\n' "$HEAD"
  printf '# 被量的那些 recipe 有未提交的改動\t%s\n' "$DIRTY"
  printf '# MODEL_CMD\t%s\n' 'bash stub-model.sh（罐頭，run.sh 自己設的）'
  printf '# run.sh 離開碼\t%s\n' "$RC"
  printf '%s\n' "$OUT"
} > "$LABEL/run.tsv"

printf '存了 %s/run.tsv：%s 條，缺口 %s 條，離開碼 %s，工作區髒=%s\n' \
  "$LABEL" \
  "$(printf '%s' "$OUT" | tail -n +2 | grep -c .)" \
  "$(printf '%s' "$OUT" | awk -F'\t' '$6=="缺口"' | grep -c . || true)" \
  "$RC" "$DIRTY"
exit 0
