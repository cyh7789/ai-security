#!/usr/bin/env bash
# 05 innerHTML 的假綠燈
#
# 跑一個 2x2：兩個版本（before / after）× 兩條攻擊輸入（script / img onerror）。
# 要看的不是「after 全綠」，是 script 那一欄在兩個版本上長得一模一樣。
# 一條在有洞與修好上表現相同的檢查，不是驗證。
#
# 用法：
#   bash verify.sh          跑四格
#   bash verify.sh 2        只跑第 2 格
#
# 需要：bash、python3（起一個本機靜態伺服器）、一個 Chrome 或 Chromium。
# 全部在 mktemp -d 裡進行，不碰你的檔案。

set -u
ONLY="${1:-}"
PASS=0; FAIL=0; SKIP=0
ok()   { printf '  [OK]   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  [SKIP] %s\n' "$1"; SKIP=$((SKIP+1)); }

HERE=$(cd "$(dirname "$0")" && pwd)
WS=$(mktemp -d)
SRV_PID=""
set +m
cleanup() {
  if [ -n "$SRV_PID" ]; then kill "$SRV_PID" 2>/dev/null; wait "$SRV_PID" 2>/dev/null; fi
  rm -rf "$WS"
}
trap cleanup EXIT

# ── 找瀏覽器 ─────────────────────────────────────────────────
CH=""
for c in \
  "$HOME/.cache/puppeteer/chrome-headless-shell/mac_arm-151.0.7922.47/chrome-headless-shell-mac-arm64/chrome-headless-shell" \
  "$(command -v chrome-headless-shell 2>/dev/null)" \
  "$(command -v google-chrome 2>/dev/null)" \
  "$(command -v chromium 2>/dev/null)" \
  "$(command -v chromium-browser 2>/dev/null)" \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" ; do
  [ -n "$c" ] && [ -x "$c" ] && { CH=$c; break; }
done

if [ -z "$CH" ]; then
  cat <<'EOT'
找不到 Chrome 或 Chromium，這支腳本跑不了。

不想為了這個裝一顆瀏覽器的話，同一件事在你現在開著的這個瀏覽器裡就驗得掉。
開 DevTools 的 Console，貼這段：

  const box = document.createElement("div");
  document.body.append(box);

  box.innerHTML = '<script>alert("A")<\/script>';
  console.log("script 標籤進 DOM 了嗎：", !!box.querySelector("script"));

  box.innerHTML = '<img src=x onerror=alert("B")>';

A 不會跳，B 會跳，中間那行印 true。標籤進去了、沒有執行，兩件事同時成立。
那就是「打 <script>alert(1)</script> 沒反應」為什麼不能當成修好了。

再貼這兩行看修法：

  box.textContent = '<img src=x onerror=alert("B")>';
  console.log("img 元素還在嗎：", !!box.querySelector("img"));

不跳，印 false。

（字串裡的 <\/script> 不是打錯。存成 .html 檔的時候，字串中間那個結束標籤
會先把外層的 <script> 區塊關掉。加一個反斜線在 JavaScript 裡是同一個字串。）

以上驗的是機制。要驗你自己那支應用，payload 必須確定抵達 answer：
把 ask() 暫時換成固定回傳那串，不要打聊天輸入框，模型不一定原樣覆述。
判準三件一起看（DOM 裡有沒有 img、alert 有沒有真的跳、Console 有沒有 CSP 違規），
見 README 的「打哪裡」與「什麼情況不適用」。
EOT
  exit 2
fi
printf '瀏覽器：%s\n' "$("$CH" --version 2>/dev/null)"

# ── 架一個最小的頁面，載入 recipe 裡真正那兩份 render.js ──────────
# 不比對程式碼長相，跑它。只有 api.js 換掉，其餘照原樣。
for v in before after; do
  mkdir -p "$WS/$v"
  cp "$HERE/$v/render.js" "$WS/$v/render.js"
  cat > "$WS/$v/api.js" <<'EOF'
// 模型端換成回聲。這是 README「打哪裡」那節教讀者做的同一件事：
// 讓 payload 確定抵達 answer，不必看模型願不願意原樣覆述。
export async function ask(q) {
  return q;
}
EOF
  cat > "$WS/$v/index.html" <<'EOF'
