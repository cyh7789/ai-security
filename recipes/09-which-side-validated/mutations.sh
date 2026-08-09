#!/usr/bin/env bash
# verify.sh 全綠只證明現在這份是對的，不證明它在事情壞掉的時候會轉紅。
# 這支把八種壞法各做一次，每一種都必須讓 verify.sh 變紅。
# 前四種是原本就有的；後兩種是審查實測 verify.sh 抓不到才補的，補完才抓得到。
# 用法：bash mutations.sh（會用副本，不動你目錄裡的原檔）
set -u
cd "$(dirname "$0")"

CAUGHT=0; MISSED=0
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
  if bash "$work/verify.sh" > /dev/null 2>&1; then
    MISSED=$((MISSED+1)); printf '  \033[31m漏掉\033[0m %s\n' "$1"
  else
    CAUGHT=$((CAUGHT+1)); printf '  \033[32m抓到\033[0m %s\n' "$1"
  fi
  rm -rf "$work"
}

echo
run "after 的 PATCH 把驗證拿掉"      's/if (body.quantity !== undefined) {/if (body.quantity !== undefined) { order.quantity = body.quantity; return json(res, 200, order); } if (false) {/' after/server.mjs
run "after 改成什麼都擋（含合法值）"  's/if (value < 1 || value > 10)/if (true)/'                                    after/server.mjs
run "before 的 PATCH 補上驗證"        's/if (body.quantity !== undefined) order.quantity = body.quantity;/if (body.quantity !== undefined) { if (body.quantity < 1) return json(res, 400, { error: "bad" }); order.quantity = body.quantity; }/' before/server.mjs
run "表單的 min 被拿掉"               's/min="1" //'                                                                  form.html
run "表單的 type 被換成 text"         's/type="number"/type="text"/'                                                  form.html
run "值域差一個等號（1 跟 10 被誤擋）" 's/if (value < 1 || value > 10)/if (value <= 1 || value >= 10)/'                after/server.mjs
runpy "after 的 POST 先存進去再回 400" after/server.mjs '
s = s.replace("    if (bad) return json(res, 400, { error: bad });\n    const newId", "    const newId")
s = s.replace("    return json(res, 201, order);", "    if (bad) return json(res, 400, { error: bad });\n    return json(res, 201, order);")
' 
run "after 的 POST 一律拒絕"          's/    if (bad) return json(res, 400, { error: bad });/    if (true) return json(res, 400, { error: bad || "nope" });/' after/server.mjs

# 第七種試過，故意不放進來：把 after 的兩支端點各自抄一份行內檢查，
# 行為跟現在這份逐位元相同，所以 verify.sh 一條都不會紅，而且它永遠不會紅。
# 那不是 verify.sh 的缺陷，是打一遍這個方法的邊界：
# 它量得到「這個值有沒有被擋」，量不到「規則有沒有一個落點」。
# 後者要用讀的。把它寫成一條會漏掉的突變，等於假裝那是個可以補起來的洞。

echo
printf '════ %s 種抓到 %s 種漏掉 ════\n' "$CAUGHT" "$MISSED"
[ "$MISSED" -eq 0 ]
