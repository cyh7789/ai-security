#!/usr/bin/env bash
# 把功能弄壞，看 verify.sh 會不會抓到。抓不到的那一條就是假綠燈。
#
#   bash mutations.sh
#
# 最後一條是反向對照：改一句不影響行為的說明文字，這時候 verify 應該還是綠。
# 沒有那一條的話，「什麼都會讓它紅」跟「它咬得準」分不開。
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
cd "${HERE}"
BAK=$(mktemp -d); trap 'restore; rm -rf "${BAK}"' EXIT
FILES="gate.mjs agent.mjs servers.mjs summarise.mjs guard-v2.txt allowlist.txt tools.jsonl README.md"
SNAP="${BAK}/runs"
save()    { for f in ${FILES}; do cp "$f" "${BAK}/$(echo "$f" | tr / _)"; done
            cp -R runs "${SNAP}"; }
restore() { for f in ${FILES}; do cp "${BAK}/$(echo "$f" | tr / _)" "$f" 2>/dev/null; done
            [ -d "${SNAP}" ] && rm -rf runs && cp -R "${SNAP}" runs; }
save

BIT=0; MISS=0
try() {  # try <說明> <該轉紅的 case> <弄壞的指令>
  local name=$1 case=$2; shift 2
  eval "$*"
  if bash verify.sh "${case}" >/dev/null 2>&1; then
    printf '  [沒抓到] case %-2s %s\n' "${case}" "${name}"; MISS=$((MISS+1))
  else
    printf '  [抓到]   case %-2s %s\n' "${case}" "${name}"; BIT=$((BIT+1))
  fi
  restore
}

echo "=== 把功能弄壞 ==="
try "白名單多加 metadata 那一台"      1 "printf '127.0.0.1:9010\n' >> allowlist.txt"
try "閘的判斷反過來"                  1 "sed -i '' 's/if (!list.includes(target))/if (list.includes(target))/' gate.mjs"
try "拿掉協定檢查"                    2 "sed -i '' 's/u.protocol !== \"http:\" \&\& u.protocol !== \"https:\"/false/' gate.mjs"
try "白名單不剝註解"                  3 "sed -i '' 's/.replace(\\/#.\\*\\$\\/, \"\")//' gate.mjs"
try "工具呼叫只認整行 JSON"           4 "sed -i '' 's|/\\\\{\\[^{}\\]\\*\"tool\"\\[^{}\\]\\*\\\\}/g|/^\\\\{[^{}]*\"tool\"[^{}]*\\\\}\$/g|' agent.mjs"
try "不檢查工具名"                    4 "sed -i '' 's/o.tool === \"fetch_url\" \&\& //' agent.mjs"
try "閘永遠不啟用"                    6 "sed -i '' 's/const gateOn = .*/const gateOn = false;/' agent.mjs"
try "抓取改成不跟重導向"              7 "sed -i '' 's|await fetch(call.url); //|await fetch(call.url, { redirect: \"manual\" }); //|' agent.mjs"
try "誘餌頁自己就帶憑證字串"         11 "sed -i '' 's|客服信箱 support@example.com|客服信箱 support@example.com \${CREDENTIAL_MARK}|' servers.mjs"
try "metadata 服務不回憑證"           5 "sed -i '' 's|\"AccessKeyId\":\"\${CREDENTIAL_MARK}\"|\"AccessKeyId\":\"none\"|' servers.mjs"
try "空回覆當成正常"                 10 "sed -i '' 's|if (!out.trim()) throw new Error|if (false) throw new Error|' agent.mjs"
try "防護句被動過一個字"              9 "sed -i '' '1s/^/[系統] 這一行不該在這裡。\n/' guard-v2.txt"
try "工具清單有一列沒填最壞情況"     12 "sed -i '' '1s/\"worst\":\"[^\"]*\"/\"worst\":\"\"/' tools.jsonl"
try "工具清單的可逆欄填了別的字"     12 "sed -i '' '3s/\"reversible\":\"no\"/\"reversible\":\"unknown\"/' tools.jsonl"
try "彙總用最終網址判內網"           13 "sed -i '' 's/\&\& !internal(r.url)/\&\& !internal(r.final)/' summarise.mjs"
try "彙總不再點出繞過那一種"         13 "sed -i '' 's/if (sneaky.length)/if (false)/' summarise.mjs"
try "公開紀錄少了一發"               14 "sed -i '' '\$d' runs/2026-08-14/results.tsv"
try "公開紀錄少了一份回覆原文"       14 "rm -f runs/2026-08-14/replies/redirect-v2-1.txt"
try "README 的重算指令路徑改錯"      15 "sed -i '' 's|node summarise.mjs runs/|node ../summarise.mjs runs/|' README.md"
try "彙總把兩欄算成同一欄"           13 "sed -i '' 's/r.gate === \"allow\" \&\& r.mark === \"yes\"/r.mark === \"yes\"/' summarise.mjs"

echo
echo "=== 反向對照：改一句不影響行為的說明文字 ==="
sed -i '' 's|^// 一個只有一種工具的玩具 agent.*|// 一個只有一種工具的玩具 agent（這一行是反向對照改的）。|' agent.mjs
if bash verify.sh >/dev/null 2>&1; then
  echo "  [對照通過] 只改說明文字，verify 還是全綠"
else
  echo "  [對照失敗] 改一句說明文字就紅了，代表有檢查在看字面不是看行為"
  MISS=$((MISS+1))
fi
restore

echo
printf '弄壞 20 種，抓到 %s 種，沒抓到 %s 種\n' "${BIT}" "${MISS}"
[ "${MISS}" = 0 ]
