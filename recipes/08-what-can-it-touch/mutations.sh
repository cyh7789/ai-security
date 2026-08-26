#!/usr/bin/env bash
# 故障注入：把腳本弄壞，看 verify.sh 會不會發現。
#
# 這一份自己說「憑證不會外流」「描述不會截斷」「降權真的生效」，
# 而這三句話都只能用同一種方法證明：故意讓它們不成立，看驗證會不會判沒過。
# 不會沒過的那條檢查沒有價值。
#
# 這支不會動到你的檔案：每一種突變都複製到 mktemp -d 裡改，跑完刪掉。
#
#   bash mutations.sh      全部
#   bash mutations.sh 3    只跑第 3 種

set -u
ONLY="${1:-}"
HERE=$(cd "$(dirname "$0")" && pwd)
PASS=0; FAIL=0; UNTESTED=0; N=0; RAN=0

# 編號打錯的話每一種都被跳過，收尾算出「抓到 0 種 / 漏掉 0 種」然後結束碼 0。
# 一份專門用來證明「這裡沒有假通過」的工具，自己就不能有這種形狀。
case "${ONLY}" in
  '') ;;
  *[!0-9]*) printf '種類編號要是數字，收到的是「%s」。\n' "${ONLY}" >&2; exit 2 ;;
esac

# run_case <說明> <節> <要改哪個檔> <perl 運算式>...
run_case() {
  N=$((N+1))
  desc=$1; sect=$2; file=$3; shift 3
  if [ -n "${ONLY}" ] && [ "${ONLY}" != "${N}" ]; then return 0; fi
  RAN=$((RAN+1))
  WS=$(mktemp -d)
  cp "${HERE}"/*.sh "${HERE}"/*.cjs "${WS}"/ 2>/dev/null
  cp -R "${HERE}/demo" "${WS}/demo" 2>/dev/null
  for e in "$@"; do
    perl -0pi -e "${e}" "${WS}/${file}" || {
      printf '  第 %s 種：突變寫不進去\n' "${N}"; rm -rf "${WS}"; FAIL=$((FAIL+1)); return; }
  done
  if cmp -s "${HERE}/${file}" "${WS}/${file}"; then
    printf '  [無效] %-42s 突變沒改到任何一個字，這一條什麼都沒驗到\n' "${desc}"
    rm -rf "${WS}"; FAIL=$((FAIL+1)); return
  fi
  OUT=$(cd "${WS}" && bash verify.sh "${sect}" 2>&1)
  REDS=$(printf '%s' "${OUT}" | grep -c '^  沒過')
  SKIPS=$(printf '%s' "${OUT}" | grep -c '^  沒有結論')
  if [ "${REDS}" -gt 0 ]; then
    printf '  [抓到] %-42s 第 %s 節 %s 個沒過\n' "${desc}" "${sect}" "${REDS}"
    PASS=$((PASS+1))
  elif [ "${SKIPS}" -gt 0 ]; then
    # 那一節整節被跳過（沒 node、抓不到 filesystem server），沒有一條沒過，不代表突變沒被抓到。
    # 算成漏掉會冤枉它，算成抓到就是這支自己在造出假通過。兩個都不對，所以單獨報。
    printf '  [沒有結論] %-38s 第 %s 節整節跳過：%s\n' "${desc}" "${sect}" \
      "$(printf '%s' "${OUT}" | grep -m1 '^  沒有結論' | sed 's/^ *沒有結論 *//')"
    UNTESTED=$((UNTESTED+1))
  else
    printf '  [漏掉] %-42s 第 %s 節 全部通過，這是假通過\n' "${desc}" "${sect}"
    printf '%s\n' "${OUT}" | sed 's/^/         /'
    FAIL=$((FAIL+1))
  fi
  rm -rf "${WS}"
}

printf '\n每一種都應該被抓到。有一個「漏掉」或「無效」就代表那條檢查沒有鑑別力。\n\n'

