#!/usr/bin/env bash
# 01 金鑰不要放前端
#
#   bash verify.sh        跑全部三個情境
#   bash verify.sh 2      只跑第 2 個
#
# 全部在 mktemp -d 裡進行，不碰你的任何檔案，跑完自動清掉。
# 需要 node 與 npx（build 用 esbuild，它的 --define 就是 Vite 用來把
# import.meta.env.VITE_* 換成字面值的同一個機制）。

set -u
ONLY="${1:-}"
PASS=0; FAIL=0; SKIP=0
hdr()  { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
ok()   { printf '  \033[32m[OK]\033[0m   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m[FAIL]\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33m[SKIP]\033[0m %s\n' "$1"; SKIP=$((SKIP+1)); }
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

HERE=$(cd "$(dirname "$0")" && pwd)
WS=$(mktemp -d); trap 'rm -rf "$WS"' EXIT

command -v node >/dev/null || { echo "需要 node，這台沒有"; exit 1; }

# 假金鑰。格式做得像真的，這樣掃描與 grep 才測得到東西，它不會打通任何服務
FAKE_KEY="sk-proj-8Kj2mNp4qR7sT9vXwYzA3bC5dE6fG1hI"

ESB="npx --yes esbuild@0.24.0"
# 沒網路的時候這支什麼都沒驗，所以離開碼是 2 不是 0。
# 原本寫 0，意思變成「這台機器連不到 npm」＝綠燈，而 07 對同一件事給的是紅燈。
$ESB --version >/dev/null 2>&1 || { echo "抓不到 esbuild（要網路），全部跳過"; exit 2; }

# 把某一版的 api.js build 成瀏覽器會下載的那份檔案
build() {  # build <before|after> <輸出目錄>
  mkdir -p "$2"
  $ESB "$HERE/$1/api.js" --bundle --format=esm --outfile="$2/bundle.js" \
    --define:import.meta.env.VITE_MODEL_API_KEY="\"${FAKE_KEY}\"" >/dev/null 2>&1
}

# 文章教的檢查：只列檔名，不把完整金鑰印進終端紀錄
scan() { grep -rIl "sk-" "$1" 2>/dev/null | wc -l | tr -d ' '; }

# ─────────────────────────────────────────────────────────────
if want 1; then
hdr "1. build 產物裡有沒有金鑰"

build before "$WS/d1-before"
build after  "$WS/d1-after"
B=$(scan "$WS/d1-before"); A=$(scan "$WS/d1-after")
printf '  before/  dist 裡含 sk- 的檔案數：%s\n' "$B"
printf '  after/   dist 裡含 sk- 的檔案數：%s\n' "$A"

[ "$B" != 0 ] \
  && ok "before 的洞是真的：VITE_ 變數 build 完就是 bundle 裡的一段字面字串" \
  || bad "before 竟然掃不到，這個 recipe 的前提不成立"
[ "$A" = 0 ] \
  && ok "after 掃不到。金鑰沒有進入任何一份會送到瀏覽器的檔案" \
  || bad "after 還掃得到金鑰"

# 讀者最該知道的一句：找不到不等於安全
printf '\n  順帶驗一件事：把金鑰前綴換成別家的，同一份 before 產物會怎樣\n'
OTHER=$(grep -rIl "ghp_" "$WS/d1-before" 2>/dev/null | wc -l | tr -d ' ')
printf '  用 ghp_ 去搜同一份有洞的產物：%s 個檔案\n' "$OTHER"
[ "$OTHER" = 0 ] \
  && ok "搜錯前綴就是 0。grep 找不到只代表這個前綴沒有，不代表沒洩漏" \
  || bad "預期搜不到"
fi

# ─────────────────────────────────────────────────────────────
if want 2; then
hdr "2. 請求打去哪、header 帶了什麼（DevTools 那一招的等價驗證）"

# 跑 build 出來的那份，也就是瀏覽器真的會執行的東西。
# 攔截 fetch，把它想送出去的目標與 header record 下來
cat > "$WS/probe.mjs" <<'PROBE'
const target = process.argv[2];
let captured = null;
globalThis.fetch = async (url, init = {}) => {
  captured = { url: String(url), headers: init.headers ?? {} };
  return { ok: true, status: 200, json: async () => ({ choices: [{ message: { content: "" } }] }) };
};
const mod = await import(target);
try { await mod.ask("hello"); } catch { /* 我們只要攔到的那筆請求 */ }
console.log(JSON.stringify(captured));
PROBE

for V in before after; do
  build "$V" "$WS/d2-$V"
  OUT=$(node "$WS/probe.mjs" "$WS/d2-$V/bundle.js" 2>/dev/null)
  URL=$(printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).url)}catch{console.log("(攔不到)")}})')
  AUTH=$(printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const h=JSON.parse(s).headers||{};console.log(h.Authorization??h.authorization??"(沒有 Authorization)")}catch{console.log("(攔不到)")}})')
  printf '  %-7s 送去 %s\n' "$V" "$URL"
  printf '  %-7s Authorization: %s\n' "" "$AUTH"
