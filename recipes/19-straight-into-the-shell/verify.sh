#!/usr/bin/env bash
# 這一份自己的檢查。一發真模型都不打。
#
#   bash verify.sh        # 全部
#   bash verify.sh 3      # 只跑第 3 條
#
# 每一條問自己那句話：把行為弄壞（不是把字改掉），這條會不會沒過？
# 證明它們真的會沒過：bash mutations.sh
set -u
cd "$(dirname "$0")"
ONLY="${1:-}"
command -v node >/dev/null || { echo "這份要 Node 才能跑，先裝 Node 再來。"; exit 2; }

PASS=0; FAIL=0
case_() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  通過   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  沒過   %s\n' "$1"; FAIL=$((FAIL+1)); }
want() { [ -z "${ONLY}" ] || [ "${ONLY}" = "$1" ]; }

RUN=runs/2026-08-18b
TSV=${RUN}/results.tsv
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
TAB=$(printf '\t')
# awk 不用在這裡：macOS 的 awk 拿中文當 -v 的值時，`$1==k` 每一列都成立，
# 於是 field 回傳整份輸出而檢查照樣有的通過有的沒過（8/18 撞到，第 1 到 5 條全假）。
field() { node probe.mjs "$1" | grep -F "$2${TAB}" | cut -f2; }

# ── 1 基線：原版真的打得穿，而且是那兩條打得穿 ────────────────
# 這是整天的起點。分號那條打不穿，因為原版加了雙引號，引號有效，只是不夠。
if want 1; then
  case_ "1 vuln.mjs：subst 與 backtick 打得穿，sep 打不穿"
  H=$(field vuln.mjs 打得穿的)
  V=$(field vuln.mjs 判定)
  [ "${H}" = "subst,backtick" ] && ok "打得穿的是 ${H}" || bad "打得穿的是 ${H}，期望 subst,backtick"
  [ "${V}" = "vuln" ] && ok "判定 vuln" || bad "判定是 ${V}"
fi

# ── 2 對照組：參數陣列那版三條都打不穿，功能還在 ───────────────
if want 2; then
  case_ "2 fixed.mjs：判定 pass"
  H=$(field fixed.mjs 打得穿的)
  B=$(field fixed.mjs 無害輸入)
  [ "${H}" = "無" ] && ok "沒有打得穿的" || bad "居然打得穿 ${H}"
  [ "${B}" = "ok" ] && ok "無害輸入還是回 dump emulator-5554" || bad "無害輸入 ${B}"
fi

# ── 3 判準的第二關：擋住了但功能壞掉，不算過 ──────────────────
# 沒有這一關的話，「把整個函式刪掉」會拿滿分。
if want 3; then
  case_ "3 一律拒絕的版本判成 broken，不是 pass"
  cat > "${TMP}/refuse.mjs" <<'EOF'
export function inspectDevice() {
  throw new Error("nope");
}
EOF
  V=$(field "${TMP}/refuse.mjs" 判定)
  [ "${V}" = "broken" ] && ok "判定 broken" || bad "判定是 ${V}，期望 broken"
fi

# ── 4 載不進來的東西要跟「修好了」分得開 ────────────────────
if want 4; then
  case_ "4 沒有 inspectDevice 的檔案判成 unusable"
  echo "這不是程式碼，是模型的說明文字。" > "${TMP}/prose.mjs"
  V=$(field "${TMP}/prose.mjs" 判定)
  [ "${V}" = "unusable" ] && ok "判定 unusable" || bad "判定是 ${V}，期望 unusable"
fi

# ── 5 黑名單清字元那種修法，讀起來像修好了 ───────────────────
# 這正是 SPEC 那句「錯的方式往往看起來像對的」。假模型吐的就是這一版。
if want 5; then
  case_ "5 清掉 ; & | 反引號的版本仍然被 subst 打穿"
  cat > "${TMP}/blacklist.mjs" <<'EOF'
