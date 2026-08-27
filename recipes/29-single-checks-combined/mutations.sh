#!/usr/bin/env bash
# 把 verify.sh 的每一條各弄壞一次，看它會不會判沒過。
#
#   bash mutations.sh
#
# 一條檢查沒有真的抓到過東西，它就只是一段跑得動的程式，不是一道檢查。
#
# 規矩跟前面幾天一樣，兩件事做得比「看離開碼」嚴：
#
# 一、「沒有結論」不算「沒過」。混在一起的話，一台沒裝 jsdom 的機器會把整張表
#    印成全部通過，而其實一條都沒驗到。
# 二、每一列要指定**哪幾條**該沒過，精確比對。只看過不過的話，一個突變可以靠
#    別的檢查沒過來冒充，而它宣稱要驗的那條壞掉也沒人知道。
#
# 這一天的突變多半改在存檔與靶場上，因為要防的東西就在那裡：一條鏈的紀錄
# 最容易壞的方式不是程式寫錯，是它描述的那個東西已經不是現在這個樣子了。
set -u
cd "$(dirname "$0")"
export LC_ALL=C

command -v node >/dev/null 2>&1 || {
  echo "沒有 node。第 3 條要真的打一次，沒有 node 驗不掉，沒有結論。" >&2
  exit 2
}
node -e "import('jsdom')" >/dev/null 2>&1 || {
  echo "node 找不到 jsdom。第 3 條驗不掉，沒有結論。在 repo 根目錄跑 npm install。" >&2
  exit 2
}

PG=../../playground
REC26=../26-what-low-looks-like
REC27=../27-ask-by-cwe
IDX=../../README.md

BACKUP=$(mktemp -d)
cp "$PG/src/render.js" "$BACKUP/render.js"
cp "$PG/src/api.js" "$BACKUP/api.js"
cp "$REC26/first-look/src_render.js.txt" "$BACKUP/f26.txt"
cp "$REC27/hunt/CWE-79.txt" "$BACKUP/f27.txt"
cp chain-exec.mjs "$BACKUP/chain-exec.mjs"
cp "$IDX" "$BACKUP/README.md"
cp chain-ask/answer.txt "$BACKUP/answer.txt"
cp "$PG/src/format.js" "$BACKUP/format.js"
cp chain-ask/repeat.tsv "$BACKUP/repeat.tsv"
restore() {
  cp "$BACKUP/render.js" "$PG/src/render.js"
  cp "$BACKUP/api.js" "$PG/src/api.js"
  cp "$BACKUP/f26.txt" "$REC26/first-look/src_render.js.txt"
  cp "$BACKUP/f27.txt" "$REC27/hunt/CWE-79.txt"
  cp "$BACKUP/chain-exec.mjs" chain-exec.mjs
  cp "$BACKUP/README.md" "$IDX"
  cp "$BACKUP/answer.txt" chain-ask/answer.txt
  cp "$BACKUP/format.js" "$PG/src/format.js"
  cp "$BACKUP/repeat.tsv" chain-ask/repeat.tsv
}
trap 'restore; rm -rf "$BACKUP"' EXIT

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

# 靶場被人順手修好了。整篇建立在那一行上，它不在了每一條都還會通過，
# 而文章描述的東西已經不存在。第 6 條跟著沒過，因為它要在那個檔裡數行號。
python3 -c "
import pathlib
p = pathlib.Path('$PG/src/render.js'); s = p.read_text()
a = 'output.innerHTML = \`<div class=\"answer\">\${answer}</div>\`;'
assert a in s, '找不到那條 sink'
p.write_text(s.replace(a, 'output.textContent = answer;'))"
run M1 "靶場那條 sink 被修掉了" 沒過 1,6

# 鏈的來源那一端被改掉：api.js 不再原樣回傳模型輸出。
python3 -c "
import pathlib
p = pathlib.Path('$PG/src/api.js'); s = p.read_text()
a = 'return data.choices[0].message.content;'
assert a in s
p.write_text(s.replace(a, 'return String(data.choices[0].message.content).slice(0, 0);'))"
run M2 "api.js 不再原樣回傳模型輸出" 沒過 2

# 把 PoC 的判準換成比對字串。這正是 Day 27 那支確認腳本第一版踩過的坑：
# 字串裡出現 payload 只證明那串字被印出來了，證不出瀏覽器會執行它。
python3 -c "
import pathlib
p = pathlib.Path('chain-exec.mjs'); s = p.read_text()
a = '  const img = window.document.querySelector(\"#answer img\");'
assert a in s, '找不到查節點那行'
p.write_text(s.replace(a, '  const img = render(MODEL_ANSWER).includes(\"onerror\") ? {dispatchEvent(){}} : null;'))"
run M3 "PoC 的判準換成比對字串" 沒過 3