# 憑證是這一份最不能失手的地方，先打它
run_case '把值跟著變數名一起印出來'          1 mcp-config.cjs \
  's{if \(!refs\.length\) return \{ kind: "literal", shown: "\*\*\*" \};}{if (!refs.length) return \{ kind: "literal", shown: s \};}'
run_case '任何像路徑的參數都當成權限範圍'      1 mcp-config.cjs \
  's{  const known = KNOWN_SCOPE_ARGS\.find\(\(k\) => all\.some\(\(a\) => k\.match\.test\(a\)\)\);}{  const known = true;}' \
  's{  const pos = positionalPaths\(all\);}{  const pos = argPaths;}'
run_case '執行檔路徑也算進允許目錄'            1 mcp-config.cjs \
  's{      const i = args\.findIndex\(\(a\) => FS_PKG\.test\(String\(a\)\)\);\n      if \(i < 0\) return \[\];\n      return args\.slice\(i \+ 1\)}{      const i = -1;\n      if (false) return [];\n      return [command].concat(args)}'
run_case '認得的 server 也一律印 unknown'       1 mcp-config.cjs \
  's{const KNOWN_SCOPE_ARGS = \[}{const KNOWN_SCOPE_ARGS = []; const _UNUSED = [}'
run_case 'headers 底下的憑證不看'            1 mcp-config.cjs \
  's{\n  take\(s\.headers\);}{}'
run_case 'args 裡的 NAME=值 不算宣告變數'     1 mcp-config.cjs \
  's{if \(m\) vars\.push\(declare\(m\[1\], m\[2\]\)\);}{if (false) vars.push(declare(m[1], m[2]));}'
run_case '憑證樣式改成大小寫敏感'             1 mcp-config.cjs \
  's{const looksLikeCred = \(name\) => CRED\.test\(name\);}{const looksLikeCred = (name) => /(TOKEN|SECRET|API_KEY)/.test(name);}'
run_case '每一台的憑證欄都印 ***'             1 mcp-config.cjs \
  's{: "no"\);}{: "***");}'
run_case '遠端那台的憑證欄印 no 不印 ?'       1 mcp-config.cjs \
  's{        credUnknown: true,}{        credUnknown: false,}'

# 來源涵蓋範圍
run_case '只讀全域，不讀專案底下的設定'        1 mcp-config.cjs \
  's{^  const projects = j\.projects.*?\n  \}\n}{}ms'
run_case '專案路徑整條印出來'                 1 mcp-config.cjs \
  's{"proj:" \+ path\.basename\(String\(proj\)\.replace\(/\\/\+\$/, ""\)\)}{"proj:" + String(proj)}'
run_case '允許目錄是 / 的時候收斂成空字串'     1 mcp-config.cjs \
  's{  if \(s === "" \|\| s === "/"\) return "/ \(whole machine\)";\n}{}'

# 專案範圍那一路。這一組打的是上一版真的漏掉的東西：只讀 ~/.claude.json
# 就下「這台機器上沒有任何一台帶 -e」的結論，而 .mcp.json 裡就有一台。
run_case '只讀 ~/.claude.json，不讀 .mcp.json'  5 inventory.sh \
  's{^ROWS=\$\(printf.*\n}{}m'
run_case '把 \${VAR} 展開成真值'               5 mcp-config.cjs \
  's{return \{ kind: "var", shown: refs\.join\(""\) \};}{return \{ kind: "var", shown: refs.map((r) => process.env[r.slice(2, -1)] || r).join("") \};}'
run_case '明文跟用變數的混為一談'              5 mcp-config.cjs \
  's{  if \(creds\.some\(\(v\) => v\.kind === "literal"\)\) flags\.push\("credliteral"\);}{  if (creds.length) flags.push("credliteral");}'
run_case '解不開的 .mcp.json 當成那個專案沒裝'  5 mcp-config.cjs \
  's{^      broken\.push\(proj\);\n}{}m'
run_case '收尾點名只印名字，不印是哪個來源'     7 mcp-config.cjs \
  's{  const at = \(r\) => r\[0\] \+ "/" \+ r\[3\];}{  const at = (r) => r[3];}'

