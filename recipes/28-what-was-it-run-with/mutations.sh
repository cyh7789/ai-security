#!/usr/bin/env bash
# 把 verify.sh 的每一條各弄壞一次，看它會不會判沒過。
#
#   bash mutations.sh
#
# 一條檢查沒有真的抓到過東西，它就只是一段跑得動的程式，不是一道檢查。
#
# 規矩跟 Day 26、27 那兩份一樣，兩件事做得比「看離開碼」嚴：
#
# 一、「沒有結論」不算「沒過」。混在一起的話，一台沒有模型的機器會把整張表印成
#    全部通過，而其實一條都沒驗到。
# 二、每一列要指定**哪幾條**該沒過，精確比對。只看過不過的話，一個突變可以靠別的
#    檢查沒過來冒充，而它宣稱要驗的那條壞掉也沒人知道。
#
# 這一天的突變多半改在 stamp.py 本身，因為要防的東西在對帳邏輯裡：一支對帳腳本
# 最容易壞的方式不是算錯雜湊，是某一格根本沒在比。
set -u
cd "$(dirname "$0")"
export LC_ALL=C

MODEL="${ANTARES_MLX:-./antares-1b-mlx}"
[ -r "$MODEL/config.json" ] || {
  echo "找不到模型（$MODEL）。第 2、3、6、7、8 節要真的對一次帳，沒有模型驗不掉，沒有結論。" >&2
  echo "設 ANTARES_MLX 指過去。" >&2
  exit 2
}

IDX=../../README.md
BACKUP=$(mktemp -d)
cp stamp.py stamp.json "${BACKUP}/"
cp ../../playground/src/api.js "${BACKUP}/api.js"
cp "$IDX" "${BACKUP}/README.md"
cp ../27-ask-by-cwe/cwes-firstdraft.tsv "${BACKUP}/"
restore() {
  cp "${BACKUP}/stamp.py" "${BACKUP}/stamp.json" .
  cp "${BACKUP}/README.md" "$IDX"
  cp "${BACKUP}/api.js" ../../playground/src/api.js
  cp "${BACKUP}/cwes-firstdraft.tsv" ../27-ask-by-cwe/
}
trap 'restore; rm -rf "$BACKUP"' EXIT

