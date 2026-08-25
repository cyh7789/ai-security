#!/usr/bin/env bash
# 把 verify.sh 的每一條各弄壞一次，看它會不會紅。
#
#   bash mutations.sh
#
# 一條檢查沒有被咬過，它就只是一段跑得動的程式，不是一道閘。
#
# 規矩跟 Day 26 那份一樣，兩件事做得比「看離開碼」嚴：
#
# 一、「沒有結論」不算「紅」。混在一起的話，一台沒有模型的機器會把整張表印成
#    全部通過，而其實一條都沒驗到。
# 二、每一列要指定**哪幾條**該紅，精確比對。只看顏色的話，一個突變可以靠別條紅
#    來冒充，而它宣稱要驗的那條壞掉也沒人知道。
#
# 突變改的是資料不是腳本，因為這一天要防的東西就在資料裡：一份核對表最容易壞的
# 方式不是寫錯程式，是核的人憑印象填一格。M9 例外，它改的是被檢查的那份原始碼。
set -u
cd "$(dirname "$0")"
export LC_ALL=C

MODEL="${ANTARES_MLX:-./antares-1b-mlx}"
[ -r "$MODEL/config.json" ] || {
  echo "找不到模型（$MODEL）。M10 要真的重跑一輪，沒有模型這張表驗不掉，沒有結論。" >&2
  echo "設 ANTARES_MLX 指過去。" >&2
  exit 2
}
command -v node >/dev/null 2>&1 || {
  echo "沒有 node。M9 要真的打一次，沒有 node 那一列驗不掉，沒有結論。" >&2
  exit 2
}

TOOLS=../../playground/server/tools.js
IDX=../../README.md
BACKUP=$(mktemp -d)
cp cwes.tsv verdict.tsv FINDINGS.md "${BACKUP}/"
cp "$TOOLS" "${BACKUP}/tools.js"
cp "$IDX" "${BACKUP}/README.md"
cp -R hunt "${BACKUP}/hunt"
cp -R hunt-renamed "${BACKUP}/hunt-renamed"
restore() {
  cp "${BACKUP}/cwes.tsv" "${BACKUP}/verdict.tsv" "${BACKUP}/FINDINGS.md" .
  cp "${BACKUP}/tools.js" "$TOOLS"
  cp "${BACKUP}/README.md" "$IDX"
  rm -rf hunt hunt-renamed
  cp -R "${BACKUP}/hunt" hunt
  cp -R "${BACKUP}/hunt-renamed" hunt-renamed
}
trap 'restore; rm -rf "$BACKUP"' EXIT

P=0; F=0
run() {  # $1=編號 $2=說明 $3=期望顏色 $4=期望變紅的條號（逗號分隔，可省）
  local out rc got reds
  out=$(SKIP_RERUN="${SKIP_RERUN_THIS:-1}" ANTARES_MLX="$MODEL" bash verify.sh 2>&1); rc=$?
  case "$rc" in
    0) got=綠 ;;
    2) got=沒有結論 ;;
    *) got=紅 ;;
  esac
  # 哪幾條紅：段落標題是「=== N 說明 ===」，紅的那行以「  紅」開頭。
  reds=$(printf '%s\n' "$out" | awk '
    /^=== / { n=$2 }
    /^  紅/ { if (!(n in seen)) { seen[n]=1; out = out (out?",":"") n } }
    END { print out }')
  if [ "$got" = "$3" ] && { [ -z "${4:-}" ] || [ "$reds" = "$4" ]; }; then
    printf '%s\t%s\t期望%s%s\t得到%s%s\t通過\n' "$1" "$2" "$3" "${4:+（第 $4 條）}" "$got" "${reds:+（第 $reds 條）}"
    P=$((P+1))
  else
    printf '%s\t%s\t期望%s%s\t得到%s%s\t**沒咬到**\n' "$1" "$2" "$3" "${4:+（第 $4 條）}" "$got" "${reds:+（第 $reds 條）}"
    F=$((F+1))
  fi
  restore
}

printf '編號\t突變\t期望\t得到\t結果\n'

# 把一個「無」改成一個檔名：六在七不在變成七在六不在。第 5、6、7 條也會跟著炸，
# 因為那一列的判定「亂指」在「在」的那一組裡不合法。
python3 -c "
p='cwes.tsv';s=open(p).read();open(p,'w').write(s.replace('CWE-611\t無\t','CWE-611\tsrc/render.js\t'))"
run M1 "把一個「不在」的類別改成「在」" 紅 1,5,6,7

: > hunt/CWE-78.txt
run M2a "把一份原始輸出清空" 紅 2,3

