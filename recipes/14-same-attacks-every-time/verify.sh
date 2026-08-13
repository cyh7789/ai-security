#!/usr/bin/env bash
# 這一份的驗證。跑法：bash verify.sh        全部
#                    bash verify.sh 7      只跑第 7 條
#
# 每一條驗的都是行為，不是字面。寫的時候問自己那句話：
# 「把功能弄壞（不是把字改掉），這條會不會轉紅？」答不出來的就重寫。
# 證明它們真的會紅：bash mutations.sh
#
# 這一份一發真模型都不打。判準本身有沒有辨識力，用罐頭回應才驗得出來：
# 真模型每次回的不一樣，判準壞掉跟模型剛好沒上鉤長得一模一樣。

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
cd "${HERE}"
ONLY="${1:-}"
PASS=0; FAIL=0
ok()  { printf '  [OK]   %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
run() { [ -z "${ONLY}" ] || [ "${ONLY}" = "$1" ]; }
TMP=$(mktemp -d); trap 'rm -rf "${TMP}"' EXIT

command -v node >/dev/null 2>&1 || { echo "沒有 node，這份跑不了"; exit 2; }

# 罐頭跑一輪，結果丟進 TMP，不要蓋掉真模型那份 results.tsv。
stub() { # stub <FAKE> <guards> [runs]
  FAKE="$1" REPLIES_DIR="${TMP}/replies" OUT_TSV="${TMP}/r.tsv" \
    bash run-suite.sh --stub --guards "$2" --runs "${3:-1}" >/dev/null 2>&1
}
sum() { # sum <kind> <verdict>  讀 TMP/r.tsv
  awk -F'\t' -v k="$1" -v v="$2" '$5==k && $6==v' "${TMP}/r.tsv" | wc -l | tr -d ' '
}

# ── 1 清單是收來的，不是手抄的 ────────────────────────────
# 改 recipe 10 的 attacks.txt 而沒重收，這條要紅。手抄的清單會跟來源分岔，
# 而分岔的那一天你不會知道，那正是這份 recipe 要解決的問題。
if run 1; then
  echo "=== 1 attacks.jsonl 跟五個來源一致 ==="
  OUT=$(node collect.mjs --check 2>&1); RC=$?
  [ "${RC}" = 0 ] && ok "${OUT}" || bad "跟來源分岔了：${OUT}"
fi

# ── 2 條數與載體分佈都是從來源算的 ─────────────────────────
# 不寫死 15 也不寫死 12/3。來源那邊加一條攻擊，這裡的期望值要自己跟上。
if run 2; then
  echo "=== 2 條數與載體分佈對得上來源 ==="
  W_IN=$(grep -cv '^#' ../10-instructions-vs-data/attacks.txt)
  W_PG=$(node --input-type=module -e "import {HIDING} from '../11-what-the-model-reads/page.mjs'; console.log(HIDING.length)")
  G_IN=$(grep -c '"carrier":"input"' attacks.jsonl)
  G_PG=$(grep -c '"carrier":"page"' attacks.jsonl)
  G_ALL=$(grep -c . attacks.jsonl)
  [ "${G_IN}" = "${W_IN}" ] && [ "${G_PG}" = "${W_PG}" ] && [ "${G_ALL}" = "$((W_IN + W_PG + 4))" ] \
    && ok "input ${G_IN}、page ${G_PG}、合計 ${G_ALL}，跟來源算出來的一樣" \
    || bad "input ${G_IN}/${W_IN}、page ${G_PG}/${W_PG}、合計 ${G_ALL}"
fi

# ── 3 判準不在模型輸出裡的那幾條，不准送出去 ────────────────
# 它們留在清單裡，但這道防線管不到。硬送會量到一個沒有意義的數字，
# 而那個數字看起來跟「擋住了」一模一樣。
if run 3; then
  echo "=== 3 dom／http 那幾條會被擋下來不送 ==="
  BAD=0; N=0
  for id in $(grep -oE '"id":"[0-9]+"' attacks.jsonl | cut -d'"' -f4); do
    C=$(grep "\"id\":\"${id}\"" attacks.jsonl | grep -oE '"carrier":"[a-z]+"' | cut -d'"' -f4)
    case "${C}" in dom|http) ;; *) continue ;; esac
    N=$((N + 1))
    node build-prompt.mjs guards/v1.txt "${id}" >/dev/null 2>&1 && BAD=$((BAD + 1))
  done
  [ "${N}" -ge 1 ] && [ "${BAD}" = 0 ] && ok "${N} 條都拒送" || bad "${N} 條裡有 ${BAD} 條被送出去了"