# inventory.sh 的唯讀與結束碼
run_case '設定檔讀不到也照樣印一張空表'        1 inventory.sh \
  's{if \[ ! -r "\$\{CFG\}" \]; then}{if false; then}'
run_case '清點的時候順手寫一個快取檔'          1 inventory.sh \
  's{^ROWS=\$\(node}{touch "\$\{HOME\}/.inventory-cache"\nROWS=\$(node}m'

# 描述那一條資料路徑
run_case '描述截斷到 80 字元'                 2 mcp-rpc.cjs \
  's{t\.description : "";}{t.description.slice(0, 80) : "";}'
run_case '描述只印第一行'                     2 mcp-rpc.cjs \
  's{t\.description : "";}{t.description.split("\\n")[0] : "";}'
run_case '字元數拿工具名的長度來算'            2 mcp-rpc.cjs \
  's{const chars = Array\.from\(desc\)\.length;}{const chars = Array.from(t.name).length;}'
run_case '總計的字元數另外算一個'              2 mcp-rpc.cjs \
  's{"\\t" \+ total \+ "\\n"}{"\\t" + (total + 7) + "\\n"}'
run_case 'server 起不來也回結束碼 0'          2 list-tools.sh \
  's{if \[ "\$\{rc\}" != 0 \]; then}{if false; then}'
# 這一條的 perl 運算式不能用 \Q...\E 包 ${HERE}：\Q 只擋 regex 元字元，
# perl 照樣會把 ${HERE} 當成自己的變數展開成空字串，於是整條樣式對不上任何東西，
# 而 run_case 會把它報成「無效」。所以 $ 跟 { } 是手動轉義的。
run_case '回印讀者的指令時不遮蔽'              2 list-tools.sh \
  's{ \| node "\$\{HERE\}/mcp-config\.cjs" mask\)}{)}'

# 掃描器
run_case '命中了也回結束碼 0'                 3 desc-scan.cjs \
  's{  process\.exitCode = 1;}{  process.exitCode = 0;}'
run_case '乾淨的也回結束碼 1'                 3 desc-scan.cjs \
  's{    process\.exitCode = 0;}{    process.exitCode = 1;}'
run_case '樣式改成大小寫敏感'                 3 desc-scan.cjs \
  's{new RegExp\(r, "i"\)}{new RegExp(r)}'
run_case '拿掉「隱瞞」那一類樣式'              3 desc-scan.cjs \
  's{^  \["隱瞞".*\n}{}m'
run_case '拿掉「路徑」那一類樣式'              3 desc-scan.cjs \
  's{^  \["路徑".*\n}{}m'
run_case '抓到第一條就收工'                   3 desc-scan.cjs \
  's{      hits\.push\(\[where\(i\), g, found\[0\], around\]\);}{      if (!hits.length) hits.push([where(i), g, found[0], around]);}'
run_case '沒問到當成乾淨'                     3 scan-descriptions.sh \
  's{  printf .沒問到就沒有掃到，結束碼 2。這不是「乾淨」。\\n.\n  exit 2}{  exit 0}'

# 樣式表只有一份，所以拿掉一類的時候，MCP 那一路跟 --files 那一路要一起沒過。
# 兩份寫的話，補了一邊漏了另一邊，而畫面上只會看到一邊變成通過。
run_case '拿掉「標籤」那一類樣式（掃指示檔那一路）' 6 desc-scan.cjs \
  's{^  \["標籤".*\n}{}m'
run_case '掃指示檔的時候不點出是哪一個檔'      6 desc-scan.cjs \
  's{f \+ ":" \+ \(i \+ 1\)}{"(某個指示檔)"}'
run_case '路徑底下沒有 markdown 也回結束碼 0'  6 desc-scan.cjs \
  's{  if \(!files\.length\) \{}{  if (false) \{}'

# 探針
run_case 'PROBE_ROOT 的 /tmp 守衛拿掉'        4 probe.sh \
  's{^case "\$\{ROOT\}" in\n.*?\nesac\n}{}ms'
