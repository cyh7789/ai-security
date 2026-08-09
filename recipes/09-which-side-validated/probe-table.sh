#!/usr/bin/env bash
# 產出「欄位 × 驗證位置」對照表。
# 用法：bash probe-table.sh before   （或 after）
#
# 這張表不是讀程式碼推出來的，是實際打過每一個位置之後記下來的。
# 讀程式碼會告訴你「這裡有一段檢查」，只有打過才知道那段檢查有沒有攔到這個值。
#
# 而且判定不看狀態碼，看值。第一版是看狀態碼的，那是一個假綠燈：
# 把 PATCH 改成「先寫進去、再回 400」，表上兩格都會印「擋下」，而資料真的變成 -5。
# 一張看起來查過的表比沒有表更糟，因為你會拿它去填自己的清單。
set -u
cd "$(dirname "$0")"
DIR="${1:-before}"
BAD=-5

log=$(mktemp)
node "$DIR/server.mjs" > "$log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
for _ in $(seq 1 50); do grep -q '^PORT=' "$log" && break; sleep 0.1; done
PORT=$(sed -n 's/^PORT=//p' "$log" | head -1)
[ -n "${PORT:-}" ] || { echo "server 起不來"; cat "$log"; exit 2; }

qty() { curl -s "http://127.0.0.1:$PORT/orders/$1" | sed -n 's/.*"quantity":\(-\{0,1\}[0-9]*\).*/\1/p'; }

patch_verdict() {
  local was now code
  was=$(qty 1)
  code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH -H 'content-type: application/json' \
           -d "{\"quantity\":${BAD}}" "http://127.0.0.1:$PORT/orders/1")
  now=$(qty 1)
  if [ "${now}" = "${BAD}" ]; then echo "值進去了 (${code})"
  elif [ "${was}" = "${now}" ]; then echo "值沒進去 (${code})"
  else echo "要人看 (${code})"; fi
}

post_verdict() {
  local body code id
  body=$(curl -s -w '\n%{http_code}' -X POST -H 'content-type: application/json' \
           -d "{\"itemId\":\"sku-1\",\"quantity\":${BAD}}" "http://127.0.0.1:$PORT/orders")
  code=$(printf '%s' "${body}" | tail -1)
  id=$(printf '%s' "${body}" | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1)
  # 回應說建立成功還不算數，要拿那個 id 讀回來看值。
  # 沒有 id 的時候不能直接說「值沒進去」：那有可能是它存了但不告訴你 id。
  # 分不出來就要說分不出來，這張表上「我沒查到」跟「沒有」不能印成同一格。
  if [ -n "${id}" ]; then
    if [ "$(qty "${id}")" = "${BAD}" ]; then echo "值進去了 (${code})"; else echo "值沒進去 (${code})"; fi
  elif [ "${code}" = "400" ] || [ "${code}" = "422" ]; then
    echo "值沒進去 (${code})"
  else
    echo "查不到 (${code})"
  fi
}

front() { # 前端那一份是宣告在 HTML 上的，直接讀屬性
  # 連 type 一起看。min/max 對 type="text" 不生效，只 grep 那兩個屬性
  # 會在前端那道已經死掉的時候照樣印出一個很像有在擋的字串。
  local f; f=$(grep -o 'type="[a-z]*" min="[0-9]*" max="[0-9]*"' form.html | head -1 | tr -d '"' | tr -s ' ')
  case "${f}" in
    "type=number"*) printf '%s' "${f#type=number }" ;;
    "") printf '沒宣告' ;;
    *)  printf '%s（min/max 對這個 type 不生效）' "${f}" ;;
  esac
}

printf '\n%s 的對照表（送進去的值：quantity = %s，每一格都讀回來確認過）\n\n' "$DIR" "$BAD"
printf '| 欄位 | 前端宣告 | 建立 POST | 編輯 PATCH |\n'
printf '| %s | %s | %s | %s |\n' quantity "$(front)" "$(post_verdict)" "$(patch_verdict)"
printf '\n後面那兩格都要「值沒進去」，這個欄位才有規則。\n'
printf '第一格是前端宣告了什麼，它擋不擋不影響結論，因為它在使用者那一邊。\n\n'
