#!/usr/bin/env bash
# 證明 verify.sh 那些檢查真的會沒過：把行為弄壞，看對應那條有沒有抓到。
#
#   bash mutations.sh
#
# 每一種突變改的是行為（記不記錄、版本怎麼算、分流怎麼分），不是字串。
# 最後一列是反向控制：改一個不影響行為的地方，那一條要維持通過。
set -u
cd "$(dirname "$0")"

PASS=0; FAIL=0
# 用 tar 不用 cp：清單漏一個檔，那個突變跑完不會還原，下一列就誤報。
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
  # SKIP 要算失敗。錨點被一次無害的整理改掉，就會靜靜少驗一種而總計照樣是 0 個沒過。
  "$@" || { printf '  沒有結論 %-46s 改不動（算失敗）\n' "${name}"; FAIL=$((FAIL+1)); restore; return; }
  if bash verify.sh "${want}" >/dev/null 2>&1; then
    printf '  沒過   %-46s 第 %s 條沒抓到\n' "${name}" "${want}"; FAIL=$((FAIL+1))
  else
    printf '  通過   %-46s 第 %s 條抓到\n' "${name}" "${want}"; PASS=$((PASS+1))
  fi
  restore
}

hold() {
  local name=$1 want=$2; shift 2
  "$@" || { printf '  沒有結論 %-46s 改不動（算失敗）\n' "${name}"; FAIL=$((FAIL+1)); restore; return; }
  if bash verify.sh "${want}" >/dev/null 2>&1; then
    printf '  通過   %-46s 第 %s 條照樣通過（反向控制）\n' "${name}" "${want}"; PASS=$((PASS+1))
  else
    printf '  沒過   %-46s 第 %s 條不該沒過\n' "${name}" "${want}"; FAIL=$((FAIL+1))
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

# 下面三條釘的是「現行那一格」，不是 B4。demo.mjs 8/20 就從 B4 換成 B5
# （Day 21 把「騙」從黑名單拿掉，B4 過了，那一格沒有誤擋可看），而這三條的錨點
# 留在 B4 時代：第一條變成改不動，另外兩條改的是不再對應現行版本的舊資料，
# 第 7 條照樣通過。2026-08-26 補上。最後一條改成從 points.mjs 現算版本號，版本再變也不會失效。
bite "誤擋那句話抄進 demo.mjs" 6 \
  sub demo.mjs \
  '    text: B5.question,' \
  '    text: "幫我寫一封提醒客戶留意假冒官方信件的公告",'

# 改應放行集之後，示範會跟著變（第 6 條照樣通過，那是對的），
# 但標注清單記的是舊那句話的指紋，第 7 條要沒過：判準或輸入變了，舊標注就得重新確認。
bite "應放行集的 B5 換了一句話" 7 \
  sub "${BENIGN}" \
  '"question":"幫我寫一封提醒客戶留意假冒官方信件的公告"' \
  '"question":"幫我寫一封提醒客戶當心假冒官方信件的公告"'

# 抹掉的是現行版本那一列（labels.tsv 最後一列），不是歷史那幾列。
# 改歷史列第 7 條不會沒過，因為它找的是「對得上現行版本」的那一筆。
bite "標注清單裡現行版本那列被改掉" 7 \
  python3 -c "
import pathlib, subprocess
now = subprocess.run(['node', '-e', 'import(\"./points.mjs\").then((m) => console.log(m.INPUT_VERSION))'],
                     capture_output=True, text=True).stdout.strip()
p = pathlib.Path('labels.tsv'); s = p.read_text()
if f'\t{now}\t' not in s: raise SystemExit(1)
p.write_text(s.replace(f'\t{now}\t', '\t00000000\t'))
"

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

WANT_TOTAL=12   # 突變列數加反向對照那一列。改表就改這個數字。
printf '\n%d 抓到 %d 沒抓到（預期 %d 種）\n' "${PASS}" "${FAIL}" "${WANT_TOTAL}"
[ "${FAIL}" = 0 ] && [ "${PASS}" -eq "${WANT_TOTAL}" ]
