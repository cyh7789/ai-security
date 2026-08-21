#!/usr/bin/env bash
# 這一份自己的檢查。一發模型都不打。
#
#   bash verify.sh        # 全部
#   bash verify.sh 3      # 只跑第 3 條
#
# 每一條問自己那句話：把行為弄壞（不是把字改掉），這條會不會轉紅？
set -u
cd "$(dirname "$0")"
ONLY="${1:-}"
command -v node >/dev/null || { echo "這份要 Node 才能跑，先裝 Node 再來。"; exit 2; }

PASS=0; FAIL=0
case_() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  [OK]   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
want() { [ -z "${ONLY}" ] || [ "${ONLY}" = "$1" ]; }

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}" "${HERE_PY}"' EXIT
TAB=$(printf '\t')
# awk 不用在這裡：macOS 的 awk 拿中文當 -v 的值時 `$1==k` 每一列都成立，
# 於是每一條檢查都會拿到整份輸出而且照樣有綠有紅（recipe 19 撞過）。
col() { cut -f"$1"; }
# drift 那張表的欄位取名字不取位置。這支自己就是在講「照欄號取值會讀到別的欄」，
# 8/19 給 drift 加「輸入」欄的時候，第 8、9、16 條同時紅掉，紅的方式一模一樣。
dcol() { python3 "${HERE_PY}" "$1" "$2" "$3"; }
HERE_PY=$(mktemp)
cat > "${HERE_PY}" <<'DCOLPY'
import sys
path, arm, which = sys.argv[1:4]
head = None
for line in open(path, encoding="utf8"):
    p = line.rstrip("\n").split("\t")
    if p[0] == "臂":
        head = p
        continue
    if head and p[0] == arm and len(p) == len(head):
        print(p[head.index(which)])
        break
DCOLPY

JOURNAL_NOW=FIXED node demo.mjs > "${TMP}/demo.out" 2>&1 || { echo "demo.mjs 跑不起來"; cat "${TMP}/demo.out"; exit 2; }
cp journal.tsv "${TMP}/j1.tsv"
# drift.out 在這裡就產生，不留在第 8 條裡面。
# 留在裡面的話，單獨跑第 9、10、16 條會拿到空字串，而空字串餵進 grep 是會通過的
# ——那幾條就變成「不管資料長怎樣都綠」。8/19 寫這支的時候第 16 條就是這樣假綠的。
node drift.mjs > "${TMP}/drift.out"

# ── 1 三筆固定輸入的判決，逐筆對 ──────────────────────────
# 這條顧的是「判斷點還是原本那個判斷點」。任何一道閘的行為變了，這裡先紅。
if want 1; then
  case_ "1 demo 三筆的判決"
  for want_line in \
    "N1|輸入側 allow／SCENARIO_OK|動作側 allow／NOT_DENY_LISTED" \
    "F1|輸入側 deny／SCOPE_BLOCK|動作側 沒走到" \
    "A1|輸入側 allow／SCENARIO_OK|動作側 deny／NO_USER_BASIS"; do
    id=${want_line%%|*}; rest=${want_line#*|}
    a=${rest%%|*}; b=${rest#*|}
    line=$(grep "^${id}${TAB}" "${TMP}/demo.out" || true)
    case "$line" in
      *"$a"*"$b"*) ok "${id} ${a}，${b}" ;;
      *) bad "${id} 這一列是：${line:-（沒有這一列）}" ;;
    esac
  done
fi

# ── 2 放行的也要記 ───────────────────────────────────
# 只記擋下來的那些是最省事的做法，也是漏網整類問題消失的原因。
# 這條在 record() 只寫 deny 的時候會紅。
if want 2; then
  case_ "2 紀錄裡放行與擋下都有"
  DEC=$(head -1 "${TMP}/j1.tsv" | tr '\t' '\n' | grep -n '^decision$' | cut -d: -f1)
  A=$(tail -n +2 "${TMP}/j1.tsv" | col "${DEC}" | grep -c '^allow$' || true)
  D=$(tail -n +2 "${TMP}/j1.tsv" | col "${DEC}" | grep -c '^deny$' || true)
  [ "${A}" -ge 1 ] && [ "${D}" -ge 1 ] \
    && ok "放行 ${A} 筆、擋下 ${D} 筆，兩種都留下了" \
    || bad "放行 ${A}、擋下 ${D}，少了一種就看不到另一半"