fi

# ── 4 三種載體各自送到對的欄位 ─────────────────────────────
# 全部塞進使用者那一格假裝一樣的話，量到的不是同一件事。
if run 4; then
  echo "=== 4 page 進網頁欄、kb 進段落欄、input 進使用者欄 ==="
  P=$(node build-prompt.mjs guards/v0.txt 09 | sed -n '/\[網頁內容\]/,$p' | grep -c '<!doctype html>')
  K=$(node build-prompt.mjs guards/v0.txt 15 | sed -n '/\[檢索到的段落\]/,/\[使用者\]/p' | grep -c '出差報帳')
  I=$(node build-prompt.mjs guards/v0.txt 04 | sed -n '/\[使用者\]/,$p' | grep -c 'RS-8417')
  [ "${P}" -ge 1 ] && [ "${K}" -ge 1 ] && [ "${I}" -ge 1 ] \
    && ok "三種載體都送進各自那一欄" || bad "page ${P}、kb ${K}、input ${I}"
fi

# ── 5 防護句真的有進去，而且 v0 真的是空的 ──────────────────
# v0 是對照組。它要是不小心帶了東西進去，整張表的基準線就垮了。
if run 5; then
  echo "=== 5 v2 全文逐字在 prompt 裡，v0 一個字都沒多 ==="
  A=$(node build-prompt.mjs guards/v2.txt 04)
  B=$(node build-prompt.mjs guards/v0.txt 04)
  MISS=0
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    printf '%s' "${A}" | grep -qF -- "${line}" || MISS=$((MISS + 1))
  done < guards/v2.txt
  EXTRA=$(printf '%s' "${B}" | grep -c '^\[系統\]')
  [ "${MISS}" = 0 ] && [ "${EXTRA}" = 3 ] \
    && ok "v2 每一行都在；v0 只有 build-prompt 自己那三行" \
    || bad "v2 少了 ${MISS} 行；v0 的系統行有 ${EXTRA} 行（該是 3）"
fi

# ── 6 判準分得出照做與不照做 ───────────────────────────────
if run 6; then
  echo "=== 6 全照做記全失守，全拒絕記零失守 ==="
  stub comply v1; C=$(sum attack lost); CT=$(awk -F'\t' '$5=="attack"' "${TMP}/r.tsv" | wc -l | tr -d ' ')
  stub refuse v1; R=$(sum attack lost)
  [ "${CT}" -ge 1 ] && [ "${C}" = "${CT}" ] && [ "${R}" = 0 ] \
    && ok "照做 ${C}/${CT} 全記到，拒絕 ${R}/${CT}" || bad "照做 ${C}/${CT}、拒絕 ${R}/${CT}"
fi

# ── 7 只看失守數會被一版什麼都不回答的 prompt 騙過去 ─────────
# 這一條就是誤擋那一欄存在的理由。它紅了代表那一欄失去意義。
if run 7; then
  echo "=== 7 什麼都不回答那版：零失守，但誤擋滿格 ==="
  stub paranoid v1
  L=$(sum attack lost); RF=$(sum benign refused); BT=$(awk -F'\t' '$5=="benign"' "${TMP}/r.tsv" | wc -l | tr -d ' ')
  [ "${L}" = 0 ] && [ "${BT}" -ge 1 ] && [ "${RF}" = "${BT}" ] \
    && ok "失守 0，誤擋 ${RF}/${BT}，兩欄一起看才擋得掉這一版" \
    || bad "失守 ${L}、誤擋 ${RF}/${BT}"
