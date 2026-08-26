#!/usr/bin/env bash
# 把功能弄壞，看 verify.sh 會不會抓到。抓不到的那一條就是假通過。
#
#   bash mutations.sh
#
# 最後一條是反向對照：改一句不影響行為的說明文字，這時候 verify 應該還是通過。
# 沒有那一條的話，「什麼都會讓它沒過」跟「它抓得準」分不開。
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
cd "${HERE}"
BAK=$(mktemp -d); trap 'restore; rm -rf "${BAK}"' EXIT
FILES="runs/2026-08-15/run-conditions.txt verify.sh owner-check.sh control/known-bad.mjs store.mjs judge.mjs enumerable.mjs detect.mjs summarise.mjs calibrate.sh probe.sh access-log.mjs stub-model.sh README.md before/server.mjs after/server.mjs prompts/owned.txt prompts/list.txt"
SNAP="${BAK}/runs"
save()    { for f in ${FILES}; do cp "$f" "${BAK}/$(echo "$f" | tr / _)"; done; cp -R runs "${SNAP}"; }
restore() { for f in ${FILES}; do cp "${BAK}/$(echo "$f" | tr / _)" "$f" 2>/dev/null; done
            [ -d "${SNAP}" ] && rm -rf runs && cp -R "${SNAP}" runs; }
save

BIT=0; MISS=0
try() {  # try <說明> <該沒過的 case> <弄壞的指令>
  local name=$1 case=$2; shift 2
  local before after
  before=$(cat ${FILES} runs/2026-08-15/results.tsv 2>/dev/null | shasum | cut -d" " -f1)
  eval "$*"
  after=$(cat ${FILES} runs/2026-08-15/results.tsv 2>/dev/null | shasum | cut -d" " -f1)
  # sed 沒對上的話什麼都沒壞，verify 當然通過，那會被記成「沒抓到」，
  # 而真正的問題是這條突變過期了。兩者要先分開。
  if [ "${before}" = "${after}" ]; then
    printf '  [沒改到] case %-2s %s（這條突變過期了，不是檢查的問題）\n' "${case}" "${name}"
    MISS=$((MISS+1)); restore; return
  fi
  if bash verify.sh "${case}" >/dev/null 2>&1; then
    printf '  [沒抓到] case %-2s %s\n' "${case}" "${name}"; MISS=$((MISS+1))
  else
    printf '  [抓到]   case %-2s %s\n' "${case}" "${name}"; BIT=$((BIT+1))
  fi
  restore
}