# 存檔裡少掉來源那一條。剩下 sink 那條的話，「兩半都看到了」就只剩一半，
# 而那正是這一天的骨幹。
python3 -c "
import pathlib
p = pathlib.Path('$REC26/first-look/src_render.js.txt')
L = [l for l in p.read_text().splitlines(True) if 'CWE-90' not in l]
p.write_text(''.join(L))"
run M4 "Day 26 的存檔少掉來源那一條" 沒過 4

# 把「from user input」改成正確的來源。這一改，「它把來源說錯了」這個論點
# 就沒有東西撐著，而文章整段建立在那句話上。
python3 -c "
import pathlib
p = pathlib.Path('$REC27/hunt/CWE-79.txt'); s = p.read_text()
a = 'directly sets innerHTML from user input'
assert a in s
p.write_text(s.replace(a, 'directly sets innerHTML from the model output'))"
run M5 "Day 27 存檔裡的來源被改成正確的" 沒過 5

# 把模型給的行號改成對的。文章說行號對不上，改對了那個論點就不成立，
# 而第 6 條要抓得到這件事，不能只會抓「行號不見了」。
python3 -c "
import pathlib
p = pathlib.Path('$REC26/first-look/src_render.js.txt'); s = p.read_text()
assert 'CWE-79 | line 4' in s
p.write_text(s.replace('CWE-79 | line 4', 'CWE-79 | line 11'))"
run M6 "存檔裡的行號被改成對的" 沒過 6

# 修法的出處被抹掉。這一天不引入新修法，指回 Day 5 是這一條在守的事。
python3 -c "
import pathlib
p = pathlib.Path('chain-exec.mjs'); s = p.read_text()
a = 'Day 5 教過的修法'
assert a in s
p.write_text(s.replace(a, '一個常見的修法'))"
run M7 "PoC 的註解不再指回 Day 5" 沒過 7

python3 -c "
import pathlib
p = pathlib.Path('$IDX')
L = [l for l in p.read_text().splitlines(True) if not l.startswith('| 29 |')]
p.write_text(''.join(L))"
run M8 "索引表少掉這一份 recipe" 沒過 8

# 那一輪的存檔裡多出「它其實指到了那條鏈」。這是這一天最想防的假訊號：
# 論點整段建立在「它沒指出來」上，存檔一旦相反，第 9 條就該立刻沒過。
python3 -c "
import pathlib
p = pathlib.Path('chain-ask/answer.txt'); s = p.read_text()
p.write_text(s + 'src/render.js -> src/api.js | model output | reaches innerHTML\n')"
run M9 "存檔裡多出它指到那條鏈" 沒過 9

# 十次重跑的紀錄被改成不一致。第 9 條的結論靠「同一問法十次都一樣」，
# 不一致就要改寫成分布，不能繼續寫成「它做不到」。
python3 -c "
import pathlib
p = pathlib.Path('chain-ask/repeat.tsv'); L = p.read_text().splitlines(True)
L[-1] = L[-1].replace(L[-1].split(chr(9))[1].strip(), '0' * 64)
p.write_text(''.join(L))"
run M12 "十次重跑的紀錄變成不一致" 沒過 9

# 多長出一條檔對檔的引用。第 9 條斷言的是邊集合恰好等於那一條，
# 所以多一條也要沒過，不能只會抓「那一條不見了」。
python3 -c "
import pathlib
p = pathlib.Path('$PG/src/format.js'); s = p.read_text()
p.write_text('import { ask } from \"./api.js\";\n' + s)"
run M11 "多長出一條檔對檔的引用" 沒過 9

# 唯一那條檔對檔的引用被拿掉。第 9 條的後半靠它，第 1 條不受影響（sink 那行還在）。
python3 -c "
import pathlib
p = pathlib.Path('$PG/src/render.js'); s = p.read_text()
a = 'import { ask } from \"./api.js\";'
assert a in s
p.write_text(s.replace(a, 'const ask = async (q) => q;'))"
run M10 "render.js 不再引用 api.js" 沒過 9

# 反向對照：改一個不影響任何判定的地方，應該照樣全部通過。
# 沒有它，「什麼都會讓它沒過」跟「它抓得準」分不開。
python3 -c "
import pathlib
p = pathlib.Path('chain-exec.mjs'); s = p.read_text()
p.write_text(s + '\n// 一行不影響行為的註解\n')"
run M0 "chain-exec.mjs 加一行註解" 通過

printf '\n通過 %s、沒抓到 %s\n' "$P" "$F"
[ "$F" = 0 ] || exit 1