<!doctype html><meta charset="utf-8">
<form id="ask-form"><input name="q" value=""></form>
<div id="answer"></div>
<div id="out"></div>
<script>
window.fired = [];
window.alert = () => window.fired.push("alert");
// payload 從輸入框進去，跟讀者手動打的那條路一樣
const P = { script: '<scr' + 'ipt>window.fired.push("script-tag")</scr' + 'ipt>',
            img:    '<img src=x onerror="window.fired.push(\'img-onerror\')">' };
document.querySelector("input[name=q]").value = P[location.hash.slice(1)] || P.img;
</script>
<script type="module" src="./render.js"></script>
<script>
addEventListener("load", () => {
  document.getElementById("ask-form").dispatchEvent(
    new Event("submit", { cancelable: true }));
  setTimeout(() => {
    const a = document.getElementById("answer");
    document.getElementById("out").textContent =
      "RESULT fired=" + (window.fired.length > 0) +
      " scriptTagInDOM=" + !!a.querySelector("script") +
      " imgInDOM=" + !!a.querySelector("img") +
      " textLen=" + a.textContent.length;
  }, 600);
});
</script>
EOF
done

PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
( cd "$WS" && python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) &
SRV_PID=$!
for _ in $(seq 1 40); do
  curl -sf "http://127.0.0.1:$PORT/before/index.html" >/dev/null 2>&1 && break
  sleep 0.1
done

run() {  # run <before|after> <script|img>
  # 沒有 --no-sandbox。這支載的是自己在 mktemp 裡產的頁面，
  # 但關掉沙箱是把瀏覽器最外層那道隔離拿掉，不該為了省事寫進一份資安 recipe。
  # 在 root 底下或某些容器裡跑不起來的話，換成非 root 使用者，不要加那個旗標。
  "$CH" --headless --disable-gpu --virtual-time-budget=4000 \
        --dump-dom "http://127.0.0.1:$PORT/$1/index.html#$2" 2>/dev/null \
    | grep -o 'RESULT fired=[^<]*' | head -1
}

want() {  # want <格號> <版本> <payload> <期待的 fired> <說明> [額外要出現的字串]
  [ -n "$ONLY" ] && [ "$ONLY" != "$1" ] && return 0
  printf '\n=== %s. %s 版 × %s ===\n' "$1" "$2" "$3"
  R=$(run "$2" "$3")
  printf '  %s\n' "${R:-（沒有輸出，頁面可能沒載起來）}"
  printf '  期待：%s\n' "$5"
  N=0
  printf '%s' "$R" | grep -qF "fired=$4" || { bad "fired 不是 $4"; N=1; }
  if [ "$#" -ge 6 ]; then
    printf '%s' "$R" | grep -qF "$6" || { bad "少了 $6"; N=1; }
  fi
  [ "$N" = 0 ] && ok "$5"
  eval "R$1=\$R"
}

want 1 before script false "有洞卻沒有任何反應，這格就是假綠燈" "scriptTagInDOM=true"
want 2 before img    true  "同一份有洞的程式碼，換一條輸入就打穿了" "imgInDOM=true"
want 3 after  script false "修好之後也不跳。跟第 1 格一模一樣"
want 4 after  img    false "修好之後擋住了，字串原樣留在畫面上" "imgInDOM=false"

# ── 這支腳本真正要說的那句話 ────────────────────────────────
if [ -z "$ONLY" ]; then
  printf '\n=== 5. 兩條輸入的鑑別力 ===\n'
  S1=$(printf '%s' "${R1:-}" | grep -o 'fired=[a-z]*')
  S3=$(printf '%s' "${R3:-}" | grep -o 'fired=[a-z]*')
  S2=$(printf '%s' "${R2:-}" | grep -o 'fired=[a-z]*')
  S4=$(printf '%s' "${R4:-}" | grep -o 'fired=[a-z]*')
  printf '  script：before %s ／ after %s\n' "$S1" "$S3"
  printf '  img   ：before %s ／ after %s\n' "$S2" "$S4"
  N=0
  [ -n "$S1" ] && [ "$S1" = "$S3" ] \
    || { bad "script 那條在兩個版本上結果不同，那這支腳本的前提要重查"; N=1; }
  [ -n "$S2" ] && [ "$S2" != "$S4" ] \
    || { bad "img 那條分不出兩個版本，攻擊集第一條沒有鑑別力"; N=1; }
  [ "$N" = 0 ] && ok "script 分不出兩個版本（所以它只能當對照組），img 分得出來（所以它是驗證）"
fi

printf '\n════════ %s 綠 / %s 紅 / %s 跳過 ════════\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = 0 ]
