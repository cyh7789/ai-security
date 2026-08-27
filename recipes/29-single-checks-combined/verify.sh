#!/usr/bin/env bash
# 這一天的檢查。跑：bash verify.sh
#
# 離開碼照 Day 22 那份公約：0 全部通過、1 有沒過的、2 環境不到位或有節被跳過，沒有結論。
#
# 這一天的主張是：模型把鏈的兩半都看到了，各自列成一條，而它們是同一條。
# 所以底下沒有一條在讀文章的形容詞，全部是拿 Day 26 與 Day 27 的存檔重新算一次，
# 再把那條鏈在真的 HTML 引擎裡打一遍。
set -u
cd "$(dirname "$0")"
export LC_ALL=C
G=0; B=0; S=0
case_() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  通過\t%s\n' "$1"; G=$((G+1)); }
bad()  { printf '  沒過\t%s\n' "$1"; B=$((B+1)); }
skip() { printf '  沒有結論\t%s\n' "$1"; S=$((S+1)); }

PG=../../playground
REC26=../26-what-low-looks-like
REC27=../27-ask-by-cwe
SINK=$PG/src/render.js
SRC=$PG/src/api.js

# ─────────────────────────────────────────────────────────────
case_ "1 靶場那條 sink 還在，而且是文章寫的那一行"
# 這一天整條鏈建立在 render.js 現在那一行上。它被修掉了的話，
# 底下每一條都還會通過，而文章描述的東西已經不存在了。
if [ ! -r "$SINK" ]; then
  bad "找不到 $SINK"
else
  LINE=$(grep -n 'output.innerHTML = `<div class="answer">${answer}</div>`' "$SINK" | cut -d: -f1)
  if [ -n "$LINE" ]; then
    ok "render.js 第 ${LINE} 行還是那條 innerHTML"
  else
    bad "render.js 裡找不到那條 innerHTML，靶場被改過了"
  fi
fi

case_ "2 鏈的另一端也還在：api.js 回傳模型輸出"
if grep -q 'return data.choices\[0\].message.content' "$SRC"; then
  ok "api.js 還是把模型回答原樣回傳"
else
  bad "api.js 的回傳改過了，鏈的來源那一端不成立"
fi

case_ "3 這條鏈在真的 HTML 引擎裡走得通，而修法擋得下來"
if ! command -v node >/dev/null 2>&1; then
  skip "沒有 node，這一條驗不掉"
elif ! node -e "import('jsdom')" >/dev/null 2>&1; then
  # 問 node 找不找得到，不要找目錄：jsdom 裝在 repo 根目錄的 node_modules，
  # 寫死相對路徑的話換個安裝位置這一條就變成永遠沒有結論。
  skip "node 找不到 jsdom（在 repo 根目錄跑 npm install），這一條驗不掉"
else
  OUT=$(node chain-exec.mjs 2>&1); RC=$?
  if [ "$RC" = 0 ] \
     && printf '%s' "$OUT" | grep -q '真的執行了（XSS 成立）' \
     && printf '%s' "$OUT" | grep -q '沒造出可執行節點'; then
    ok "有洞版的 onerror 真的跑了，修好版只剩文字"
  else
    bad "rc=$RC，輸出：$(printf '%s' "$OUT" | tr '\n' '｜')"
  fi
fi

case_ "4 Day 26 那一輪，模型在同一個檔上列了鏈的兩半"
F26=$REC26/first-look/src_render.js.txt
if [ ! -r "$F26" ]; then
  bad "找不到 $F26"
else
  M=0
  # 這兩句是這一天的骨幹：一句是 sink，一句是來源，它列成兩條獨立的問題。
  grep -qF 'Sets innerHTML to user-supplied content without sanitization.' "$F26" \
    || { bad "存檔裡找不到 sink 那一條"; M=1; }
  grep -qF 'Calls an external API (ask) without validating or sanitizing its output.' "$F26" \
    || { bad "存檔裡找不到來源那一條"; M=1; }
  [ "$M" = 0 ] && ok "兩條都在，而且是分開列的"
fi

case_ "5 Day 27 那一輪，它把來源說成使用者輸入"
F27=$REC27/hunt/CWE-79.txt
if [ ! -r "$F27" ]; then
  bad "找不到 $F27"
else
  if grep -qF 'directly sets innerHTML from user input' "$F27"; then
    ok "逐字：directly sets innerHTML from user input"
  else
    bad "存檔裡找不到那句，來源判斷那個論點沒有東西撐著"
  fi
fi

case_ "6 那兩個行號真的是錯的"
# 文章說模型給的行號對不上。這要數出來，不能用講的。
if [ ! -r "$SINK" ] || [ ! -r "$F26" ]; then
  skip "缺檔案，數不了"