import { execSync } from "node:child_process";
export function inspectDevice(device) {
  const safe = String(device).replace(/[;&|`]/g, "");
  return execSync(`echo "dump ${safe}"`, { encoding: "utf8" }).trim();
}
EOF
  H=$(field "${TMP}/blacklist.mjs" 打得穿的)
  [ "${H}" = "subst" ] && ok "打得穿的是 ${H}" || bad "打得穿的是 ${H}，期望 subst"
fi

# ── 6 payload 只 touch，不刪東西 ──────────────────────────
# advisory 那條是 rm -rf，這個 recipe 不跑它。
if want 6; then
  case_ "6 攻擊輸入裡沒有刪除類指令"
  if grep -nE 'rm -rf|unlink|shutdown' probe.mjs | grep -v 'rmSync' >/dev/null; then
    bad "probe.mjs 的 payload 有刪除類指令"
  else
    ok "只有 touch"
  fi
fi

# ── 7 暫存目錄收得乾淨 ─────────────────────────────────
if want 7; then
  case_ "7 跑完不留暫存目錄"
  node probe.mjs vuln.mjs >/dev/null
  LEFT=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'shell-probe-*' 2>/dev/null | wc -l | tr -d ' ')
  [ "${LEFT}" = "0" ] && ok "沒有殘留" || bad "留了 ${LEFT} 個 shell-probe-*"
fi

# ── 8 整條流程跑得動（假模型，不花錢）────────────────────────
if want 8; then
  case_ "8 run-suite 用假模型跑得完，欄位對得上"
  MODEL_CMD='bash stub-model.sh' N=1 OUT="${TMP}/smoke" ARMS='plain withtests' node run-suite.mjs >/dev/null 2>&1
  ROWS=$(( $(wc -l < "${TMP}/smoke/results.tsv") - 1 ))
  COLS=$(head -1 "${TMP}/smoke/results.tsv" | awk -F'\t' '{print NF}')
  FIXES=$(ls "${TMP}/smoke/fixes" | wc -l | tr -d ' ')
  [ "${ROWS}" = "2" ] && ok "2 列" || bad "${ROWS} 列，期望 2"
  [ "${COLS}" = "6" ] && ok "6 欄" || bad "${COLS} 欄，期望 6"
  [ "${FIXES}" = "2" ] && ok "留檔 2 份" || bad "留檔 ${FIXES} 份，期望 2"
fi

# ── 9 Fisher 在已知的兩組上給得出已知的答案 ──────────────────
# 期望值不從被測程式來：12 對 0 的 2x2，Fisher 雙尾 p 是 1/C(24,12) 的兩倍。
if want 9; then
  case_ "9 summarise 的 Fisher 值對得上手算"
  { echo -e "arm\trun\tverdict\thits\tbenign"
    for i in $(seq 1 12); do echo -e "a\t${i}\tvuln\tsubst\tok"; done
    for i in $(seq 1 12); do echo -e "b\t${i}\tpass\t-\tok"; done
  } > "${TMP}/known.tsv"
  P=$(node summarise.mjs "${TMP}/known.tsv" | grep -F "Fisher" | cut -f2)
  # 手算：12 對 0 的 2x2，雙尾就是兩個極端表格，各 1/C(24,12)。C(24,12)=2704156。
  EXPECT="p = 7.40e-7"
  [ "${P}" = "${EXPECT}" ] && ok "${P}" || bad "${P}，手算是 ${EXPECT}"
fi

# ── 10 定案那輪的資料在，而且兩臂各 12 ───────────────────────
if want 10; then
  case_ "10 ${TSV}：兩臂各 12 列"
  if [ ! -f "${TSV}" ]; then
    bad "${TSV} 不在"
  else
    for a in plain withtests; do
      N=$(awk -F'\t' -v a="${a}" 'NR>1 && $1==a' "${TSV}" | wc -l | tr -d ' ')
      [ "${N}" = "12" ] && ok "${a} 12 列" || bad "${a} ${N} 列"
    done
    BAD=$(awk -F'\t' 'NR>1 && $3!="pass" && $3!="vuln" && $3!="noexec" && $3!="broken" && $3!="unusable"' "${TSV}" | wc -l | tr -d ' ')
    [ "${BAD}" = "0" ] && ok "判定欄只有五種值" || bad "有 ${BAD} 列的判定欄不在五種值裡"
    NOEXEC=$(awk -F'\t' 'NR>1 && $3=="noexec"' "${TSV}" | wc -l | tr -d ' ')
    [ "${NOEXEC}" = "5" ] && ok "5 份把子行程拿掉了" || bad "noexec 有 ${NOEXEC} 份，文章寫 5"
  fi
fi

# ── 11 每一份修法都還在，數量對得上 ─────────────────────────
if want 11; then
  case_ "11 fixes/ 的份數等於 TSV 的列數"
  if [ ! -d "${RUN}/fixes" ]; then
    bad "${RUN}/fixes 不在"
  else
    F=$(ls "${RUN}/fixes" | wc -l | tr -d ' ')
    R=$(( $(wc -l < "${TSV}") - 1 ))
    [ "${F}" = "${R}" ] && ok "各 ${F} 份" || bad "留檔 ${F} 份，TSV ${R} 列"
  fi
fi

# ── 12 第三關：把子行程整個拿掉的版本要跟 pass 分得開 ───────────
# 前兩關都過得了：沒有標記檔、無害輸入也回對的字串。差別只在它根本沒去開那個指令。
if want 12; then
  case_ "12 直接回傳字串的版本判成 noexec"
  cat > "${TMP}/noexec.mjs" <<'EOF'
export function inspectDevice(device) {
  return `dump ${device}`;
}
EOF
  V=$(field "${TMP}/noexec.mjs" 判定)
  S=$(field "${TMP}/noexec.mjs" 有開外部指令)
  [ "${V}" = "noexec" ] && ok "判定 noexec" || bad "判定是 ${V}，期望 noexec"
  [ "${S}" = "沒有" ] && ok "確實沒開外部指令" || bad "居然是 ${S}"
  S2=$(field fixed.mjs 有開外部指令)
  [ "${S2}" = "有" ] && ok "對照組 fixed.mjs 有開" || bad "對照組是 ${S2}，這一關的偵測本身壞了"
fi

# ── 13 那 5 份 noexec 真的一個子行程都沒開 ─────────────────
# 第三關（PATH 插假指令）只給得出上界：它對絕對路徑與 shell 內建會漏記。
# 文章敢把 5 當確數，靠的是逐份看過檔案，那句話要有東西可以指，就是這一條。
if want 13; then
  case_ "13 判成 noexec 的那幾份，檔案裡真的沒有任何子行程呼叫"
  if [ ! -d "${RUN}/fixes" ]; then
    bad "${RUN}/fixes 不在"
  else
    N=$(awk -F'\t' 'NR>1 && $3=="noexec" {printf "%s-%02d.mjs\n", $1, $2}' "${TSV}")
    CNT=$(printf '%s\n' "${N}" | grep -c . || true)
    BAD=""
    for f in ${N}; do
      grep -qE 'child_process|execFile|execSync|spawn|/bin/' "${RUN}/fixes/${f}" && BAD="${BAD} ${f}"
    done
    # 反向：判成 pass 的那些必須有子行程呼叫，不然這條檢查對誰都成立
    P=$(awk -F'\t' 'NR>1 && $3=="pass" {printf "%s-%02d.mjs\n", $1, $2}' "${TSV}")
    NOCALL=""
    for f in ${P}; do
      grep -qE 'child_process' "${RUN}/fixes/${f}" || NOCALL="${NOCALL} ${f}"
    done
    [ -z "${BAD}" ] && ok "${CNT} 份 noexec 都沒有子行程呼叫" || bad "這幾份其實有呼叫：${BAD}"
    [ -z "${NOCALL}" ] && ok "判成 pass 的那些都有 child_process" || bad "判 pass 卻沒有呼叫：${NOCALL}"
  fi
fi

printf '\n通過 %d，沒過 %d\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = "0" ]