run_case '前置條件不檢查工具在不在'            4 probe.sh \
  's{^for t in node npx curl; do\n.*?\ndone\n}{}ms'
run_case '連不到外網也照樣往下跑'              4 probe.sh \
  's{if \[ "\$\{code\}" != "200" \]; then}{if false; then}'
run_case '不做正對照，直接看收窄那一輪'        4 probe.sh \
  's{^if ! printf .%s. "\$\{body\}" \| grep -q "\$\{CANARY\}"; then\n.*?\nfi\n}{}ms'
run_case '探針壞了跟降權沒生效共用同一個結束碼' 4 probe.sh \
  's{先修環境（npx 抓不到套件、允許目錄給錯、檔案沒建起來都會走到這裡）。結束碼 3。\\n.\n  exit 3}{先修環境。結束碼 1。\\n\x27\n  exit 1}'
run_case '收窄那一輪只看 VERDICT，不看記號字串' 4 probe.sh \
  's{^if printf .%s. "\$\{body\}" \| grep -q "\$\{CANARY\}"; then$}{if [ "\$\{verdict\}" = "VERDICT=RPCERR" ]; then}m'
run_case '跑完不清 /tmp/mcp-probe'            4 probe.sh \
  's{^trap cleanup EXIT$}{}m'
# 只換掉第一句是不夠的：第二句還在，兩邊的差集就還是非空，檢查照樣通過。
# 這一條要把降權那一段整個換成探針壞了那一段，兩種失敗才真的講同一組話。
run_case '兩種失敗講同一句話'                 4 probe.sh \
  's{  printf \x27降權沒生效：.*?結束碼 1。\\n\x27\n}{  printf \x27探針壞了：寬範圍也讀不到那個記號字串。\\n\x27\n  printf \x27這一輪沒有驗到「收窄有沒有效」：寬的讀不到，窄的當然也讀不到，第 3 步會假通過。\\n\x27\n  printf \x27先修環境（npx 抓不到套件、允許目錄給錯、檔案沒建起來都會走到這裡）。結束碼 3。\\n\x27\n}s'

# 兩種前置失敗都回 2，訊息一樣的話讀者不知道要裝東西還是修網路。
# 這一條把「連不到」那段換成「沒有 npx」那段，兩邊的結論就一字不差。
run_case '兩種前置失敗講同一句話'            4 probe.sh \
  's{  printf \x27前置條件不到位：問不到 %s（HTTP %s）。\\n\x27 "\$\{REGISTRY\}" "\$\{code\}"\n  printf \x27npx 抓不到 filesystem server 就起不了探針，這一輪什麼都沒驗到。結束碼 2。\\n\x27\n}{  printf \x27前置條件不到位：沒有 npx。\\n\x27\n  printf \x27這支要用 npx 抓 filesystem server、用 curl 量連不連得到外網，缺一個就什麼都沒驗到。結束碼 2。\\n\x27\n}'

# 這裡數的是「跑了幾種」，不是把結果加起來。加總的版本每多一種結果分類就要記得
# 回來改一次，而漏改的後果正好是這支要抓的形狀：某一種明明跑了、只是這台機器
# 測不到，收尾卻回頭說「沒有第 N 種」，同一輪輸出前後打架。
if [ "${RAN}" -eq 0 ]; then
  printf '\n一種突變都沒跑到。%s可用的是 1 到 %s，或不給參數跑全部。\n' \
    "$([ -n "${ONLY}" ] && printf '沒有第 %s 種，' "${ONLY}")" "${N}" >&2
  exit 2
fi

printf '\n════════ 抓到 %s 種 / 漏掉 %s 種 / 沒有結論 %s 種 ════════\n' "${PASS}" "${FAIL}" "${UNTESTED}"
[ "${UNTESTED}" = 0 ] || printf '沒有結論的那幾種不要當成通過。\n'
[ "${FAIL}" = 0 ] && [ "${UNTESTED}" = 0 ]