python3 -c "
import json;p='hunt/run.json';d=json.load(open(p));d['total_seconds']=99.9;json.dump(d,open(p,'w'))"
run M2b "存檔的總秒數改掉，逐條不動" 紅 2

# 只改一個字。核對表看起來照樣像有引原句。
python3 -c "
p='verdict.tsv';s=open(p).read()
assert 'Files containing CWE-22' in s
open(p,'w').write(s.replace('Files containing CWE-22','Files that contain CWE-22'))"
run M3 "核對表的依據改一個字（憑印象填）" 紅 3

# 少一列。第 6 條會跟著紅，因為亂指從六變五。
python3 -c "
p='verdict.tsv';L=open(p).read().splitlines(True)
open(p,'w').writelines([l for l in L if not l.startswith('CWE-330\t')])"
run M4 "核對表漏記一整個類別" 紅 4,6

# 把一個「亂指」改成「指錯」。兩個詞都在講「它指了個檔」，但一個是給不存在的
# 類別用的、一個是給存在的類別用的。混著填，第 6 條算出來的成績就沒有意義。
python3 -c "
p='verdict.tsv';L=open(p).read().splitlines()
o=[]
for l in L:
    c=l.split('\t')
    if c[0]=='CWE-89': c[4]='指錯'; l='\t'.join(c)
    o.append(l)
open(p,'w').write('\n'.join(o)+'\n')"
run M5 "把「亂指」填成「指錯」" 紅 5,6

python3 -c "
p='FINDINGS.md';s=open(p).read();open(p,'w').write(s.replace('六類裡指到四類','六類裡指到五類'))"
run M6 "結論把命中數寫多一類" 紅 6

# 判定還是「指到」，但它交出的檔案改掉。第 6 條數的只是那一欄填了什麼字，
# 所以只有第 7 條看得出這一列其實沒指對。
python3 -c "
p='verdict.tsv';L=open(p).read().splitlines()
o=[]
for l in L:
    c=l.split('\t')
    if c[0]=='CWE-78': c[3]='server/health.js'; l='\t'.join(c)
    o.append(l)
open(p,'w').write('\n'.join(o)+'\n')"
run M7 "「指到」那一列改成指了別的檔" 紅 7

# 對照組被動過：改名那一輪的答案換成另一個假名。少了第 8 條，
# 「它讀的是內容不是名字」這句話就沒有東西撐著。
python3 -c "
p='hunt-renamed/CWE-78.txt';s=open(p).read()
assert 'server/m4.js' in s
open(p,'w').write(s.replace('server/m4.js','server/m2.js'))"
run M8 "改名對照組指到另一個檔" 紅 8

# 把 playground 那個檔修好。這一條驗的是第 9 條真的在打現在那份原始碼，
# 不是在打腳本裡自己寫死的一份複本。
python3 -c "
p='../../playground/server/tools.js';s=open(p).read()
assert 'const { exec } = require(\"child_process\");' in s
s=s.replace('const { exec } = require(\"child_process\");','const { execFile } = require(\"child_process\");')
s=s.replace('const execAsync = util.promisify(exec);','const execAsync = util.promisify(execFile);')
s=s.replace('await execAsync(\`dig +short \${domain}\`)','await execAsync(\"dig\", [\"+short\", domain])')
s=s.replace('''await execAsync(
    \`convert uploads/\${filename} -resize 200x200 thumbs/\${filename}\`
  )''','''await execAsync(\"convert\", [
    \`uploads/\${filename}\`, \"-resize\", \"200x200\", \`thumbs/\${filename}\`,
  ])''')
open(p,'w').write(s)"
run M9 "把 playground 那個檔改成 execFile（洞不見了）" 紅 9

# 這一條要真的重跑，所以不設 SKIP_RERUN。改的那句不是任何一列的依據，
# 也不是任何一條算得到的東西，所以只有第 10 條的逐字比對抓得到。
python3 -c "
p='hunt/CWE-502.txt';s=open(p).read()
assert 'no deserialization' in s
open(p,'w').write(s.replace('no deserialization','no deserialisation'))"
SKIP_RERUN_THIS=0 run M10 "存檔裡改一個沒人引用的字" 紅 10

python3 -c "
p='../../README.md';L=open(p).read().splitlines(True)
open(p,'w').writelines([l for l in L if not l.startswith('| 27 |')])"
run M11 "索引表少掉這一份 recipe" 紅 11

# 反向對照兩條。第二條問的是「跳過會不會被算成通過」。
run M0a "什麼都不改，第 10 條跳過" 沒有結論
SKIP_RERUN_THIS=0 run M0b "什麼都不改，第 10 條真的跑" 綠

printf '\n通過 %s、沒咬到 %s\n' "$P" "$F"
[ "$F" = 0 ] || exit 1
