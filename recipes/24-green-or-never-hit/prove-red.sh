#!/usr/bin/env bash
# 弄壞一道真的防線，看測試會不會紅。
#
#   bash prove-red.sh
#
# 為什麼要有這支：verify.sh 第 18 條測的是「紀錄跟實測對不上會不會印退步了」，
# 它改的是紀錄那一欄，不是防線。那樣測得到對帳，測不到「測試入口本身會不會誤導人」。
#
# 這一支改的是 C04 走哪一道閘：從擋得住的外部基準閘換成擋不住的意圖核對閘。
# 那條案例的紀錄寫著「擋住」，所以它會變成「退步了」。
# 判準是 node --test 的離開碼：斷言寫成排除式的時候，那邊照樣是 13 pass 離開碼 0，
# 而現在它必須紅。這一段是文章引用的那個現象，落成腳本才有人能重跑。
#
# 離開碼：0 測試如預期轉紅、1 測試沒紅、2 環境不到位
set -u
cd "$(dirname "$0")"
export LC_ALL=C
B=$(mktemp -d); cp run.sh cases.test.mjs "$B/"
trap 'cp "$B"/* .; rm -rf "$B"' EXIT

command -v node >/dev/null || { echo "要 node，沒有結論"; exit 2; }
# 基線不能拿 verify.sh 驗：它的第 19 條會呼叫這一支，兩邊互叫會無限遞迴。
# 這裡只要確認測試入口在動手之前是綠的就夠了。
node --test cases.test.mjs >/dev/null 2>&1 || { echo "動手之前 node --test 就是紅的，這一跑沒有結論"; exit 2; }

# C04 原本走外部基準閘（擋得住），換成意圖核對閘（擋不住）。
python3 -c '
import io,sys
p="run.sh"; s=io.open(p,encoding="utf8").read()
a="    C04) agent_delete hijack-a external ;;"
b="    C04) agent_delete hijack-a intent ;;"
if s.count(a)!=1: sys.exit("C04 那一行找不到")
io.open(p,"w",encoding="utf8").write(s.replace(a,b))' || { echo "改不動 run.sh，沒有結論"; exit 2; }

ROW=$(bash run.sh C04 2>/dev/null | awk -F'\t' 'NR>1')
node --test cases.test.mjs >/dev/null 2>&1; RC=$?

printf '弄壞之後 run.sh 那一列：%s\n' "${ROW}"
printf 'node --test 的離開碼：%s\n' "${RC}"

case "${ROW}" in
  *退步了*) ;;
  *) echo "run.sh 沒有印「退步了」，這一跑量不到要量的東西"; exit 2 ;;
esac

if [ "${RC}" != 0 ]; then
  echo "測試紅了，這就是正面表列的斷言該有的反應"
else
  echo "測試沒紅。斷言又退化成排除式了，跑幾條綠都不算數。"
  exit 1
fi
