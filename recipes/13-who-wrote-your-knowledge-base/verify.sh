#!/usr/bin/env bash
# 這一份的驗證。跑法：bash verify.sh        全部
#                    bash verify.sh 7      只跑第 7 條
#
# 每一條驗的都是行為，不是字面。寫的時候問自己的那句話：
# 「把功能弄壞（不是把字改掉），這條會不會轉紅？」答不出來的就重寫。
# 證明它們真的會紅：bash mutations.sh

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

ASK="出差報帳要準備什麼單據"

# ── 1 ────────────────────────────────────────────────────
if run 1; then
  # 每一組都比，不是只比一組。只挑一組的話，「只讀了前幾行」這種漏法
  # 剛好會被排在前面的那一組蓋過去（實測過，那條放行）。
  echo "=== 1 每一組的數字都對得上檔案本身 ==="
  OUT=$(node kb-sources.cjs demo/kb.jsonl --prefix :); RC=$?
  GOT=$(printf '%s\n' "${OUT}" | sed -n '2,/^合計/p' | grep -v '^合計' | awk 'NF{print $1"="$2}' | sort | tr '\n' ' ')
  WANT=$(sed 's/.*"source":"\([^:"]*\).*/\1/' demo/kb.jsonl | sort | uniq -c \
         | awk '{print $2"="$1}' | sort | tr '\n' ' ')
  [ "${RC}" = 0 ] && [ -n "${GOT}" ] && [ "${GOT}" = "${WANT}" ] \
    && ok "分組數出 ${GOT}，跟檔案一致" \
    || bad "數出「${GOT}」、檔案是「${WANT}」、結束碼 ${RC}"
fi

# ── 2 ────────────────────────────────────────────────────
# 段數與來源數都拿檔案重算，不寫死。加一列進 demo/kb.jsonl 這條要自己跟上。
if run 2; then
  echo "=== 2 段數與來源數是算出來的 ==="
  OUT=$(node kb-sources.cjs demo/kb.jsonl --prefix :)
  HEAD=$(printf '%s\n' "${OUT}" | head -1)
  N=$(grep -c . demo/kb.jsonl)
  K=$(sed 's/.*"source":"\([^:"]*\).*/\1/' demo/kb.jsonl | sort -u | wc -l | tr -d ' ')
  printf '%s' "${HEAD}" | grep -q "${N} 段，${K} 個來源" \
    && ok "報 ${N} 段 ${K} 個來源，跟檔案一致" || bad "標題是「${HEAD}」，檔案是 ${N} 段 ${K} 個來源"
fi

