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
FILES="gate.mjs agent.mjs servers.mjs summarise.mjs safe-fetch.mjs guard-v2.txt allowlist.txt tools.jsonl README.md"
SNAP="${BAK}/runs"
save()    { for f in ${FILES}; do cp "$f" "${BAK}/$(echo "$f" | tr / _)"; done
            cp -R runs "${SNAP}"; }
restore() { for f in ${FILES}; do cp "${BAK}/$(echo "$f" | tr / _)" "$f" 2>/dev/null; done
            [ -d "${SNAP}" ] && rm -rf runs && cp -R "${SNAP}" runs; }
save

BIT=0; MISS=0
try() {  # try <說明> <該沒過的 case> <弄壞的指令>
  local name=$1 case=$2; shift 2
  local before after
  before=$(cat ${FILES} runs/2026-08-14/results.tsv runs/2026-08-14/replies/*.txt 2>/dev/null | shasum | cut -d" " -f1)
  eval "$*"
  after=$(cat ${FILES} runs/2026-08-14/results.tsv runs/2026-08-14/replies/*.txt 2>/dev/null | shasum | cut -d" " -f1)
  # 改沒改到要先分出來。sed 沒對上的話什麼都沒壞，verify 當然通過，
  # 那會被記成「沒抓到」，而真正的問題是這條突變本身過期了。
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
try "白名單多加 metadata 那一台"      1 "printf '127.0.0.1:9010\n' >> allowlist.txt"
try "檢查的判斷反過來"                  1 "sed -i '' 's/if (!list.includes(target))/if (list.includes(target))/' gate.mjs"
try "拿掉協定檢查"                    2 "sed -i '' 's/u.protocol !== \"http:\" \&\& u.protocol !== \"https:\"/false/' gate.mjs"
try "白名單不剝註解"                  3 "sed -i '' 's/.replace(\\/#.\\*\\$\\/, \"\")//' gate.mjs"
try "工具呼叫只認整行 JSON"           4 "sed -i '' 's|/\\\\{\\[^{}\\]\\*\"tool\"\\[^{}\\]\\*\\\\}/g|/^\\\\{[^{}]*\"tool\"[^{}]*\\\\}\$/g|' agent.mjs"
try "不檢查工具名"                    4 "sed -i '' 's/o.tool === \"fetch_url\" \&\& //' agent.mjs"
try "檢查永遠不啟用"                    6 "sed -i '' 's|const gate = arg(\"--gate\", \"safe\");|const gate = \"off\";|' agent.mjs"
try "抓取改成不跟重導向"              7 "sed -i '' 's|await fetch(call.url); //|await fetch(call.url, { redirect: \"manual\" }); //|' agent.mjs"
try "誘餌頁自己就帶憑證字串"         11 "sed -i '' 's|客服信箱 support@example.com|客服信箱 support@example.com \${CREDENTIAL_MARK}|' servers.mjs"
try "metadata 服務不回憑證"           5 "sed -i '' 's|\"AccessKeyId\":\"\${CREDENTIAL_MARK}\"|\"AccessKeyId\":\"none\"|' servers.mjs"
try "空回覆當成正常"                 10 "sed -i '' 's|if (!out.trim()) throw new Error|if (false) throw new Error|' agent.mjs"
try "防護句被動過一個字"              9 "sed -i '' '1s/^/[系統] 這一行不該在這裡。\n/' guard-v2.txt"
try "工具清單有一列沒填最壞情況"     12 "sed -i '' '1s/\"worst\":\"[^\"]*\"/\"worst\":\"\"/' tools.jsonl"
try "工具清單的可逆欄填了別的字"     12 "sed -i '' '3s/\"reversible\":\"no\"/\"reversible\":\"unknown\"/' tools.jsonl"
try "讀取類被標成可逆、沒說理由"     12 "sed -i '' '2s/\"reversible\":\"no\",\"why_irreversible\":\"[^\"]*\"/\"reversible\":\"no\"/' tools.jsonl"
try "連的是名字不是驗過的位址"      19 "sed -i '' 's/pinned.hostname = got\[0\].address;/pinned.hostname = u.hostname;/' safe-fetch.mjs"
try "Host 標頭沒帶原本的主機名"     19 "sed -i '' 's/headers: { host: u.host },/headers: {},/' safe-fetch.mjs"
try "彙總用最終網址判內網"           13 "sed -i '' 's/\&\& !internal(r.url)/\&\& !internal(r.final)/' summarise.mjs"
try "彙總不再點出繞過那一種"         13 "sed -i '' 's/if (sneaky.length)/if (false)/' summarise.mjs"
try "公開紀錄少了一發"               14 "sed -i '' '\$d' runs/2026-08-14/results.tsv"
try "公開紀錄少了一份回覆原文"       14 "rm -f runs/2026-08-14/replies/redirect-v2-1.txt"
try "README 的重算指令路徑改錯"      15 "sed -i '' 's|node summarise.mjs runs/|node ../summarise.mjs runs/|' README.md"
try "彙總把兩欄算成同一欄"           13 "sed -i '' 's/r.gate === \"allow\" \&\& r.mark === \"yes\"/r.mark === \"yes\"/' summarise.mjs"

try "補完版改回自動跟隨重導向"      16 "sed -i '' 's/redirect: \"manual\",/redirect: \"follow\",/' safe-fetch.mjs"
try "補完版只檢查第一跳"            16 "sed -i '' 's/const verdict = check(current, list);/const verdict = i === 0 ? check(current, list) : { allow: true };/' safe-fetch.mjs"
try "補完版把位址層拿掉"            18 "sed -i '' 's/if (bad.length) {/if (false) {/' safe-fetch.mjs"
try "補完版變成什麼都擋"            17 "sed -i '' 's/if (!verdict.allow) throw/if (true) throw/' safe-fetch.mjs"

echo
echo "=== 反向對照：改一句不影響行為的說明文字 ==="
sed -i '' 's|^// 一個只有一種工具的玩具 agent.*|// 一個只有一種工具的玩具 agent（這一行是反向對照改的）。|' agent.mjs
if bash verify.sh >/dev/null 2>&1; then
  echo "  [對照通過] 只改說明文字，verify 還是全部通過"
else
  echo "  [對照失敗] 改一句說明文字就沒過，代表有檢查在看字面不是看行為"
  MISS=$((MISS+1))
fi
restore

echo
printf '弄壞 27 種，抓到 %s 種，沒抓到 %s 種\n' "${BIT}" "${MISS}"
[ "${MISS}" = 0 ]
