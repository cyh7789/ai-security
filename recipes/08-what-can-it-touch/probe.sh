#!/usr/bin/env bash
# 閉環的最後一步：證明「收窄範圍」這件事真的生效了。
#
#   bash probe.sh
#
# 它自己造正反兩組，兩組都符合預期才算通過：
#   1  在 /tmp/mcp-probe 底下建 allowed/ok.txt 與 denied/secret.txt
#   2  用寬範圍（允許目錄給 /tmp/mcp-probe）起官方 filesystem server，
#      讀 denied/secret.txt → 必須讀到。這是正對照：證明這個探針真的碰得到東西。
#   3  用收窄後的範圍（允許目錄只給 /tmp/mcp-probe/allowed）起同一台，
#      同一個呼叫 → 必須被拒。
#   4  跑完把 /tmp/mcp-probe 清掉
#
# 離開碼分四種，因為這四件事的處理方式不一樣：
#   0  兩步都符合預期
#   1  第 3 步失敗：收窄之後它還是讀到了。降權沒生效，去修設定
#   2  前置條件不到位（沒有 npx／沒有 curl／連不到外網）。什麼都還沒驗到
#   3  第 2 步失敗：寬範圍也讀不到。探針壞了，先修環境，這一輪的第 3 步不算數
#
# 2 跟 3 分開的理由：寬範圍讀不到的時候，收窄之後當然也讀不到，
# 於是第 3 步會「通過」。那是一顆假綠燈，而它跟真的降權成功在畫面上長得一樣。
#
# 這支是整份唯一會在你機器上建東西的腳本，全部在 /tmp/mcp-probe 底下，跑完刪掉。
# 它需要抓 @modelcontextprotocol/server-filesystem，所以會連外網。

set -u
HERE=$(cd "$(dirname "$0")" && pwd)