# ── 3 ────────────────────────────────────────────────────
# 這一條是這份的核心規矩：「我沒看到」不能跟「沒問題」混在一起。
if run 3; then
  echo "=== 3 有段落沒有來源欄就要非 0 結束 ==="
  OUT=$(node kb-sources.cjs demo/kb-nosource.jsonl --prefix :); RC=$?
  MISS=$(printf '%s\n' "${OUT}" | sed -n 's/^沒有來源欄的：\([0-9]*\) 段.*/\1/p')
  WANT=$(node -e '
    const fs=require("fs");let n=0;
    for (const l of fs.readFileSync("demo/kb-nosource.jsonl","utf8").split("\n").filter(x=>x.trim())) {
      try { const r=JSON.parse(l); if (typeof (r.source ?? r.metadata?.source) !== "string") n++; } catch {}
    }
    console.log(n);')
  [ "${RC}" = 2 ] && [ "${MISS}" = "${WANT}" ] \
    && ok "結束碼 2，數出 ${MISS} 段沒有來源，跟檔案一致" \
    || bad "結束碼 ${RC}、數出 ${MISS}、檔案裡是 ${WANT}"
fi

# ── 4 ────────────────────────────────────────────────────
# 讀不出來的行要單獨講，不能靜靜跳過。這是 Day 12 那個洞的同一個形狀。
if run 4; then
  echo "=== 4 壞掉的行要被數出來 ==="
  OUT=$(node kb-sources.cjs demo/kb-nosource.jsonl --prefix :)
  N=$(printf '%s\n' "${OUT}" | sed -n 's/^讀不出來的行：\([0-9]*\) 行.*/\1/p')
  [ "${N}" = 1 ] && ok "報出 1 行讀不出來" || bad "報出「${N}」，示範檔裡故意放了 1 行壞的"
fi

# ── 5 ────────────────────────────────────────────────────
if run 5; then
  echo "=== 5 --prefix 沒給的時候不切，來源數會變多 ==="
  A=$(node kb-sources.cjs demo/kb.jsonl --prefix : | head -1 | sed 's/.*，\([0-9]*\) 個來源.*/\1/')
  B=$(node kb-sources.cjs demo/kb.jsonl        | head -1 | sed 's/.*，\([0-9]*\) 個來源.*/\1/')
  [ -n "${A}" ] && [ -n "${B}" ] && [ "${B}" -gt "${A}" ] \
    && ok "切前綴 ${A} 個、不切 ${B} 個" || bad "切前綴 ${A}、不切 ${B}，不切的應該比較多"
fi

# ── 6 ────────────────────────────────────────────────────
if run 6; then
  echo "=== 6 stdin 進來的結果跟給檔名一樣 ==="
  A=$(node kb-sources.cjs demo/kb.jsonl --prefix :)
  B=$(node kb-sources.cjs - --prefix : < demo/kb.jsonl)
  [ "${A}" = "${B}" ] && ok "兩種餵法輸出逐字相同" || bad "兩種餵法輸出不同"
fi

# ── 7 ────────────────────────────────────────────────────
# 名次是排出來的，不是印出來的字。把投毒檔換成一份跟問題無關的內容，名次要掉。
if run 7; then
  echo "=== 7 投毒那份的名次跟它的內容有關 ==="
  R1=$(node rank-probe.cjs demo/corpus --ask "${ASK}" --poison demo/poison.txt --top 9 \
       | sed -n 's/^你造的那份排第 \([0-9]*\) 名.*/\1/p')
  cp demo/corpus/03-oncall.md "${TMP}/unrelated.txt"
  R2=$(node rank-probe.cjs demo/corpus --ask "${ASK}" --poison "${TMP}/unrelated.txt" --top 9 \
       | sed -n 's/^你造的那份排第 \([0-9]*\) 名.*/\1/p')
  [ -n "${R1}" ] && [ -n "${R2}" ] && [ "${R1}" -lt "${R2}" ] \
    && ok "對題那份第 ${R1} 名，不對題那份第 ${R2} 名" \
    || bad "對題 ${R1} 名、不對題 ${R2} 名，對題的應該比較前面"
fi

# ── 8 ────────────────────────────────────────────────────
# 空對照：機制不存在的時候這個數字會是多少？問一個語料裡沒有的題目，
# 投毒那份不該還是第一名。沒有這一條，第 7 條的「第 1 名」可能只是它字最多。
if run 8; then
  echo "=== 8 問不相干的問題，投毒那份不會還是第一 ==="
  OUT=$(node rank-probe.cjs demo/corpus --ask "值班交接要確認哪些事" --poison demo/poison.txt --top 9)
  R=$(printf '%s\n' "${OUT}" | sed -n 's/^你造的那份排第 \([0-9]*\) 名.*/\1/p')
  [ -n "${R}" ] && [ "${R}" -gt 1 ] && ok "換個問題它掉到第 ${R} 名" || bad "換個問題它還是第 ${R} 名"
fi

# ── 9 ────────────────────────────────────────────────────
# --top 改的是「送進 prompt 的名額」，所以同一個名次會從進得去變成進不去。
if run 9; then
  echo "=== 9 名額縮小之後，同一份東西的判定會翻面 ==="
  IN=$(node rank-probe.cjs demo/corpus --ask "新人第一週要做什麼" --poison demo/poison.txt --top 9 \
       | grep -c "會被送進 prompt")
  OUTC=$(node rank-probe.cjs demo/corpus --ask "新人第一週要做什麼" --poison demo/poison.txt --top 1 \
       | grep -c "沒進前 1")
  [ "${IN}" = 1 ] && [ "${OUTC}" = 1 ] \
    && ok "前 9 名進得去、前 1 名進不去" || bad "前 9 的判定 ${IN}、前 1 的判定 ${OUTC}"
fi

# ── 10 ───────────────────────────────────────────────────
# 沒進前 N 的時候要講「要贏過第 N 名」，而那個數字必須真的是排名表上第 N 名的分數。
if run 10; then
  echo "=== 10 「要擠進去得贏過誰」報的是第 N 名的分數 ==="
  OUT=$(node rank-probe.cjs demo/corpus --ask "值班交接要確認哪些事" --poison demo/poison.txt --top 2)
  SAID=$(printf '%s\n' "${OUT}" | sed -n 's/.*贏過第 2 名的 \([0-9.]*\).*/\1/p')
  NTH=$(printf '%s\n' "${OUT}" | awk '/^ *2\./{print $2}')
  [ -n "${SAID}" ] && [ "${SAID}" = "${NTH}" ] \
    && ok "說要贏過 ${SAID}，排名表第 2 名正是 ${NTH}" || bad "說 ${SAID}、表上是 ${NTH}"
fi

# ── 11 ───────────────────────────────────────────────────
# 走訪要跟著 symlink 走。Day 12 的洞：Dirent.isDirectory() 對指向目錄的 symlink 回 false。
if run 11; then
  echo "=== 11 語料在 symlink 後面也要讀得到 ==="
  mkdir -p "${TMP}/real" "${TMP}/tree"
  cp demo/corpus/01-expense.md "${TMP}/real/"
  ln -s "${TMP}/real" "${TMP}/tree/linked"
  N=$(node rank-probe.cjs "${TMP}/tree" --ask "${ASK}" | sed -n 's/^語料 \([0-9]*\) 份.*/\1/p')
  [ "${N}" = 1 ] && ok "跟著 symlink 讀到 1 份" || bad "讀到 ${N} 份，symlink 後面那份沒進去"
fi

# ── 12 ───────────────────────────────────────────────────
if run 12; then
  echo "=== 12 symlink 繞圈不會無限走下去 ==="
  mkdir -p "${TMP}/loop/a"
  cp demo/corpus/02-onboarding.md "${TMP}/loop/a/"
  ln -s "${TMP}/loop" "${TMP}/loop/a/back"
  OUT=$(node rank-probe.cjs "${TMP}/loop" --ask "${ASK}" 2>&1); RC=$?
  N=$(printf '%s\n' "${OUT}" | sed -n 's/^語料 \([0-9]*\) 份.*/\1/p')
  [ "${RC}" = 0 ] && [ "${N}" = 1 ] && ok "繞圈的樹只讀到 1 份就停" || bad "結束碼 ${RC}、讀到 ${N} 份"
fi

# ── 13 ───────────────────────────────────────────────────
# --embed 那一路真的走網路，而且真的用回來的向量排序。
# 用一台假的端點：它回的向量刻意讓最後一份文件贏。
# 問題故意挑「值班交接」那句 —— 字面那一路投毒檔在這句排第 9，
# 所以第一名是它就只可能來自端點回的向量。用一句字面本來就會贏的問題，
# 這條會變成兩邊都綠的假閘門（實測過，那樣改真的放行）。
if run 13; then
  echo "=== 13 --embed 用的是端點回來的向量 ==="
  node - "${TMP}" <<'JS' &
const http = require("http");
// 每一段都給一個固定向量：問題是 [1,0]，最後一份文件是 [1,0]，其餘是 [0,1]。
// 所以不管文字寫什麼，排第一的一定是最後一份。
const s = http.createServer((req, res) => {
  let b = "";
  req.on("data", (c) => (b += c));
  req.on("end", () => {
    const { input } = JSON.parse(b);
    const data = input.map((_, i) => ({ embedding: i === 0 || i === input.length - 1 ? [1, 0] : [0, 1] }));
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({ data }));
  });
});
s.listen(0, "127.0.0.1", () => require("fs").writeFileSync(process.argv[2] + "/port", String(s.address().port)));
setTimeout(() => s.close(), 20000);
JS
  STUB=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "${TMP}/port" ] && break; sleep 0.3; done
  if [ -s "${TMP}/port" ]; then
    P=$(cat "${TMP}/port")
    TOPDOC=$(node rank-probe.cjs demo/corpus --ask "值班交接要確認哪些事" --poison demo/poison.txt --top 1 \
             --embed "http://127.0.0.1:${P}/v1/embeddings" | awk '/^ *1\./{print $3}')
    [ "${TOPDOC}" = "poison.txt" ] \
      && ok "假端點讓最後一份贏，排第一的就是它" || bad "排第一的是 ${TOPDOC}，假端點指定的是 poison.txt"
  else
    bad "假的 embedding 端點沒起來"
  fi
  { kill "${STUB}"; wait "${STUB}"; } 2>/dev/null