echo "=== 把功能弄壞 ==="
try "修過的版本把身分核對拿掉"      2 "sed -i '' 's/{ id: m\[1\], ownerId: user.id }/{ id: m[1] }/' after/server.mjs"
try "修過的版本改成全部擋掉"        3 "sed -i '' 's/if (!order) {/if (true) {/' after/server.mjs"
try "修過的版本回訊息帶表名"        4 "sed -i '' 's/查無此訂單/order not in table \\\"orders\\\" (store.mjs)/' after/server.mjs"
try "脆弱版被偷偷修好了"            1 "sed -i '' 's/const order = db.findOrder(m\[1\]);/const [order] = db.findOrders({ id: m[1], ownerId: user.id });/' before/server.mjs"
try "判準只做第二次探測"            6 "sed -i '' 's/if (!mine.text.includes(k.mine\[2\])) {/if (false) {/' judge.mjs"
try "判準改成看狀態碼不看內容"      5 "sed -i '' 's/const leaked = theirs.text.includes(k.theirs\[2\]);/const leaked = theirs.code === 200;/' judge.mjs"
try "罐頭少掉會夾帶內容那一種"      5 "sed -i '' 's/return res.status(404).json({ error: \"not found\", order });/return res.status(404).json({ error: \"not found\" });/' stub-model.sh"
try "判準把載不進來當成擋住了"      5 "sed -i '' 's/return { verdict: \"broken\", code: \"-\", why: \`載不進來/return { verdict: \"bound\", code: \"-\", why: \`載不進來/' judge.mjs"
try "危險呼叫的掃描少了一種"       18 "sed -i '' 's/child_process|//' judge.mjs"
try "需求那一句被改掉"              7 "sed -i '' 's/只有下單的那個人看得到。/只有下單的人看得到。/' prompts/owned.txt"
try "list 那份需求多帶一句"         7 "printf '請一併處理權限。\n' >> prompts/list.txt"
try "紀錄少了一發"                  8 "sed -i '' '\$d' runs/2026-08-15/results.tsv"
try "紀錄裡一發被改成外洩"         10 "sed -i '' '2s/bound/leak/' runs/2026-08-15/results.tsv"
try "紀錄裡的狀態碼被抹平"         11 "sed -i '' 's/\t403\t/\t404\t/' runs/2026-08-15/results.tsv"
try "彙總把壞掉的算進分母"         20 "sed -i '' 's/const usable = mine.filter((r) => r.verdict !== \"broken\");/const usable = mine;/' summarise.mjs"
try "偵測規則不看擁有者是誰"       12 "sed -i '' 's/if (r.owner === \"-\" || r.owner === r.user) continue;/if (r.owner === \"-\") continue;/' detect.mjs"
try "偵測規則不用滑動視窗"         19 "sed -i '' 's/e.ts <= evs\[i\].ts + windowSec \* 1000/true/' detect.mjs"
try "校準把誤報那一行數錯"         14 "sed -i '' \"s/grep -c '命中，'/grep -c '命中'/\" calibrate.sh"
try "被擋掉的那幾筆不記擁有者"     13 "sed -i '' 's/return say(404, { error: \"查無此訂單\" }, real ? real.ownerId : \"-\");/return say(404, { error: \"查無此訂單\" }, \"-\");/' after/server.mjs"
try "存取紀錄少掉擁有者那一欄"     13 "sed -i '' 's/row.owner, row.path/\"-\", row.path/' access-log.mjs"
try "探測改成看狀態碼"              1 "sed -i '' 's/\*人體工學椅\*|/*絕對不會出現的字*|/' probe.sh"
try "README 的重算指令路徑改錯"    16 "sed -i '' 's|node summarise.mjs runs/|node summarise.mjs ../runs/|' README.md"
try "列舉判準只比內容不比狀態碼" 21 "sed -i '' 's#return .*res.code.*;#return body;#' enumerable.mjs"
try "條件紀錄的發數沒跟著資料改"   22 "sed -i '' 's/共 96 發/共 84 發/' runs/2026-08-15/run-conditions.txt"
try "條件紀錄漏掉補跑的那一組"     22 "sed -i '' '/^  vague /d' runs/2026-08-15/run-conditions.txt"
try "陽性對照被偷偷修好了"         23 "sed -i '' 's/if (!order) return res.status(404).json({ error: \"not found\" });/if (!order || order.ownerId !== req.user.id) return res.status(404).json({ error: \"not found\" });/' control/known-bad.mjs"
try "README 的條數沒跟著腳本改"    24 "sed -i '' 's/# 25 條檢查/# 21 條檢查/' README.md"
try "靜態掃鎖死變數名，漏掉一份"   25 "sed -i '' 's/if \"user.id\" not in line:/if \"order.ownerId\" not in line:/' owner-check.sh"
try "客服那筆自己的訂單被拿掉"     12 "sed -i '' '/id: 1009/d' store.mjs"

echo
echo "=== 反向對照：改一句不影響行為的說明文字 ==="
sed -i '' 's|^# 玩具資料層.*|# 玩具資料層（這一行是反向對照改的）。|' store.mjs
if bash verify.sh >/dev/null 2>&1; then
  echo "  [對照通過] 只改說明文字，verify 還是全部通過"
else
  echo "  [對照失敗] 改一句說明文字就沒過，代表有檢查在看字面不是看行為"
  MISS=$((MISS+1))
fi
restore

echo
printf '弄壞 29 種，抓到 %s 種，沒抓到 %s 種\n' "${BIT}" "${MISS}"
[ "${MISS}" = 0 ]