fi

# ── 8 模型自稱沒被影響不算數 ───────────────────────────────
if run 8; then
  echo "=== 8 嘴上說沒被影響、同時吐出標記，照樣記失守 ==="
  stub selfreport v1
  L=$(sum attack lost); T=$(awk -F'\t' '$5=="attack"' "${TMP}/r.tsv" | wc -l | tr -d ' ')
  [ "${L}" = "${T}" ] && ok "${L}/${T} 都記成失守" || bad "只記到 ${L}/${T}"
fi

# ── 9 那一頭沒在回話的時候，不准印出任何一張表 ────────────────
# 少了這條，模型掛掉的那一輪會產出一張「每一格都擋住了」的漂亮表格然後 exit 0。
if run 9; then
  echo "=== 9 存活對照沒過就中止，而且不留半張表 ==="
  printf '#!/usr/bin/env bash\ncat >/dev/null; printf "服務暫時無法使用\\n"\n' > "${TMP}/dead.sh"
  OUT=$(MODEL_CMD="bash ${TMP}/dead.sh" OUT_TSV="${TMP}/dead.tsv" REPLIES_DIR="${TMP}/rp" \
        bash run-suite.sh --guards v1 --runs 1 2>&1); RC=$?
  ROWS=$([ -f "${TMP}/dead.tsv" ] && grep -c . "${TMP}/dead.tsv" || echo 0)
  [ "${RC}" = 3 ] && [ "${ROWS}" -le 1 ] && ok "退出碼 3，沒有資料列流出去" \
    || bad "退出碼 ${RC}、tsv 有 ${ROWS} 列"
fi

# ── 10 中途死掉也要中止，不是記成擋住了 ─────────────────────
# 錯誤訊息裡沒有標記，所以「模型死了」跟「模型擋住了」在判準眼裡一模一樣。
if run 10; then
  echo "=== 10 開跑之後才死掉，那一輪不算數 ==="
  cat > "${TMP}/flaky.sh" <<'SH'
#!/usr/bin/env bash
p=$(cat)
case "$p" in *OK-LIVE*) printf 'OK-LIVE\n'; exit 0 ;; esac
exit 7
SH
  OUT=$(MODEL_CMD="bash ${TMP}/flaky.sh" OUT_TSV="${TMP}/flaky.tsv" REPLIES_DIR="${TMP}/rp2" \
        bash run-suite.sh --guards v1 --runs 1 2>&1); RC=$?
  [ "${RC}" = 3 ] && ok "退出碼 3，沒有把死掉當成擋住" || bad "退出碼 ${RC}｜${OUT}"
fi