else
  SAID_SINK=$(grep -oE 'CWE-79 \| line [0-9]+' "$F26" | grep -oE '[0-9]+$')
  SAID_SRC=$(grep -oE 'CWE-90 \| line [0-9]+' "$F26" | grep -oE '[0-9]+$')
  REAL_SINK=$(grep -n 'answer">\${answer}' "$SINK" | cut -d: -f1)
  REAL_SRC=$(grep -n 'await ask(question)' "$SINK" | cut -d: -f1)
  M=0
  [ -n "$SAID_SINK" ] && [ -n "$REAL_SINK" ] || { bad "撈不到行號"; M=1; }
  [ "$SAID_SINK" = "$REAL_SINK" ] && { bad "sink 的行號其實是對的（都是 $SAID_SINK），文章那個論點不成立"; M=1; }
  [ "$SAID_SRC" = "$REAL_SRC" ] && { bad "來源的行號其實是對的（都是 $SAID_SRC），文章那個論點不成立"; M=1; }
  [ "$M" = 0 ] && ok "它說 line ${SAID_SINK} 與 line ${SAID_SRC}，實際在 ${REAL_SINK} 與 ${REAL_SRC}"
fi

case_ "7 修法跟 Day 5 教的是同一件事"
# 這一天不引入新修法。Day 5 那篇教的是不要把它當標記解析，
# 這裡的 PoC 用逃逸示範同一條分界。
D5=../05-innerhtml-fake-green
if [ ! -d "$D5" ]; then
  bad "找不到 recipe 05"
elif grep -rqF 'textContent' "$D5" && grep -qF 'Day 5 教過的修法' chain-exec.mjs; then
  ok "recipe 05 講的是 textContent，這支的註解指回那裡"
else
  bad "修法沒有指回 Day 5，這一天變成在教一個新東西"
fi

case_ "8 索引表收了這一份"
if grep -q '29-single-checks-combined' ../../README.md; then
  ok "README 的索引表有這一列"
else
  bad "README 的索引表沒有這一份 recipe"
fi

case_ "9 直接問它組合，它給的兩對都不是真的資料流"
# 前兩輪是逐檔問與逐類問，兩種問法都預設答案落在單一位置上，
# 所以「它看不到組合」有可能是問法決定的。這一條守的是把那個變因拿掉的那一輪。
CA=chain-ask/answer.txt
if [ ! -r "$CA" ]; then
  skip "還沒跑過 chain-ask.py（要本機模型），這一條驗不掉"
else
  M=0
  grep -qF 'server/files.js -> server/tools.js' "$CA" \
    || { bad "存檔裡沒有那一對，文章引的東西不在"; M=1; }
  grep -qF 'server/files.js -> src/format.js' "$CA" \
    || { bad "存檔裡沒有第二對"; M=1; }
  grep -qF 'src/render.js -> src/api.js' "$CA" \
    && { bad "它其實有指出那條鏈，文章那個論點不成立"; M=1; }
  # 數的是「邊」，不是「有引用語句的檔案數」。後者會把 orders.js 引用外部的 db
  # 也算進去，印出一個跟結論打架的數字（外部審查在這裡指出檢查沒真的守住）。
  EDGES=$(python3 edges.py "$PG" | tr '\n' '|')
  [ "$EDGES" = "src/render.js -> src/api.js|" ] \
    || { bad "七個檔之間的邊不是只有那一條，是：${EDGES:-無}"; M=1; }
  # 單次執行推不出「它做不到」。同一個問法重跑十次的雜湊存在 repeat.tsv，
  # 十次要全部一致，而且要跟現在這份存檔對得上。
  R=chain-ask/repeat.tsv
  if [ ! -r "$R" ]; then
    bad "沒有 repeat.tsv，那一輪只跑過一次"; M=1
  else
    H=$(shasum -a 256 "$CA" | cut -d' ' -f1)
    NR=$(grep -c '^run' "$R")
    SAME=$(awk '$1 ~ /^run/ {print $2}' "$R" | sort -u | wc -l | tr -d ' ')
    [ "$NR" -ge 10 ] || { bad "repeat.tsv 只有 $NR 次，不夠推出「它做不到」"; M=1; }
    [ "$SAME" = 1 ] || { bad "十次重跑的輸出不一致（$SAME 種），結論要改寫成分布"; M=1; }
    grep -qF "$H" "$R" || { bad "repeat.tsv 記的雜湊跟現在這份存檔對不上"; M=1; }
  fi
  [ "$M" = 0 ] && ok "兩對都不是真的資料流、唯一那條它沒指出來，同一問法重跑十次逐位元相同"
fi

# ─────────────────────────────────────────────────────────────
printf '\n通過 %s、沒過 %s、沒有結論 %s\n' "$G" "$B" "$S"
[ "$B" = 0 ] || exit 1
[ "$S" = 0 ] || exit 2
exit 0
