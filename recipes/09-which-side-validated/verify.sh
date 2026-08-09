#!/usr/bin/env bash
# 09 驗證：前端擋得住的東西，後端擋不擋得住。
# 用法：bash verify.sh
# 只用 node 內建模組與 curl，不下載任何套件，兩台 server 都綁在 127.0.0.1 的隨機埠上。
set -u
cd "$(dirname "$0")"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \033[32m綠\033[0m %s\n' "$1"; }
no()  { FAIL=$((FAIL+1)); printf '  \033[31m紅\033[0m %s\n' "$1"; }
chk() { # chk <說明> <實際> <期望>
  if [ "$2" = "$3" ]; then ok "$1（$2）"; else no "$1：期望 $3，實際 $2"; fi
}

# 起過的 server PID 記到檔案裡，不記到變數裡。
# 變數的問題是它活在哪個 shell 裡，命令替換一開子 shell 就寫不回來；
# 檔案沒有這個問題，而且它讓「有沒有記到」本身變成可以檢查的東西。
PIDFILE=$(mktemp)
cleanup() { while read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null; done < "$PIDFILE"; }
trap 'cleanup; rm -f "$PIDFILE"' EXIT

# 起好的 port 從 PORT 拿，不要寫成 `P=$(start before)`。
PORT=""
start() { # start <目錄>；成功之後 PORT 就是它的埠
  local log i; log=$(mktemp)
  node "$1/server.mjs" > "$log" 2>&1 &
  echo "$!" >> "$PIDFILE"
  disown 2>/dev/null || true   # 讓 shell 不要在殺掉它的時候印 Terminated
  for i in $(seq 1 50); do
    if grep -q '^PORT=' "$log" 2>/dev/null; then
      PORT=$(sed -n 's/^PORT=//p' "$log" | head -1)
      return 0
    fi
    sleep 0.1
  done
  echo "server 起不來：$1" >&2
  cat "$log" >&2
  return 1
}

code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
body() { curl -s "$@"; }
qty()  { body "http://127.0.0.1:$1/orders/${2:-1}" | sed -n 's/.*"quantity":\([-0-9]*\).*/\1/p'; }
# POST 建立成功會回 id，拿那個 id 讀回來才知道值進不進得去。
newid() { printf '%s' "$1" | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1; }

echo
echo "── before：建立那半有驗，編輯那半沒有 ──"
start before || exit 1
BP=$PORT

# 前端那一份。第一版只 grep 檔案裡有沒有那兩串字，然後印「瀏覽器會擋」。
# 那是假綠燈：把 type 換成 text，min/max 就不生效了，而字串還在，照樣印綠。
# 現在改成從 server 把表單抓下來，而且連 type 一起檢查。
# 「瀏覽器真的會擋」還是要你自己打開那一頁看，這條只證明送到瀏覽器的那份宣告了什麼。
FORM=$(curl -s "http://127.0.0.1:$BP/")
if printf '%s' "$FORM" | grep -q 'type="number"' \
   && printf '%s' "$FORM" | grep -q 'min="1"' \
   && printf '%s' "$FORM" | grep -q 'max="10"'; then
  ok "server 供得出表單，而且它宣告了 type=number min=1 max=10"
else
  no "表單抓不到，或少了 type=number／min／max，後面的對照就沒有意義"
fi

chk "POST quantity=-5 被擋" \
  "$(code -X POST -H 'content-type: application/json' -d '{"itemId":"sku-1","quantity":-5}' "http://127.0.0.1:$BP/orders")" 400

chk "PATCH quantity=-5 沒被擋" \
  "$(code -X PATCH -H 'content-type: application/json' -d '{"quantity":-5}' "http://127.0.0.1:$BP/orders/1")" 200

# 狀態碼只說「它回話了」。要證明繞過成立，得把那筆讀回來看值。
chk "讀回來確認真的寫進去了" "$(qty "$BP")" -5

echo
echo "── after：兩支端點對同一個值給同一個答案 ──"
start after || exit 1
AP=$PORT

# POST 這一欄以前只比狀態碼。跟 PATCH 那次是同一個洞：
# 把 POST 改成「先存進去、再回 400」，狀態碼照樣是 400，而那筆訂單真的建出來了。
POST_BODY=$(body -X POST -H 'content-type: application/json' -d '{"itemId":"sku-1","quantity":-5}' "http://127.0.0.1:$AP/orders")
chk "POST quantity=-5 被擋" \
  "$(code -X POST -H 'content-type: application/json' -d '{"itemId":"sku-1","quantity":-5}' "http://127.0.0.1:$AP/orders")" 400
# 不能只看回應裡有沒有 id：說謊的那種寫法會存進去然後回一個不帶 id 的 400。
# 這台一開始有一筆訂單，所以建成功的下一個 id 是 2。被擋的話 2 必須不存在。
chk "被擋的 POST 沒有偷偷建出訂單" \
  "$(code "http://127.0.0.1:$AP/orders/2")" 404

PATCH_BODY=$(body -X PATCH -H 'content-type: application/json' -d '{"quantity":-5}' "http://127.0.0.1:$AP/orders/1")
chk "PATCH quantity=-5 被擋" \
  "$(code -X PATCH -H 'content-type: application/json' -d '{"quantity":-5}' "http://127.0.0.1:$AP/orders/1")" 400

# 擋下來還不夠，要擋在對的原因上。500 或 404 也是「沒改成」，但那是壞掉不是驗證。
if printf '%s' "$PATCH_BODY" | grep -q 'quantity must be between 1 and 10'; then
  ok "擋下來的原因是值域檢查，不是伺服器壞了"
else
  no "擋下來了，但原因不是值域檢查：$PATCH_BODY"
fi

chk "被擋之後那筆沒有被改動" "$(qty "$AP")" 2

# 正對照：全部擋掉也會讓上面幾條變綠。要證明合法的那些還過得去。
# 邊界值 1 跟 10 一定要打。只打中間的 3，`<= 1 || >= 10` 這種差一個等號的寫法照樣全綠。
for v in 3 1 10; do
  code -X PATCH -H 'content-type: application/json' -d "{\"quantity\":$v}" "http://127.0.0.1:$AP/orders/1" > /dev/null
  chk "合法的 quantity=$v 仍然改得動" "$(qty "$AP")" "$v"
done
# POST 也要有自己的正對照，不然「POST 一律拒絕」會讓上面那兩條變綠。
OK_BODY=$(body -X POST -H 'content-type: application/json' -d '{"itemId":"sku-1","quantity":4}' "http://127.0.0.1:$AP/orders")
OK_ID=$(newid "$OK_BODY")
if [ -n "$OK_ID" ]; then
  chk "合法的 POST 建得出訂單，而且值是對的" "$(qty "$AP" "$OK_ID")" 4
else
  no "合法的 POST 沒有建出訂單：$OK_BODY"
fi

echo
echo "── 收尾：這支腳本自己有沒有收乾淨 ──"
# 第一版沒有這條，於是 `BP=$(start before)` 的子 shell 問題漏了兩支 node，畫面上九條全綠。
# 第二版有這條但它是假的：那個寫法連 PID 都沒記到，迴圈跑零次也印綠。
# 所以這裡先驗「記到了幾支」再驗「還活著幾支」，前者不對的話後者沒有意義。
STARTED=$(grep -c . "$PIDFILE" 2>/dev/null); STARTED=${STARTED:-0}
chk "起過的 server 都有被記下來" "$STARTED" 2
cleanup
sleep 0.3
LEFT=0
while read -r p; do [ -n "$p" ] && kill -0 "$p" 2>/dev/null && LEFT=$((LEFT+1)); done < "$PIDFILE"
chk "跑完沒有留下背景行程" "$LEFT" 0

printf '════ %s 綠 %s 紅 ════\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
