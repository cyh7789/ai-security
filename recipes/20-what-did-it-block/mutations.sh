#!/usr/bin/env bash
# 證明 verify.sh 那些檢查真的會紅：把行為弄壞，看對應那條有沒有咬到。
#
#   bash mutations.sh
#
# 每一種突變改的是行為（記不記錄、版本怎麼算、分流怎麼分），不是字串。
# 最後一列是反向控制：改一個不影響行為的地方，那一條要維持綠。
set -u
cd "$(dirname "$0")"

PASS=0; FAIL=0
# 用 tar 不用 cp：清單漏一個檔，那個突變跑完不會還原，下一列就假紅。
BACKUP=$(mktemp -d)/snap.tar
tar cf "${BACKUP}" journal.mjs points.mjs demo.mjs triage.mjs drift.mjs labels.tsv README.md
BENIGN=../14-same-attacks-every-time/benign.jsonl
BENIGN_BAK="$(dirname "${BACKUP}")/benign.jsonl"
cp "${BENIGN}" "${BENIGN_BAK}"
restore() {
  tar xf "${BACKUP}"
  cp -f "${BENIGN_BAK}" "${BENIGN}"
}
trap 'restore; rm -rf "$(dirname "${BACKUP}")"' EXIT

bite() {
  local name=$1 want=$2; shift 2
  # SKIP 要算失敗。錨點被一次無害的整理改掉，就會靜靜少驗一種而總計照樣是 0 紅。
  "$@" || { printf '  [SKIP] %-46s 改不動（算失敗）\n' "${name}"; FAIL=$((FAIL+1)); restore; return; }
  if bash verify.sh "${want}" >/dev/null 2>&1; then
    printf '  [FAIL] %-46s 第 %s 條沒咬到\n' "${name}" "${want}"; FAIL=$((FAIL+1))
  else
    printf '  [OK]   %-46s 第 %s 條咬到\n' "${name}" "${want}"; PASS=$((PASS+1))
  fi
  restore
}

hold() {
  local name=$1 want=$2; shift 2
  "$@" || { printf '  [SKIP] %-46s 改不動（算失敗）\n' "${name}"; FAIL=$((FAIL+1)); restore; return; }
  if bash verify.sh "${want}" >/dev/null 2>&1; then
    printf '  [OK]   %-46s 第 %s 條照樣綠（反向控制）\n' "${name}" "${want}"; PASS=$((PASS+1))
  else
    printf '  [FAIL] %-46s 第 %s 條不該紅\n' "${name}" "${want}"; FAIL=$((FAIL+1))
  fi
  restore
}

sub() { python3 - "$@" <<'SUBPY'
import sys, pathlib
f, pairs = sys.argv[1], sys.argv[2:]
p = pathlib.Path(f); s = p.read_text()
for a, b in zip(pairs[::2], pairs[1::2]):
    if s.count(a) != 1:
        sys.exit(1)
    s = s.replace(a, b)
p.write_text(s)
SUBPY
}

echo "== 突變 =="

bite "紀錄只寫 deny，放行的丟掉" 2 \
  sub journal.mjs \
  'export function record(entry) {' \
  'export function record(entry) {
  if (entry.decision === "allow") return entry;'

bite "輸入側放行的那一筆不記" 3 \
  sub points.mjs \
  '  const r = scenarioGate(text);
  record({' \
  '  const r = scenarioGate(text);
  if (!r.allow) record({'

bite "版本號改成寫死的字串" 5 \
  sub journal.mjs \
  '  return h.digest("hex").slice(0, 8);' \
  '  return "v1";'

bite "誤擋那句話抄進 demo.mjs" 6 \
  sub demo.mjs \
  '    text: B4.question,' \
  '    text: "幫我寫一封提醒客戶不要受騙的公告",'

# 改應放行集之後，示範會跟著變（第 6 條照樣綠，那是對的），
# 但標注清單記的是舊那句話的指紋，第 7 條要紅：判準或輸入變了，舊標注就得重新確認。
bite "應放行集的 B4 換了一句話" 7 \
  sub "${BENIGN}" \
  '"question":"幫我寫一封提醒客戶不要受騙的公告"' \
  '"question":"幫我寫一封提醒客戶留意詐騙的公告"'

bite "標注清單留著舊的判準版本" 7 \
  sub labels.tsv \
  '	968fe113	deny	誤擋' \
  '	00000000	deny	誤擋'

bite "drift 只讀第一個檔就下結論" 8 \
  sub drift.mjs \
  '    if (head.includes("outreason")) files.push(p);' \
  '    if (head.includes("outreason") && files.length === 0) files.push(p);'

bite "分流不檢查版本，直接加總" 12 \
  sub triage.mjs \
  '  if (vers.size > 1) {' \
  '  if (false) {'

bite "缺 reason_code 的丟進計數，不挑出來" 13 \
  sub triage.mjs \
  '    if (!r.reason_code || r.reason_code === "-") needCluster.push(r);' \
  '    if (false) needCluster.push(r);'

bite "接線層自己抄一份判準" 15 \
  sub points.mjs \
  'export const INPUT_POINT = "input-gate";' \
  'const OUT_OF_SCOPE = ["騙"];
export const INPUT_POINT = "input-gate";'

bite "README 的列數寫成別的數字" 16 \
  sub README.md \
  '252 列紀錄' \
  '300 列紀錄'

hold "改一句不影響行為的註解" 1 \
  sub demo.mjs \
  '// 三筆固定輸入走過兩個判斷點，把紀錄寫出來。' \
  '// 三筆固定輸入，走過兩個判斷點，把紀錄寫出來。'

printf '\n%d 咬到 %d 沒咬到\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = 0 ]
