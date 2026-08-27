#!/usr/bin/env bash
# 把 verify.sh 的每一條各弄壞一次，看它會不會判沒過。
#
#   bash mutations.sh
#
# 一條檢查沒有真的抓到過東西，它就只是一段跑得動的程式，不是一道檢查。
#
# 兩件事做得比「看離開碼」嚴：
#
# 一、「沒有結論」不算「沒過」。混在一起的話，一台沒裝 jsdom 的機器會把整張表
#    印成全部通過，而其實一條都沒驗到。
# 二、每一列指定**哪幾條**該沒過，精確比對。只看過不過的話，一個突變可以靠
#    別的檢查沒過來冒充。
#
# 這一天的突變有一半改的是簽核欄，因為這張表最容易壞的方式不是算錯，
# 是有人把一件沒跑過的事簽成過了。
set -u
cd "$(dirname "$0")"
export LC_ALL=C

command -v node >/dev/null 2>&1 || {
  echo "沒有 node。鏈那一組驗不掉，沒有結論。" >&2; exit 2; }
node -e "import('jsdom')" >/dev/null 2>&1 || {
  echo "node 找不到 jsdom。鏈那一組驗不掉，沒有結論。在 repo 根目錄跑 npm install。" >&2; exit 2; }
python3 -c "pass" >/dev/null 2>&1 || {
  echo "沒有 python3，改不了那幾個檔，沒有結論。" >&2; exit 2; }

LV=../22-when-should-it-stop-you/levels.tsv
CASES=../24-green-or-never-hit/cases.tsv
CHAIN=../29-single-checks-combined/chain-exec.mjs
IDX=../../README.md

# 從一個已經被弄壞的狀態開跑，備份下來的就是壞的那份，後面每一列都在量假的東西
# （8/28 實測：上一輪被逾時砍掉，uncovered.tsv 停在被清空的樣子，接著四列全部誤判）。
# 所以開跑前先確認判準檔是完整的，不完整就不跑。
bash verify.sh 1 >/dev/null 2>&1 || {
  echo "判準檔現在就不完整（verify.sh 第 1 節沒過），先把它修回來再跑突變。" >&2; exit 2; }
grep -q '其餘六支' uncovered.tsv || {
  echo "uncovered.tsv 看起來被上一輪突變留在半路，先還原再跑。" >&2; exit 2; }

# 兩份同時跑會互相蓋掉對方的備份，收尾之後判準檔停在誰的突變上就看誰先結束
# （8/28 實測：兩個行程並行，README 少了一列、uncovered.tsv 停在半路，十一列全部誤判）。
# 鎖放在 repo 外面：被砍掉的時候它會留著，留在 repo 裡就變成一個沒人認得的未追蹤檔，
# 而 CI 有一條在檢查「跑完工作目錄要是乾淨的」。
LOCK=${TMPDIR:-/tmp}/ai-security-recipe30-mutations.lock
mkdir "$LOCK" 2>/dev/null || {
  echo "已經有一份 mutations.sh 在跑（${LOCK} 還在）。等它跑完，或確認沒有行程之後把那個目錄刪掉。" >&2
  exit 2; }

BACKUP=$(mktemp -d)
cp standard.tsv uncovered.tsv rollup.sh "$BACKUP/"
cp "$LV" "$BACKUP/levels.tsv"
cp "$CASES" "$BACKUP/cases.tsv"
cp "$CHAIN" "$BACKUP/chain-exec.mjs"
cp "$IDX" "$BACKUP/README.md"
restore() {
  # 被打斷的時候 INT 跟 EXIT 會各觸發一次，第二次備份目錄已經刪掉了。
  # 不擋的話收尾會噴一串 cp: No such file，看起來像還原失敗。
  [ -d "$BACKUP" ] || return 0
  cp "$BACKUP/standard.tsv" standard.tsv
  cp "$BACKUP/uncovered.tsv" uncovered.tsv
  cp "$BACKUP/rollup.sh" rollup.sh
  cp "$BACKUP/levels.tsv" "$LV"
  cp "$BACKUP/cases.tsv" "$CASES"
  cp "$BACKUP/chain-exec.mjs" "$CHAIN"
  cp "$BACKUP/README.md" "$IDX"
}
# EXIT 之外還要接 INT 與 TERM。這支跑一輪要兩分半，被 Ctrl-C 或逾時打斷的機率不低，
# 而只掛 EXIT 的話那兩個訊號會讓判準檔停在突變後的樣子（8/28 實測，uncovered.tsv 停在被清空的狀態）。
trap 'restore; rm -rf "$BACKUP" "$LOCK"' EXIT INT TERM

P=0; F=0
run() {  # $1=編號 $2=說明 $3=期望的判定 $4=期望沒過的條號（逗號分隔，可省）
  local out rc got reds
  out=$(bash verify.sh 2>&1); rc=$?
  case "$rc" in
    0) got=通過 ;;
    2) got=沒有結論 ;;
    *) got=沒過 ;;
  esac
  reds=$(printf '%s\n' "$out" | awk '
    /^=== / { n=$2 }
    /^  沒過/ { if (!(n in seen)) { seen[n]=1; o = o (o?",":"") n } }
    END { print o }')
  if [ "$got" = "$3" ] && { [ -z "${4:-}" ] || [ "$reds" = "$4" ]; }; then
    printf '%s\t%s\t期望%s%s\t得到%s%s\t通過\n' "$1" "$2" "$3" "${4:+（第 $4 條）}" "$got" "${reds:+（第 $reds 條）}"
    P=$((P+1))
  else
    printf '%s\t%s\t期望%s%s\t得到%s%s\t**沒抓到**\n' "$1" "$2" "$3" "${4:+（第 $4 條）}" "$got" "${reds:+（第 $reds 條）}"
    F=$((F+1))
  fi
  restore
}

