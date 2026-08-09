#!/usr/bin/env bash
# verify.sh 全綠只證明現在這份是對的，不證明它在事情壞掉的時候會轉紅。
# 這支跑十一種變化：十種是故障，必須讓 verify.sh 轉紅；
# 一種是共用來源的反向對照，它必須照舊綠，不然那個共用只是宣稱。
# 前四種是原本就有的；後兩種是審查實測 verify.sh 抓不到才補的，補完才抓得到。
# 用法：bash mutations.sh（會用副本，不動你目錄裡的原檔）
set -u
cd "$(dirname "$0")"

CAUGHT=0; MISSED=0; HELD=0
run() { # run <說明> <sed 表達式> <目標檔>
  local work; work=$(mktemp -d)
  cp -R ./* "$work/" 2>/dev/null
  sed -i '' "$2" "$work/$3" 2>/dev/null || sed -i "$2" "$work/$3"
  # sed 沒套進去的時候整條會靜默變成「跑原版」，畫面上長得跟「閘門漏掉」一模一樣。
  # 2026-08-09 就是這樣誤判了一次：BSD sed 吃不下多行表達式，我讀成閘門有洞。
  if cmp -s "./$3" "$work/$3"; then
    MISSED=$((MISSED+1)); printf '  \033[31m壞了\033[0m %s（突變沒套用進去，這條沒測到）\n' "$1"
    rm -rf "$work"; return
  fi
  if bash "$work/verify.sh" > /dev/null 2>&1; then
    MISSED=$((MISSED+1)); printf '  \033[31m漏掉\033[0m %s\n' "$1"
  else
    CAUGHT=$((CAUGHT+1)); printf '  \033[32m抓到\033[0m %s\n' "$1"
  fi
  rm -rf "$work"
}

runpy() { # runpy <說明> <目標檔> <python 片段，變數叫 s>
  local work; work=$(mktemp -d)
  cp -R ./* "$work/" 2>/dev/null
  python3 -c "
import pathlib,sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
$3
p.write_text(s)" "$work/$2"
  if cmp -s "./$2" "$work/$2"; then
    MISSED=$((MISSED+1)); printf '  \033[31m壞了\033[0m %s（突變沒套用進去，這條沒測到）\n' "$1"
    rm -rf "$work"; return
  fi
  # 第四個參數是 NEG 的時候，期望反過來：這種改動「不該」讓 verify 轉紅。
  if bash "$work/verify.sh" > /dev/null 2>&1; then
    if [ "${4:-}" = NEG ]; then
      HELD=$((HELD+1)); printf '  \033[32m照舊綠\033[0m %s\n' "$1"
    else
      MISSED=$((MISSED+1)); printf '  \033[31m漏掉\033[0m %s\n' "$1"
    fi
  else
    if [ "${4:-}" = NEG ]; then
      MISSED=$((MISSED+1)); printf '  \033[31m不該紅\033[0m %s\n' "$1"
      bash "$work/verify.sh" 2>&1 | grep '紅' | head -2
    else
      CAUGHT=$((CAUGHT+1)); printf '  \033[32m抓到\033[0m %s\n' "$1"
    fi
  fi
  rm -rf "$work"
}

# 專門打 probe-table：verify.sh 綠不綠不算數，要看那張表印出什麼。
runtable() { # runtable <說明> <sed 表達式> <目標檔> <表上該出現的字>
  local work; work=$(mktemp -d)
  cp -R ./* "$work/" 2>/dev/null
  sed -i '' "$2" "$work/$3" 2>/dev/null || sed -i "$2" "$work/$3"
  if cmp -s "./$3" "$work/$3"; then
    MISSED=$((MISSED+1)); printf '  \033[31m壞了\033[0m %s（突變沒套用進去）\n' "$1"
    rm -rf "$work"; return
  fi
  if bash "$work/probe-table.sh" after 2>/dev/null | grep -q "$4"; then
    CAUGHT=$((CAUGHT+1)); printf '  \033[32m抓到\033[0m %s\n' "$1"
  else
    MISSED=$((MISSED+1)); printf '  \033[31m漏掉\033[0m %s（表上沒有出現「%s」）\n' "$1" "$4"
  fi
  rm -rf "$work"
}

echo
run "after 的 PATCH 把驗證拿掉"      's/if (body.quantity !== undefined) {/if (body.quantity !== undefined) { order.quantity = body.quantity; return json(res, 200, order); } if (false) {/' after/server.mjs
run "after 改成什麼都擋（含合法值）"  's/if (value < QUANTITY_MIN || value > QUANTITY_MAX)/if (true)/'                after/rules.mjs
run "值域差一個等號（1 跟 10 被誤擋）" 's/value < QUANTITY_MIN || value > QUANTITY_MAX/value <= QUANTITY_MIN || value >= QUANTITY_MAX/' after/rules.mjs
run "before 的 PATCH 補上驗證"        's/if (body.quantity !== undefined) order.quantity = body.quantity;/if (body.quantity !== undefined) { if (body.quantity < 1) return json(res, 400, { error: "bad" }); order.quantity = body.quantity; }/' before/server.mjs
run "表單的 min 佔位被拿掉"           's/min="__MIN__" //'                                                            form.html
run "表單的 type 被換成 text"         's/type="number"/type="text"/'                                                  form.html
runpy "after 的 POST 先存進去再回 400" after/server.mjs '
s = s.replace("    if (bad) return json(res, 400, { error: bad });\n    const newId", "    const newId")
s = s.replace("    return json(res, 201, order);", "    if (bad) return json(res, 400, { error: bad });\n    return json(res, 201, order);")
'
run "after 的 POST 一律拒絕"          's/    if (bad) return json(res, 400, { error: bad });/    if (true) return json(res, 400, { error: bad || "nope" });/' after/server.mjs

# 這一對是「共用來源」那個主張的證據，兩條要一起看。
runpy "after 把界線改成 1 到 20（表單會跟著變，所以不該紅）" after/rules.mjs '
s = s.replace("export const QUANTITY_MAX = 10;", "export const QUANTITY_MAX = 20;")
' NEG
run "before 只改端點界線，表單那份沒跟上"  's/body.quantity > 10/body.quantity > 20/'                                  before/server.mjs

# 這一條打的是 probe-table 自己，不是 verify.sh
runtable "說謊的 PATCH：先存進去再回 400" 's/    if (body.quantity !== undefined) {/    if (body.quantity !== undefined) { order.quantity = body.quantity; return json(res, 400, { error: "quantity must be between 1 and 10" }); } if (false) {/' after/server.mjs '值進去了'

echo
printf '════ 故障 %s 種轉紅、反向對照 %s 種照舊綠，不符 %s 種 ════\n' "$CAUGHT" "$HELD" "$MISSED"
[ "$MISSED" -eq 0 ]