done

OUT_B=$(node "$WS/probe.mjs" "$WS/d2-before/bundle.js" 2>/dev/null)
OUT_A=$(node "$WS/probe.mjs" "$WS/d2-after/bundle.js" 2>/dev/null)
printf '%s' "$OUT_B" | grep -q 'api.example-model.com' \
  && ok "before 的瀏覽器直接連供應商，中間沒有你控制的機器" \
  || bad "before 沒有打供應商"
printf '%s' "$OUT_B" | grep -q "$FAKE_KEY" \
  && ok "before 把完整金鑰放進 Authorization，Network 面板一點就看到" \
  || bad "before 的 header 裡沒有金鑰"
printf '%s' "$OUT_A" | grep -q '"/api/chat"' \
  && ok "after 打的是同源的 /api/chat，供應商網址不出現在前端" \
  || bad "after 沒有打自己的後端"
printf '%s' "$OUT_A" | grep -q "$FAKE_KEY" \
  && bad "after 竟然還帶著金鑰" \
  || ok "after 的請求裡沒有供應商金鑰"

printf '\n  提醒：after 之後 Authorization 仍可能出現，那是你自己應用的登入權杖。\n'
printf '  所以驗收不能只看「有沒有 Authorization 這個 header」，要看裡面是誰的憑證。\n'
fi

# ─────────────────────────────────────────────────────────────
if want 3; then
hdr "3. dist 沒清乾淨，你看的是上一版"

D=$WS/d3
build before "$D"
printf '  第一步：先用有洞的版本 build，此時 dist 裡有金鑰（%s 個檔案）\n' "$(scan "$D")"

# 方向一：改好了但沒清 dist。文章裡卡半小時的就是這個
build_skipped_note="（模擬：改完程式碼，但忘記重新 build）"
printf '\n  方向一 %s\n' "$build_skipped_note"
printf '  你以為在看新的，其實 dist 還是舊的：%s 個檔案含 sk-\n' "$(scan "$D")"
[ "$(scan "$D")" != 0 ] \
  && ok "假警報：程式碼已經修好，grep 卻還在紅。找不到原因是因為問題不在程式碼" \
  || bad "沒重現陳舊產物"

# 方向二：更危險。dist 是修好版留下的，原始碼卻被改回有洞的
D2=$WS/d3b
build after "$D2"
printf '\n  方向二（模擬：dist 是修好那版留下的，之後有人把 api.js 改回舊寫法）\n'
printf '  原始碼有洞，但 dist 是乾淨的舊產物：%s 個檔案含 sk-\n' "$(scan "$D2")"
[ "$(scan "$D2")" = 0 ] \
  && ok "假通過，而且這個方向危險得多：檢查是綠的，洞在原始碼裡等著下次 build" \
  || bad "沒重現這個方向"

# 正確做法
rm -rf "$D"; build before "$D"
printf '\n  正確做法：rm -rf dist 之後重新 build，再驗一次\n'
printf '  清掉重 build 之後：%s 個檔案含 sk-\n' "$(scan "$D")"
[ "$(scan "$D")" != 0 ] \
  && ok "拿到的才是這一版原始碼的真實結果" \
  || bad "重 build 之後結果不對"
fi

# ─────────────────────────────────────────────────────────────
printf '\n════════ %s 綠 / %s 紅 / %s 跳過 ════════\n' "$PASS" "$FAIL" "$SKIP"

# 離開碼的意思，全 repo 一致（Day 22 定的）：
#   0 綠，而且真的驗過了
#   1 紅，這是你要它擋你的那種
#   2 環境不到位或有節被跳過，沒有結論。跳過不是通過
[ "${FAIL}" != 0 ] && exit 1
[ "${SKIP}" != 0 ] && exit 2
exit 0