printf '編號\t突變\t期望\t得到\t結果\n'

# 最誘人的那個動作：把七條已知缺口簽成過了。這張表的整個價值就在這一列會不會叫。
python3 -c "
import pathlib
p = pathlib.Path('standard.tsv'); s = p.read_text()
assert '\t9/7/0\t' in s
p.write_text(s.replace('\t9/7/0\t', '\t16/0/0\t'))"
run M1 "把七條已知缺口簽成過了" 沒過 2

# 沒有重跑指令的那一列被簽成過了。沒跑過的東西不會有結果。
python3 -c "
import pathlib
p = pathlib.Path('standard.tsv'); s = p.read_text()
assert '\t0/0/1\t' in s
p.write_text(s.replace('\t0/0/1\t', '\t1/0/0\t'))"
run M2 "把沒測那一列簽成過了" 沒過 2,3

# 反過來：有重跑指令卻簽成沒測，等於寫了指令沒跑。
python3 -c "
import pathlib
p = pathlib.Path('standard.tsv'); s = p.read_text()
assert '\t1/0/0\t' in s
p.write_text(s.replace('\t1/0/0\t', '\t0/0/1\t', 1))"
run M3 "有重跑指令卻簽成沒測" 沒過 2,3

# 重跑指令指到不存在的東西。一條跑不起來的指令跟沒有指令是同一回事。
python3 -c "
import pathlib
p = pathlib.Path('standard.tsv'); s = p.read_text()
a = 'bash recipes/24-green-or-never-hit/run.sh'
assert a in s
p.write_text(s.replace(a, 'bash recipes/24-green-or-never-hit/nope.sh'))"
run M4 "重跑指令指到不存在的檔" 沒過 4

# 沒測清單被清空。一張只列測過的東西的表，跟一張全部都測過的表長得一樣。
python3 -c "
import pathlib
p = pathlib.Path('uncovered.tsv'); s = p.read_text()
head = [l for l in s.splitlines() if l.startswith('#') or l.startswith('項目')]
p.write_text('\n'.join(head) + '\n')"
run M5 "把沒測清單清空" 沒過 1,5

# 沒測清單上的數字被改成不是數出來的。
python3 -c "
import pathlib
p = pathlib.Path('uncovered.tsv'); s = p.read_text()
assert '其餘六支' in s
p.write_text(s.replace('其餘六支', '其餘三支'))"
run M6 "沒測清單的數字改成手寫的" 沒過 5

# 有一支 recipe 沒有分級，等於它不在 CI 的任何一個矩陣裡。
python3 -c "
import pathlib
p = pathlib.Path('$LV'); s = p.read_text()
out = [l for l in s.splitlines() if not l.startswith('30-what-does-it-actually-cover\t')]
p.write_text('\n'.join(out) + '\n')"
run M7 "把 30 從分級表拿掉" 沒過 6

# 來源的紀錄跟實測對不上。這時候整組要判沒有結論，不能挑一邊當結果。
python3 -c "
import pathlib
p = pathlib.Path('$CASES'); s = p.read_text()
lines = s.splitlines()
for i, l in enumerate(lines):
    if l.startswith('C04\t'):
        f = l.split('\t'); f[6] = '沒擋'; lines[i] = '\t'.join(f); break
else:
    raise SystemExit('找不到 C04')
p.write_text('\n'.join(lines) + '\n')"
run M8 "把來源紀錄的一列改成跟實測不一樣" 沒有結論

# 鏈那一組的修好版不再逃逸。這一條證明第 2 條真的跑了那支程式，不是讀存檔。
python3 -c "
import pathlib
p = pathlib.Path('$CHAIN'); s = p.read_text()
a = 'const renderFixed = (a) =>'
assert a in s, '找不到修好版那行'
p.write_text(s.replace(a, 'const renderFixed = renderNow;\nconst _renderFixedOld = (a) =>'))"
run M9 "鏈那一組的修好版不再逃逸" 沒過 2

# 彙整腳本弄髒了工作目錄。一支跑一次就改到別人檔案的檢查，在 CI 上會讓下一支
# 量到的是被它改過的狀態。
python3 -c "
import pathlib
p = pathlib.Path('rollup.sh'); s = p.read_text()
a = 'rows() {'
assert a in s
p.write_text(s.replace(a, 'printf x >> \"\$ROOT/recipes/24-green-or-never-hit/cases.tsv\"\nrows() {'))"
run M10 "彙整腳本跑一次就改到別人的檔案" 沒過 7

# README 那張索引表少一列。少了它讀者點進來會找不到今天這一份。
python3 -c "
import pathlib
p = pathlib.Path('../../README.md'); s = p.read_text()
out = [l for l in s.splitlines() if 'recipes/30-what-does-it-actually-cover/' not in l]
p.write_text('\n'.join(out) + '\n')"
run M11 "README 的索引表少了 30 那列" 沒過 8

# 反向對照：改一個不影響任何判定的地方，應該照樣全部通過。
# 沒有它，「什麼都會讓它沒過」跟「它抓得準」分不開。
python3 -c "
import pathlib
p = pathlib.Path('standard.tsv'); s = p.read_text()
p.write_text(s.replace('組\t展開', '# 一行不影響判定的註解\n組\t展開'))"
run M0 "standard.tsv 加一行註解" 通過

printf '\n通過 %s、沒抓到 %s\n' "$P" "$F"
[ "$F" != 0 ] && exit 1
exit 0