fi

# ── 14 ───────────────────────────────────────────────────
# 端點少回一筆會讓分數整排錯位，而排名照樣印得出來，這正是最危險的失敗。
if run 14; then
  echo "=== 14 端點回的筆數對不上就要停 ==="
  node - "${TMP}" <<'JS' &
const http = require("http");
const s = http.createServer((req, res) => {
  let b = "";
  req.on("data", (c) => (b += c));
  req.on("end", () => {
    const { input } = JSON.parse(b);
    const data = input.slice(1).map(() => ({ embedding: [1, 0] })); // 故意少一筆
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({ data }));
  });
});
s.listen(0, "127.0.0.1", () => require("fs").writeFileSync(process.argv[2] + "/port2", String(s.address().port)));
setTimeout(() => s.close(), 20000);
JS
  STUB=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "${TMP}/port2" ] && break; sleep 0.3; done
  P=$(cat "${TMP}/port2" 2>/dev/null || echo "")
  if [ -n "${P}" ]; then
    OUT=$(node rank-probe.cjs demo/corpus --ask "${ASK}" --embed "http://127.0.0.1:${P}/v1/embeddings" 2>&1); RC=$?
    printf '%s' "${OUT}" | grep -q "筆數\|回了" && [ "${RC}" != 0 ] \
      && ok "少一筆就停下來喊，結束碼 ${RC}" || bad "結束碼 ${RC}，輸出：$(printf '%s' "${OUT}" | head -2)"
  else
    bad "假的 embedding 端點沒起來"
  fi
  { kill "${STUB}"; wait "${STUB}"; } 2>/dev/null
fi

# ── 15 ───────────────────────────────────────────────────
# 這支不是語意檢索，它自己要講出來。這條盯的是「別人把警語拿掉」，
# 不是盯字串：把 --embed 接上去的時候那句話反而不該出現。
if run 15; then
  echo "=== 15 沒接 --embed 的時候要自己說它不是語意 ==="
  A=$(node rank-probe.cjs demo/corpus --ask "${ASK}" | grep -c "不是語意")
  [ "${A}" = 1 ] && ok "字面那一路有講" || bad "字面那一路講了 ${A} 次"
fi

echo
printf '%s 綠 %s 紅\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = 0 ]
