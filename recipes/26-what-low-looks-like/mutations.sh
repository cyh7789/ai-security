#!/usr/bin/env bash
# 把 verify.sh 的每一條各弄壞一次，看它會不會紅。
#
#   bash mutations.sh
#
# 一條檢查沒有被咬過，它就只是一段跑得動的程式，不是一道閘。
#
# 這一份的突變大多在改**存檔與核對表**，不是改腳本。理由是這一天要防的東西
# 就在那裡：一份核對表最容易壞的方式不是寫錯程式，是核的人憑印象填一格。
#
# 兩件事這裡刻意做得比「看離開碼」嚴：
#
# 一、「沒有結論」不算「紅」。混在一起的話，一台沒有模型的機器會把整張表
#    印成十條通過，而其實一條都沒驗到（2026-08-25 實測）。
# 二、每一列要指定**哪幾條**該紅，而且是精確比對。只看顏色的話，一個突變
#    可以靠別條紅來冒充，而它宣稱要驗的那條其實壞掉也沒人知道：把第 10 條的
#    比對挖空，舊版這張表照樣十三列全通過（同日實測）。
set -u
cd "$(dirname "$0")"
export LC_ALL=C

MODEL="${ANTARES_MLX:-./antares-1b-mlx}"
[ -r "$MODEL/config.json" ] || {
  echo "找不到模型（$MODEL）。M10 要真的重跑一輪，沒有模型這張表驗不掉，沒有結論。" >&2
  echo "設 ANTARES_MLX 指過去。" >&2
  exit 2
}

BACKUP=$(mktemp -d)
cp verdict.tsv POSITIONING.md "${BACKUP}/"
cp -R first-look "${BACKUP}/first-look"
PGNEW=../../playground/src/_mutation_probe.js
restore() {
  cp "${BACKUP}/verdict.tsv" "${BACKUP}/POSITIONING.md" .
  rm -rf first-look; cp -R "${BACKUP}/first-look" first-look
  rm -f "$PGNEW"
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

printf 'export function noop() { return 1; }\n' > "$PGNEW"
run M1 "playground 多一個存檔沒收的 .js" 紅 1

: > first-look/src_render.js.txt
run M2 "把一份原始輸出清空" 紅 2,4,5

python3 -c "
import json;p='first-look/run.json';d=json.load(open(p));d['total_seconds']=99.9;json.dump(d,open(p,'w'))"
run M3 "存檔的總秒數改掉，逐檔不動" 紅 3,7

# 只改一個字：把 sanitization 改成 validation。核對表看起來照樣像有引原句。
python3 -c "
p='verdict.tsv';s=open(p).read();open(p,'w').write(s.replace('without sanitization.','without validation.'))"
run M4 "核對表的依據改一個字（憑印象填）" 紅 4,5

python3 -c "
p='verdict.tsv';L=open(p).read().splitlines(True)
open(p,'w').writelines([l for l in L if 'CWE-90 | line 9' not in l])"
run M5a "核對表漏記一條模型多吐的候選" 紅 5,8

# 刪掉那條誤報、再補一列重記已經記過的候選。兩邊的**條數**還是一樣，
# 只比計數的版本會全綠，而誤報數會從 1 掉到 0。
python3 -c "
p='verdict.tsv';L=open(p).read().splitlines()
o=[]
for l in L:
    if l.startswith('乾淨\tsrc/format.js'): continue
    o.append(l)
o.append('多出來\tsrc/render.js\t重記一次\tCWE-79\t重複\tCWE-79\t4\t11\tCWE-79 | line 4 | Sets innerHTML to user-supplied content without sanitization.\t-')
open(p,'w').write('\n'.join(o)+'\n')"
run M5b "刪掉誤報那列、補一列重記，總數不變" 紅 5,7,8

# 反向關鍵字是填表的人自己選的。填一個原始碼裡根本沒有的字，
# 「它沒講到這件事」就變成永遠成立。
python3 -c "
p='verdict.tsv';s=open(p).read();open(p,'w').write(s.replace('\tuser_id\n','\tzzzznope\n'))"
run M6a "反向關鍵字填一個原始碼裡沒有的字" 紅 6

# 反過來：填一個候選行裡真的出現過的字，那一列的判定就不成立了。
python3 -c "
p='verdict.tsv';s=open(p).read();open(p,'w').write(s.replace('\terr.message\n','\tfile\n'))"
run M6b "反向關鍵字填一個候選行裡有的字" 紅 6

python3 -c "
p='POSITIONING.md';s=open(p).read();open(p,'w').write(s.replace('指出三個','指出四個'))"
run M7a "聲明把命中數寫多一個" 紅 7

python3 -c "
p='POSITIONING.md';s=open(p).read();open(p,'w').write(s.replace('33.1 秒','34.2 秒'))"
run M7b "聲明的秒數改成規格裡那個沒有來源的數字" 紅 7

# 讓 innerHTML 那列的實際行號等於模型寫的 4，也就是「它其實指對了」。
python3 -c "
p='verdict.tsv';L=open(p).read().splitlines()
o=[]
for l in L:
    c=l.split('\t')
    if len(c)>8 and c[1]=='src/render.js' and c[6]=='4': c[7]='4'; l='\t'.join(c)
    o.append(l)
open(p,'w').write('\n'.join(o)+'\n')"
run M8 "多一條行號其實指對了，聲明沒跟著改" 紅 8

python3 -c "
p='POSITIONING.md';s=open(p).read();open(p,'w').write(s.replace('## 所以我怎麼用它','## 雜項'))"
run M9 "聲明少一節「所以我怎麼用它」" 紅 9

# 這一條要真的重跑，所以不設 SKIP_RERUN。改的那句散文不是候選行、也沒有被
# 任何一列的依據引到，所以前九條看不見它，只有第 10 條的逐字比對抓得到。
python3 -c "
p='first-look/src_api.js.txt';s=open(p).read()
assert 'hard-coded secrets' in s
open(p,'w').write(s.replace('hard-coded secrets','hardcoded secrets'))"
SKIP_RERUN_THIS=0 run M10 "存檔裡改一個沒人引用的字" 紅 10

# 反向對照兩條。第二條問的是「跳過會不會被算成通過」。
run M0a "什麼都不改，第 10 條跳過" 沒有結論
SKIP_RERUN_THIS=0 run M0b "什麼都不改，第 10 條真的跑" 綠

printf '\n通過 %s、沒咬到 %s\n' "$P" "$F"
[ "$F" = 0 ] || exit 1