ROOT=${PROBE_ROOT:-/tmp/mcp-probe}
# 這兩個是給 verify.sh 用的：把寬的那邊收窄可以逼出 rc=3，把窄的那邊放寬可以逼出 rc=1。
# 少了這個接縫，那兩條離開碼只能靠改原始碼去驗，而那驗到的是另一份腳本。
WIDE=${PROBE_WIDE:-${ROOT}}
NARROW=${PROBE_NARROW:-${ROOT}/allowed}
FSPKG=${PROBE_FS_PKG:-@modelcontextprotocol/server-filesystem@2026.7.10}
REGISTRY=${PROBE_REGISTRY:-https://registry.npmjs.org}
CANARY=mcp-probe-canary-do-not-copy

# rm -rf 的對象只能是 /tmp 底下。PROBE_ROOT 是環境變數，指到別的地方就不刪也不跑。
case "${ROOT}" in
  /tmp/*) ;;
  *) printf 'PROBE_ROOT 只能指到 /tmp 底下，收到的是 %s。這支會 rm -rf 那個目錄，所以不接受別的位置。\n' "${ROOT}"; exit 2 ;;
esac

# 每一條收尾的路都先印這一行。讀者看得出結論從哪裡開始，
# 而 verify.sh 靠它把「結論那一段」單獨切出來比：
# 整份輸出去比是沒用的，區塊標題本來就不一樣，任何兩種失敗都會「看起來分得開」。
conclude() { printf '\n── 結論 ──\n'; }

cleanup() { rm -rf "${ROOT}"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

# ── 前置條件 ──────────────────────────────────────────────
# 少了任何一項就是「這一輪什麼都沒驗到」，不是「降權沒生效」，所以離開碼跟那個分開。
# 靜默跳過是這一份最反對的形狀：畫面上會跟通過長得一樣。
for t in node npx curl; do
  command -v "${t}" >/dev/null 2>&1 || {
    conclude
    printf '前置條件不到位：沒有 %s。\n' "${t}"
    printf '這支要用 npx 抓 filesystem server、用 curl 量連不連得到外網，缺一個就什麼都沒驗到。離開碼 2。\n'
    exit 2; }
done

# 套件名帶了版本（釘死才可重現），但註冊處的 metadata 端點吃的是不帶版本的名字，
# 接上去會 404，然後這支會誤報成「連不到外網」。
FSNAME=${FSPKG%@*}
code=$(curl -s -o /dev/null -w '%{http_code}' -m 20 "${REGISTRY}/${FSNAME}" 2>/dev/null)
if [ "${code}" != "200" ]; then
  conclude
  printf '前置條件不到位：問不到 %s（HTTP %s）。\n' "${REGISTRY}" "${code}"
  printf 'npx 抓不到 filesystem server 就起不了探針，這一輪什麼都沒驗到。離開碼 2。\n'
  exit 2
fi

# ── 造場景 ────────────────────────────────────────────────
rm -rf "${ROOT}"
mkdir -p "${ROOT}/allowed" "${ROOT}/denied" || { echo "建不了 ${ROOT}"; exit 2; }
printf 'ok\n' > "${ROOT}/allowed/ok.txt"
printf '%s\n' "${CANARY}" > "${ROOT}/denied/secret.txt"
TARGET="${ROOT}/denied/secret.txt"

ask() {   # ask <允許目錄> → 印出 mcp-rpc 的輸出
  node "${HERE}/mcp-rpc.cjs" call read_text_file "{\"path\":\"${TARGET}\"}" -- \
    npx -y "${FSPKG}" "$1" 2>&1
}

printf '要讀的檔：%s\n' "${TARGET}"
printf '裡面放的是一個固定的記號字串，讀到了才算真的讀到，不是看有沒有回話。\n\n'

# ── 第 2 步：正對照 ───────────────────────────────────────
printf '── 寬範圍（允許目錄 %s）──\n' "${WIDE}"
out=$(ask "${WIDE}")
verdict=$(printf '%s\n' "${out}" | head -1)
body=$(printf '%s\n' "${out}" | tail -n +2)
printf '%s\n' "${verdict}"
printf '%s\n' "${body}" | head -3

# 判準是「記號字串有沒有出現」，不是 VERDICT=OK。
# 只看 VERDICT 的話，一台回 200 但內容是別的東西的 server 也會過關，
# 而這一步的全部意義就是證明探針碰得到那個檔。
if ! printf '%s' "${body}" | grep -q "${CANARY}"; then
  conclude
  printf '探針壞了：寬範圍也讀不到那個記號字串。\n'
  printf '這一輪沒有驗到「收窄有沒有效」：寬的讀不到，窄的當然也讀不到，第 3 步會假通過。\n'
  printf '先修環境（npx 抓不到套件、允許目錄給錯、檔案沒建起來都會走到這裡）。離開碼 3。\n'
  exit 3
fi
printf '正對照成立：寬範圍讀到了那個記號字串。\n\n'

# ── 第 3 步：收窄之後 ─────────────────────────────────────
printf '── 收窄後（允許目錄只給 %s）──\n' "${NARROW}"
out=$(ask "${NARROW}")
verdict=$(printf '%s\n' "${out}" | head -1)
body=$(printf '%s\n' "${out}" | tail -n +2)
printf '%s\n' "${verdict}"
printf '%s\n' "${body}" | head -3

# 這裡不能只看 VERDICT：MCP 的工具錯誤不走 JSON-RPC 的 error 欄位，
# filesystem server 拒絕的時候回的是一個成功的 result，isError 是 true、
# 理由塞在 content 的文字裡（mcp-rpc.cjs 把那種情形叫 TOOLERR）。
# 判準還是同一條：記號字串有沒有出現。它出現了就是讀到了，不管 VERDICT 印什麼。
if printf '%s' "${body}" | grep -q "${CANARY}"; then
  conclude
  printf '降權沒生效：允許目錄只給了 %s，它還是把 %s 讀出來了。\n' "${NARROW}" "${TARGET}"
  printf '設定改了不等於範圍收窄了。去看那台是不是還吃著舊的允許目錄。離開碼 1。\n'
  exit 1
fi

if [ "${verdict}" != "VERDICT=TOOLERR" ]; then
  conclude
  printf '探針壞了：收窄那一輪連問都沒問成（%s），不是被拒絕。\n' "${verdict}"
  printf '沒讀到不代表擋住了，這一輪一樣沒有結論。離開碼 3。\n'
  exit 3
fi

conclude
printf '收窄生效：同一個呼叫被擋下來了，而且上面那句拒絕的原文是 server 自己講的。\n'
printf '兩步都符合預期。離開碼 0。\n'