fi

# ── 3 那筆攻擊在輸入側是 allow，而且它留下了一行 ──────────────
# 這是上一條的具體案例：A1 走到動作側才被攔，輸入側那一行是 allow。
# 只記 deny 的紀錄裡這一行不存在，你會以為輸入側那天什麼都沒發生。
if want 3; then
  case_ "3 A1 在輸入側的那一行是 allow"
  DG=$(node -e '
    import("./journal.mjs").then(async (m) => {
      const rows = m.readJournal();
      const r = rows.filter((x) => x.point === "input-gate" && x.decision === "allow");
      console.log(r.length);
    })')
  [ "${DG}" = "2" ] && ok "輸入側放行了 2 筆（N1 與 A1），兩筆都在紀錄裡" \
    || bad "輸入側放行的紀錄有 ${DG} 筆，期望 2"
fi

# ── 4 七個欄位一個都不少，而且沒有錯位 ────────────────────
# 理由那一欄是模型寫的自由文字。裡面出現一個 tab，整個檔從那一列開始錯位，
# 而錯位之後每一欄都還讀得出東西，不會噴錯。
if want 4; then
  case_ "4 每一列都是九欄"
  N=$(head -1 "${TMP}/j1.tsv" | tr '\t' '\n' | grep -c .)
  BADROW=$(tail -n +2 "${TMP}/j1.tsv" | while IFS= read -r l; do
    c=$(printf '%s' "$l" | tr '\t' '\n' | grep -c .)
    [ "$c" = "9" ] || printf 'x'
  done | grep -c x || true)
  [ "${N}" = "9" ] && [ "${BADROW}" = "0" ] \
    && ok "表頭 9 欄，資料列沒有一列欄數不對" \
    || bad "表頭 ${N} 欄、欄數不對的資料列 ${BADROW} 列"
fi

# ── 5 版本號是算出來的，不是手填的 ──────────────────────
# version-demo.sh 自己會核對「改了會變」與「還原之後回得去」，這裡跑它。
# policyVersion 改成回傳固定字串的話，這條會紅。
if want 5; then
  case_ "5 判準改一個字，版本號跟著變"
  if bash version-demo.sh > "${TMP}/ver.out" 2>&1; then
    B=$(grep '^改之前' "${TMP}/ver.out" | col 3)
    A=$(grep '^加一個詞' "${TMP}/ver.out" | col 3)
    ok "加一個詞之前 ${B}、之後 ${A}，還原之後回到 ${B}"
  else
    bad "version-demo.sh 報紅：$(tail -2 "${TMP}/ver.out")"
  fi
fi

# ── 6 誤擋那條是從應放行集撈的，不是抄一份 ─────────────────
# 改 benign.jsonl 的 B5，demo 要跟著變。抄一份在 demo.mjs 裡的話這條會紅。
# 8/20 從 B4 換成 B5：Day 21 把「騙」拿掉之後 B4 會放行，
# 而這一格要的是「仍然被誤擋的那條」，不是「曾經被誤擋的那條」。
if want 6; then
  case_ "6 F1 的輸入直接來自應放行集 B5"
  BQ=$(node -e '
    const fs = require("node:fs");
    const rows = fs.readFileSync("../14-same-attacks-every-time/benign.jsonl", "utf8").trim().split("\n").map(JSON.parse);
    process.stdout.write(rows.find((r) => r.id === "B5").question);')
  grep -qF "$BQ" demo.mjs && bad "B5 那句話被抄進 demo.mjs 了，改應放行集不會影響它" || true
  D1=$(node -e "
    import('./journal.mjs').then((m) => {
      console.log(m.digest(process.argv[1]));
    })" "$BQ")
  tail -n +2 "${TMP}/j1.tsv" | cut -f4,6 | grep -qx "input-gate${TAB}${D1}" \
    && ok "紀錄裡那筆誤擋的指紋，等於應放行集 B5 那句話算出來的" \
    || bad "B5 的指紋 ${D1} 在紀錄裡找不到"
fi

# ── 7 標注清單裡要有對得上現行判準的那一筆 ────────────────
# 這條原本硬看 F1。判準在 Day 21 改過之後 F1 變成歷史標注，
# 硬看它就變成「永遠紅」，而永遠紅的檢查跟永遠綠的一樣沒用。
# 現在問的是正確的問題：現行判準版本下有沒有人工標注，那筆的指紋在不在紀錄裡。
# 舊版標注留在檔案裡不影響這條，那正是 policy_version 這一欄要做到的事。
if want 7; then
  case_ "7 現行判準版本下有一筆人工標注，指紋對得上紀錄"
  NOW=$(node -e 'import("./points.mjs").then((m) => console.log(m.INPUT_VERSION))')
  LD=$(python3 - "${NOW}" <<'PY'
import sys
now = sys.argv[1]
for line in open("labels.tsv", encoding="utf8"):
    if line.startswith("#") or line.startswith("id\t"):
        continue
    c = line.rstrip("\n").split("\t")
    if len(c) > 4 and c[3] == now:
        print(c[1])
        break
PY
)
  if [ -z "${LD}" ]; then
    bad "labels.tsv 裡沒有任何一筆對得上現行判準版本 ${NOW}：判準改過了，標注要重新確認"
  else
    tail -n +2 "${TMP}/j1.tsv" | cut -f4,6 | grep -qx "input-gate${TAB}${LD}" \
      && ok "現行版本 ${NOW} 有標注，指紋 ${LD} 也在紀錄裡" \
      || bad "現行版本的標注指紋 ${LD} 在紀錄裡找不到"
  fi
fi

# ── 8 drift 的數字，用另一條路重算一次 ───────────────────
# drift.mjs 自己會印 252 與 203。這裡用 python 逐檔 DictReader 重算，
# 兩條路的數字不一樣就紅。drift 改成印寫死的數字的話，這條會紅。
if want 8; then
  case_ "8 drift 的列數與不重複數，換一支程式重算得出來"
  DT=$(dcol "${TMP}/drift.out" 整批 列數)
  DD=$(dcol "${TMP}/drift.out" 整批 不重複)
  PY=$(python3 - <<'PY'
import csv, glob, os
files = sorted(glob.glob("../18-not-a-free-chatgpt/runs/*/*.tsv"))
rs = []
for f in files:
    with open(f, newline="") as fh:
        rd = csv.DictReader(fh, delimiter="\t")
        if "outreason" not in (rd.fieldnames or []):
            continue
        for r in rd:
            v = (r.get("outreason") or "").strip()
            if v:
                rs.append(v)
print(f"{len(rs)}\t{len(set(rs))}")
PY
)
  PT=$(printf '%s' "$PY" | col 1); PD=$(printf '%s' "$PY" | col 2)
  [ -n "${DT}" ] && [ -n "${PT}" ] && [ "${DT}" = "${PT}" ] && [ "${DD}" = "${PD}" ] \
    && ok "兩條路都是 ${DT} 列、${DD} 種不重複" \
    || bad "drift 說 ${DT}/${DD}，重算是 ${PT}/${PD}"
fi

# ── 9 長尾是假的：benign 那一臂列數等於不重複數 ──────────────
# 這條是整份 recipe 的主張。它紅掉代表資料變了，那個主張要重講。
if want 9; then
  case_ "9 benign 那一臂，48 列 48 種"
  L=$(dcol "${TMP}/drift.out" benign 列數)
  D=$(dcol "${TMP}/drift.out" benign 不重複)
  [ -n "${L}" ] && [ "${L}" = "${D}" ] && [ "${L}" -ge 40 ] \
    && ok "同一組正常請求 ${L} 列，模型寫出 ${D} 種理由，重複率零" \
    || bad "benign 那一臂 ${L} 列 ${D} 種"
fi

# ── 10 欄位真的跑過，而且不是寫死的 ─────────────────────
# drift 印的欄數要跟檔案現況一致：直接去數那幾個檔的表頭。
if want 10; then
  case_ "10 欄數 9 到 12 是從檔案數出來的"
  REAL=$(for f in ../18-not-a-free-chatgpt/runs/*/*.tsv; do
    head -1 "$f" | grep -q 'outreason' && head -1 "$f" | tr '\t' '\n' | grep -c .
  # 不要用 tr 接多位元組字元：BSD 的 tr（macOS）會換成完整的三個 byte，
  # GNU 的 tr（Linux）只換第一個，產出無效 UTF-8。8/21 CI 第一次跑抓到，
  # 本機是「9、10、11、12」，runner 上是「9?10?11?12?」。
  done | sort -n | uniq | awk 'NR>1{printf "、"} {printf "%s", $0} END{print ""}')
  SAID=$(grep '^欄數出現過' "${TMP}/drift.out" | sed 's/.*：//')
  [ -n "${SAID}" ] && [ "${REAL}" = "${SAID}" ] && ok "drift 說 ${SAID}，實際數出來也是 ${REAL}" \
    || bad "drift 說 ${SAID}，實際是 ${REAL}"
fi

# ── 11 固定讀第 9 欄，在後面幾批會讀到別的欄位 ────────────────
# 這是「欄位跑掉」為什麼危險的具體證據：它不會噴錯，只會靜靜給你錯的東西。
if want 11; then
  case_ "11 照欄號取值，在後面的批次讀到的不是理由"
  A=$(head -1 ../18-not-a-free-chatgpt/runs/2026-08-16/results.tsv | col 9)
  B=$(head -1 ../18-not-a-free-chatgpt/runs/2026-08-17b/results.tsv | col 9)
  [ "${A}" = "outreason" ] && [ "${B}" != "outreason" ] \
    && ok "第一批第 9 欄是 outreason，最後一批第 9 欄是 ${B}" \
    || bad "第一批 ${A}、最後一批 ${B}"
fi

# ── 12 分流拒絕跨版本加總 ────────────────────────────
# 造一份含兩個判準版本的紀錄，triage 要說出來而不是相加。
if want 12; then
  case_ "12 同一個判斷點出現兩個判準版本時，不加總"
  # 版本號不寫死在這裡：判準一改它就會變，寫死的話這條會靜靜地造不出第二個版本。
  V=$(tail -n +2 "${TMP}/j1.tsv" | cut -f5 | head -1)
  { head -1 "${TMP}/j1.tsv"; tail -n +2 "${TMP}/j1.tsv"; \
    tail -n +2 "${TMP}/j1.tsv" | sed "s/${V}/deadbeef/"; } > "${TMP}/two.tsv"
  node triage.mjs "${TMP}/two.tsv" > "${TMP}/two.out"
  grep -q '不加總' "${TMP}/two.out" \
    && ok "偵測到兩個版本，分開列" || bad "兩個版本混在一起還照樣加總了"
fi

# ── 13 分群只跑在缺 reason_code 那一格 ──────────────────
# 把一列的 reason_code 挖掉，triage 要把它挑出來給人看，而不是丟進計數。
if want 13; then
  case_ "13 缺 reason_code 的那一列被挑去分群，不進計數"
  sed '2s/SCENARIO_OK/-/' "${TMP}/j1.tsv" > "${TMP}/hole.tsv"
  node triage.mjs "${TMP}/hole.tsv" > "${TMP}/hole.out"
  grep -q '分群只跑這一格' "${TMP}/hole.out" \
    && ok "缺碼那一列被挑出來了" || bad "缺碼那一列沒有被挑出來"
  node triage.mjs "${TMP}/j1.tsv" | grep -q '不需要分群' \
    && ok "碼齊全的時候明講不需要分群" || bad "碼齊全還是叫人去分群"
fi

# ── 14 連跑兩次，紀錄逐位元相同 ────────────────────────
# 紀錄要拿來比對版本差異，前提是同樣的輸入寫出同樣的東西。
if want 14; then
  case_ "14 連跑兩次結果一致"
  JOURNAL_NOW=FIXED node demo.mjs > /dev/null
  cmp -s "${TMP}/j1.tsv" journal.tsv \
    && ok "兩次的 journal.tsv 逐位元相同" || bad "兩次跑出來的紀錄不一樣"
fi

# ── 15 判斷邏輯沒有被複製過來 ─────────────────────────
# points.mjs 只准接線。判準的定義出現在這裡，代表它會跟本尊漂開。
if want 15; then
  case_ "15 points.mjs 沒有自己定義判準"
  if grep -qE '^(export )?const (OUT_OF_SCOPE|SCENARIO|DENY_BY_DEFAULT|TOOL_ALLOWLIST|WORDS) *=' points.mjs; then
    bad "points.mjs 自己定義了判準常數，那份會跟 recipe 17／18 漂開"
  else
    ok "判準常數全部是 import 進來的"
  fi
fi

# ── 16 README 講的數字跟實跑對得上 ───────────────────────
if want 16; then
  case_ "16 README 的 252／203 跟現在跑出來的一樣"
  T=$(dcol "${TMP}/drift.out" 整批 列數)
  D=$(dcol "${TMP}/drift.out" 整批 不重複)
  [ -n "${T}" ] && [ -n "${D}" ] \
    && grep -q "${T} 列紀錄" README.md && grep -q "${D} 種不同的理由" README.md \
    && ok "README 寫的 ${T} 列 ${D} 種，就是現在跑出來的" \
    || bad "README 的數字跟實跑對不上（現在是 ${T} 列 ${D} 種）"
fi

# ── 17 分群跑在缺碼那一格，數字與範圍限制都要對 ──────────────
# 這條原本驗的是「堆數落在 2 到 12 就算方法有效」，那個區間是人為訂的，
# 而且把輸入條數當成了正確群數（8/19 外審抓到）。現在只驗兩件事實：
# 印出來的數字跟 README 貼的一致，以及那段範圍限制還在。
if want 17; then
  case_ "17 cluster 的數字跟 README 一致，範圍限制沒掉"
  OUT=$(node cluster.mjs 0.3)
  BH=$(printf '%s' "${OUT}" | grep "^benign${TAB}" | cut -f4)
  EH=$(printf '%s' "${OUT}" | grep "^evade${TAB}" | cut -f4)
  M=""
  [ -n "${BH}" ] && [ -n "${EH}" ] || M="${M} 讀不到堆數"
  grep -q "benign	5	48	${BH}" README.md || M="${M} README 貼的 benign 堆數不是 ${BH}"
  grep -q "還有 ${EH} 堆" README.md || M="${M} README 沒寫 evade 的 ${EH} 堆"
  # 不能再宣稱輸入條數是正確群數
  printf '%s' "${OUT}" | grep -q "輸入條數不是正確群數" || M="${M} 輸出少了「輸入條數不是正確群數」那句"
  grep -q "分群是在\*\*每個組各自跑\*\*的" README.md || M="${M} README 沒講各組堆數不能相加"
  grep -q "可以證偽的預測" cluster.mjs && M="${M} 原始碼還寫著「可以證偽的預測」"
  [ -z "${M}" ] && ok "benign ${BH} 堆、evade ${EH} 堆，跟 README 一致，範圍限制都在" || bad "對不上：${M}"
fi

# ── 18 分群真的是單連結：換個輸入順序，堆數不能變 ──────────
# 第一版寫成「找到第一個夠像的群就塞進去」，那個結果會隨輸入順序改變，
# 而它的名字叫單連結。名字跟行為不符最糟，因為報出來的堆數看起來像實驗結果。
# 這條就是釘那件事：真的 single-linkage 等價於相似度圖的連通分量，跟順序無關。
if want 18; then
  case_ "18 分群結果不隨輸入順序改變"
  R=$(node -e '
    const { readFileSync, readdirSync, statSync } = require("node:fs");
    const { join } = require("node:path");
    const RUNS = "../18-not-a-free-chatgpt/runs";
    const set = new Set();
    for (const d of readdirSync(RUNS)) {
      const dir = join(RUNS, d);
      if (!statSync(dir).isDirectory()) continue;
      for (const f of readdirSync(dir)) {
        if (!f.endsWith(".tsv")) continue;
        const L = readFileSync(join(dir, f), "utf8").trim().split("\n");
        const h = L[0].split("\t");
        if (!h.includes("outreason")) continue;
        for (const l of L.slice(1)) {
          const r = Object.fromEntries(l.split("\t").map((v, i) => [h[i], v]));
          if (r.armname === "evade" && r.outreason) set.add(r.outreason);
        }
      }
    }
    const items = [...set];
    const grams = (s) => {
      const t = s.replace(/[，。、；：（）「」\s]/g, "");
      const g = new Set();
      for (let i = 0; i + 1 < t.length; i += 1) g.add(t.slice(i, i + 2));
      return g;
    };
    const jac = (a, b) => { let h = 0; for (const x of a) if (b.has(x)) h += 1; return h / (a.size + b.size - h); };
    const run = (xs) => {
      const gs = xs.map(grams);
      const p = xs.map((_, i) => i);
      const find = (x) => { while (p[x] !== x) { p[x] = p[p[x]]; x = p[x]; } return x; };
      for (let i = 0; i < xs.length; i += 1)
        for (let j = i + 1; j < xs.length; j += 1)
          if (jac(gs[i], gs[j]) >= 0.3) { const a = find(i), b = find(j); if (a !== b) p[b] = a; }
      return new Set(xs.map((_, i) => find(i))).size;
    };
    console.log(`${run(items)} ${run([...items].reverse())}`);
  ')
  F=${R%% *}; B=${R##* }
  [ -n "${F}" ] && [ "${F}" = "${B}" ] \
    && ok "正序 ${F} 堆、反序 ${B} 堆，一樣" \
    || bad "正序 ${F} 堆、反序 ${B} 堆，會隨順序變就不是單連結"
fi

# ── 19 trace_id 缺了要吵，不是靜靜填一個「-」 ────────────────
# 文件說必填、實際可空，是這類 schema 最常見的謊。兩週後才會發現整批關聯不起來。
if want 19; then
  case_ "19 少了 trace_id 會擋下來"
  node -e '
    import("./journal.mjs").then((m) => {
      try { m.record({ point: "x", decision: "allow" }); process.exit(1); }
      catch { process.exit(0); }
    });' 2>/dev/null \
    && ok "record() 少了 trace_id 會拋錯" || bad "少了 trace_id 照樣寫得進去"
fi

# ── 20 人工標注不會跨版本污染（造真的資料驗，不是 grep 原始碼）────
# 只比 digest 的話，同一句話在新判準下被正確放行，舊版那個「誤擋」標籤照樣黏上去，
# 那跟整份 recipe「不同版本是兩把不同的尺」直接衝突。
#
# 第一版的檢查是 grep 原始碼有沒有 keyOf，所以「命中改對了、取值還在比 digest」
# 這種改一半的 bug 照樣全綠（8/19 外審抓到）。這條改成造兩筆同指紋、
# 不同判準版本、不同判定的標注，看印出來的是哪一筆。
if want 20; then
  case_ "20 同指紋不同判準版本的標注，取到的是當版那筆"
  DG=$(tail -n +2 "${TMP}/j1.tsv" | awk -F'\t' '$4=="input-gate" && $8=="SCOPE_BLOCK" {print $6}' | head -1)
  NOW=$(tail -n +2 "${TMP}/j1.tsv" | awk -F'\t' '$4=="input-gate" && $8=="SCOPE_BLOCK" {print $5}' | head -1)
  if [ -z "${DG}" ] || [ -z "${NOW}" ]; then
    bad "紀錄裡找不到那筆誤擋，這條驗不了"
  else
    {
      printf 'id\tdigest\tpoint\tpolicy_version\tdecision\tverdict\tsource\t處置\n'
      printf 'OLD\t%s\tinput-gate\tdeadbeef\tdeny\t舊版誤擋\t測試\t-\n' "${DG}"
      printf 'NEW\t%s\tinput-gate\t%s\tdeny\t當版誤擋\t測試\t-\n' "${DG}" "${NOW}"
    } > "${TMP}/labels-two.tsv"
    OUT=$(TRIAGE_LABELS="${TMP}/labels-two.tsv" node triage.mjs "${TMP}/j1.tsv")
    M=""
    printf '%s' "${OUT}" | grep -q '人判：當版誤擋' || M="${M} 沒取到當版那筆"
    printf '%s' "${OUT}" | grep -q '人判：舊版誤擋' && M="${M} 取到了舊版那筆（跨版本污染）"
    [ -z "${M}" ] && ok "同一個指紋兩筆標注，只認判準版本 ${NOW} 那筆" || bad "對不上：${M}"
  fi
fi

# ── 21 有 code 的也要真的抽樣，而且抽法是決定性的 ─────────────
if want 21; then
  case_ "21 有 code 的抽樣覆核真的抽得出東西"
  # 這裡也要帶 JOURNAL_NOW：漏了的話 journal.tsv 每跑一次就換一次時間戳，
  # 跑檢查變成一個會改 repo 的動作。8/21 CI 的「跑完 repo 要乾淨」那條抓到的就是這裡。
  JOURNAL_NOW=FIXED node demo.mjs >/dev/null 2>&1
  A=$(node triage.mjs | grep -c "抽樣覆核" || true)
  B=$(node triage.mjs); C=$(node triage.mjs)
  [ "${A}" -ge 1 ] || bad "triage 沒有抽樣那一段"
  [ "${A}" -ge 1 ] && { [ "${B}" = "${C}" ] \
    && ok "抽得出樣本，而且連跑兩次抽到同一批" \
    || bad "同一批紀錄兩次抽到不一樣的樣本"; }
fi

printf '\n%d 綠 %d 紅\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = 0 ]