P=0; F=0
run() {  # $1=編號 $2=說明 $3=期望的判定 $4=期望沒過的條號（逗號分隔，可省）
  local out rc got reds
  out=$(ANTARES_MLX="$MODEL" bash verify.sh 2>&1); rc=$?
  case "$rc" in
    0) got=通過 ;;
    2) got=沒有結論 ;;
    *) got=沒過 ;;
  esac
  reds=$(printf '%s\n' "$out" | awk '
    /^=== / { n=$2 }
    /^  沒過/ { if (!(n in seen)) { seen[n]=1; out = out (out?",":"") n } }
    END { print out }')
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

# 第 1 條顧的是成分表自己的形狀。少一格的話，那一格從此不會被比，
# 而 check 照樣印得出三行通過。
python3 -c "
import json;p='stamp.json';d=json.load(open(p));del d['quant'];json.dump(d,open(p,'w'))"
# 第 2、3、6、7 條跟著沒過，因為那幾條拿現行的 stamp.json 去對帳，
# 而少一格會判成「這份成分表跟現在這支對不起來」。
run M1 "成分表少掉 quant 那格" 沒過 1,2,3,6,7

# 對帳最經典的假通過：把某一格的比較拿掉。五格裡少比一格，
# verify.sh 的第 2 條照樣全部通過，只有那一格自己的專屬檢查看得出來。
python3 -c "
p='stamp.py';s=open(p).read()
a='CELLS = (\"model\", \"quant\", \"prompt\", \"script\", \"corpus\")'
assert a in s, '找不到 CELLS 那行'
open(p,'w').write(s.replace(a,'CELLS = (\"model\", \"prompt\", \"script\", \"corpus\")'))"
# 第 1、2 條都抓不到這一條。第 1 條看的是成分表有沒有五格，而成分表沒被動過；
# 第 2 條期望 rc=0，而少比一格剩下的全對，rc 就是 0。
# 少比一格的假通過是靜默的，只有那一格自己的專屬檢查（第 4 條）與逐格點名的
# 第 3、5 條看得出來。這就是為什麼每一格都要有自己那一條。
run M2 "stamp.py 不再比 quant 那格" 沒過 3,4,5

python3 -c "
p='stamp.py';s=open(p).read()
a='    if a == b:'
assert a in s
open(p,'w').write(s.replace(a,'    if True:'))"
run M3 "對帳改成永遠說對得上" 沒過 3,4,5,6,7

# 反過來的假訊號：永遠說不合。第 2 條會抓到，而它是唯一一條期望「全部通過」的。
python3 -c "
p='stamp.py';s=open(p).read()
a='    if a == b:'
assert a in s
open(p,'w').write(s.replace(a,'    if False:'))"
# 第 7 條抓不到：它驗的是缺東西時走不走 die()，而 die() 沒被動到。
run M4 "對帳改成永遠說不合" 沒過 2,3,4,5,6,7

# 邊界那條：把提示樣板換成整支腳本一起算。這樣改註解會讓 prompt 跟著動，
# 而「今天是提示變了還是程式變了」就分不出來了。
python3 -c "
p='stamp.py';s=open(p).read()
a='blob = prompt_template(script)'
assert a in s, '找不到 blob 那行的呼叫'
open(p,'w').write(s.replace(a,'blob = script.read_text()'))"
# 第 2 條跟著沒過，因為 stamp.json 那格是用舊算法記的，換了算法就對不上。
run M5 "提示那格改成整支腳本一起算" 沒過 2,6,7

# 缺東西被當成不合。這個方向比漏抓嚴重：一台沒有模型的機器會看到整張表全部沒過，
# 而其實一格都沒比到。
python3 -c "
p='stamp.py';s=open(p).read()
a='    sys.exit(2)'
assert a in s
open(p,'w').write(s.replace(a,'    sys.exit(1)',1))"
run M6 "缺東西的離開碼從 2 改成 1" 沒過 9

# 換描述之前那一輪的表被改成跟現在這張一樣。第 3 條那個示範就沒東西撐著了，
# 而「換一段描述，答案就變了」這句話文章跟 README 都寫著。
python3 -c "
import pathlib
p=pathlib.Path('../27-ask-by-cwe/cwes-firstdraft.tsv')
q=pathlib.Path('../27-ask-by-cwe/cwes.tsv')
p.write_text(q.read_text())"
run M7 "換描述前那張表被改成跟現在一樣" 沒過 3

python3 -c "
p='../../README.md';L=open(p).read().splitlines(True)
open(p,'w').writelines([l for l in L if not l.startswith('| 28 |')])"
run M8 "索引表少掉這一份 recipe" 沒過 10

# corpus 那格不再比：改被掃的程式碼就沒有東西抓得到，而那正是第一版的洞。
python3 -c "
p='stamp.py';s=open(p).read()
a='CELLS = (\"model\", \"quant\", \"prompt\", \"script\", \"corpus\")'
assert a in s, '找不到 CELLS 那行'
open(p,'w').write(s.replace(a,'CELLS = (\"model\", \"quant\", \"prompt\", \"script\")'))"
run M9 "stamp.py 不再比 corpus 那格" 沒過 3,7

# 收檔規則跟 hunt.py 分岔，而且總數不變：漏掉 health.js、多收 test/setup.js。
# 只比數量的話這一條會矇混過去，playground/test/setup.js 就在那裡等著。
python3 -c "
p='stamp.py';s=open(p).read()
a='p for p in root.rglob(\"*.js\") if p.is_file() and \"test\" not in p.parts'
assert a in s, '找不到收檔那行'
open(p,'w').write(s.replace(a,'p for p in root.rglob(\"*.js\") if p.is_file() and \"health\" not in p.name'))"
run M10 "corpus 換一組檔案，總數還是七個" 沒過 2,3,8

# 提示那格算了模型讀不到的欄位。人工答案欄 hunt.py 從來沒餵給模型，
# 改它會讓 prompt 誤報不合，而那個方向最糟：把有效的成績單丟掉重跑。
python3 -c "
p='stamp.py';s=open(p).read()
a='.join(rows)'
assert a in s, '找不到 join(rows)'
open(p,'w').write(s.replace(a,'.join([cwes.read_text()])'))"
# 第 6、7 條跟著沒過：它們驗的是「動別的東西時 prompt 不動」，
# 而 stamp.json 存的是新算法的值，換回舊算法整個 prompt 格就對不上了。
run M11 "提示那格改回整份 cwes.tsv" 沒過 2,6,7

# 反向對照：改一個不影響任何判定的地方，應該照樣全部通過。
# 沒有它，「什麼都會讓它沒過」跟「它抓得準」分不開。
python3 -c "
p='stamp.py';s=open(p).read()
open(p,'w').write(s + '\n# 一行不影響行為的註解\n')"
run M0 "stamp.py 加一行註解" 通過

printf '\n通過 %s、沒抓到 %s\n' "$P" "$F"
[ "$F" = 0 ] || exit 1