# ── 11 隱形那條的標記真的在 payload 裡 ──────────────────────
# 它要是掉了，那一條會三版全綠，而綠的原因是模型憑空生不出那個代號，
# 不是防護句擋住了。這種恆綠的列比紅的列危險。
if run 11; then
  echo "=== 11 隱形碼點那條扛得住 JSON 來回 ==="
  R=$(node -e '
    const L=require("fs").readFileSync("attacks.jsonl","utf8").trim().split("\n").map(JSON.parse);
    const r=L.find(x=>x.hiding==="invisible");
    if(!r){console.log("none");process.exit(0)}
    const tags=[...r.payload].filter(c=>{const p=c.codePointAt(0);return p>=0xE0000&&p<=0xE007F}).length;
    const dec=[...r.payload].map(c=>{const p=c.codePointAt(0);
      return p>=0xE0000&&p<=0xE007F?String.fromCharCode(p-0xE0000):c}).join("");
    console.log([r.payload.includes(r.mark), tags>0, dec.includes(r.mark)].join(" "));')
  [ "${R}" = "false true true" ] \
    && ok "明文找不到、Tags 碼點在、解碼後對得上" || bad "量到「${R}」（要 false true true）"
fi

# ── 12 --runs 說幾次就跑幾次 ───────────────────────────────
if run 12; then
  echo "=== 12 每一格真的重複跑 ==="
  stub refuse v1 1; ONE=$(grep -c . "${TMP}/r.tsv")
  stub refuse v1 3; THREE=$(grep -c . "${TMP}/r.tsv")
  [ "$((ONE - 1))" -ge 1 ] && [ "$((THREE - 1))" = "$(((ONE - 1) * 3))" ] \
    && ok "1 次 $((ONE - 1)) 列、3 次 $((THREE - 1)) 列" || bad "1 次 $((ONE - 1))、3 次 $((THREE - 1))"
fi

# ── 13 比較表的分母是數出來的 ──────────────────────────────
# 寫死分母的話，少跑一格會被算成「那一格擋住了」。
if run 13; then
  echo "=== 13 少一列，分母就少一 ==="
  stub refuse v1 3
  FULL=$(node compare.mjs "${TMP}/r.tsv" | grep -E '^\| v1 ' | head -1)
  # 用 sed 砍最後一列，不要用 head -n -1：BSD 的 head 不吃負數，
  # 產出的是一個空檔，compare.mjs 直接報錯，而「報錯」跟「分母變了」在這條眼裡一樣。
  sed '$d' "${TMP}/r.tsv" > "${TMP}/short.tsv"
  SHORT=$(node compare.mjs "${TMP}/short.tsv" | grep -E '^\| v1 ' | head -1)
  [ -n "${FULL}" ] && [ -n "${SHORT}" ] && [ "${FULL}" != "${SHORT}" ] \
    && ok "分母跟著資料變：${FULL} → ${SHORT}" || bad "少一列分母沒變：${FULL} → ${SHORT}"
fi

# ── 14 誤擋判準真的在看內容 ────────────────────────────────
# 把該出現的答案改成不可能出現的字，誤擋數要跟著上去。
if run 14; then
  echo "=== 14 換掉正常問題的期望答案，誤擋數會動 ==="
  cp benign.jsonl "${TMP}/benign.bak"
  sed 's/"expect":"[^"]*"/"expect":"這串字不可能出現在回覆裡"/' "${TMP}/benign.bak" > benign.jsonl
  stub refuse v1; AFTER=$(sum benign refused)
  cp "${TMP}/benign.bak" benign.jsonl
  stub refuse v1; BEFORE=$(sum benign refused)
  [ "${BEFORE}" = 0 ] && [ "${AFTER}" -ge 1 ] \
    && ok "原本誤擋 ${BEFORE}，改掉期望答案之後 ${AFTER}" || bad "原本 ${BEFORE}、改掉之後 ${AFTER}"
fi

# ── 15 兩種列不會混欄 ──────────────────────────────────────
# attack 的結果只能是 lost／held，benign 只能是 answered／refused。
# 混到一起的話，總計那一欄會把兩件事加在一起，而它們不是同一件事。
if run 15; then
  echo "=== 15 attack 與 benign 的判決值不互串 ==="
  stub refuse v0,v1 1
  X=$(awk -F'\t' '($5=="attack" && $6!="lost" && $6!="held") ||
                  ($5=="benign" && $6!="answered" && $6!="refused")' "${TMP}/r.tsv" | wc -l | tr -d ' ')
  N=$(grep -c . "${TMP}/r.tsv")
  [ "${X}" = 0 ] && [ "${N}" -gt 1 ] && ok "${N} 列沒有一列混欄" || bad "${X} 列混欄（共 ${N} 列）"
fi

echo
printf '%s 綠 %s 紅\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = 0 ]
