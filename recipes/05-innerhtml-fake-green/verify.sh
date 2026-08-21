#!/usr/bin/env bash
# 05 innerHTML 的假綠燈
#
# 兩組實驗：
#   1 到 5 格  兩個版本（before / after）× 兩條攻擊輸入（script / img onerror）。
#              要看的不是「after 全綠」，是 script 那一欄在兩個版本上長得一模一樣。
#              一條在有洞與修好上表現相同的檢查，不是驗證。
#   第 6 節    同一份 before/render.js，換五種模型回法（原樣、markdown 圍籬、
#              行內反引號、HTML escape、拒答）。圍籬擋不住，只有 escape 擋得住。
#   第 7 節    同一段程式碼放在有 CSP 與沒有 CSP 的頁面上。被 CSP 擋掉的時候
#              事件沒發生，但那個 img 元素還在 DOM 裡，所以判準要看元素不看事件。
#
# 用法：
#   bash verify.sh          全部
#   bash verify.sh 2        只跑第 2 格
#   bash verify.sh 6        只跑五臂那節
#
# 需要：bash、python3（起一個本機靜態伺服器）、一個 Chrome 或 Chromium。
# 全部在 mktemp -d 裡進行：頁面、伺服器根目錄、Chrome 的設定檔都在裡面，跑完刪掉。

set -u
ONLY="${1:-}"
# 沒有這一段的話，`bash verify.sh 8` 一節都不會跑，然後印 0 綠 0 紅、結束碼 0。
# 一份講假綠燈的腳本自己發假綠燈。不認得的節號是錯誤，不是「沒事」。
case "$ONLY" in
  ''|[1-7]) ;;
  *) printf '不認得的節號：%s\n用法：bash verify.sh [1-7]，不給參數就全部跑\n' "$ONLY" >&2
     exit 2 ;;
esac
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
  "$(ls -d "$HOME"/.cache/puppeteer/chrome-headless-shell/*/chrome-headless-shell-mac-arm64/chrome-headless-shell 2>/dev/null | sort -V | tail -1)" \
  "$(ls -d "$HOME"/.cache/puppeteer/chrome-headless-shell/*/chrome-headless-shell-linux64/chrome-headless-shell 2>/dev/null | sort -V | tail -1)" \
  "$(command -v chrome-headless-shell 2>/dev/null)" \
  "$(command -v google-chrome 2>/dev/null)" \
  "$(command -v chromium 2>/dev/null)" \
  "$(command -v chromium-browser 2>/dev/null)" \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" ; do
  [ -n "$c" ] && [ -x "$c" ] && { CH=$c; break; }
done

# 挑到完整版 Chrome 的話先講清楚。2026-08-21 踩過：上面第一個候選原本把
# puppeteer 的版本號寫死（mac_arm-151.0.7922.47），它自己升到 152 之後那個路徑
# 就不存在，一路掉到這裡，而完整版 Chrome 在這台機器上起不來也不會結束
# （Trying to load the allocator multiple times），26 個檢查全部拿不到結果，
# 跑滿 500 秒才紅，訊息完全不指向真正的原因。
case "$CH" in
  *chrome-headless-shell) : ;;
  *) printf '  [i] 用的是完整版瀏覽器 %s，不是 chrome-headless-shell。\n' "$CH"
     printf '      它起不來的話先跑 npx @puppeteer/browsers install chrome-headless-shell@stable\n' ;;
esac

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
  console.log("img 元素在 DOM 裡嗎：", !!box.querySelector("img"));

這一頁沒有用 CSP 禁掉 inline 事件處理器的話：A 不跳、B 會跳，兩行都印 true。
標籤進去了、沒有執行，這兩件事同時成立，那就是「打 <script>alert(1)</script>
沒反應」為什麼不能當成修好了。

B 沒跳不要當成安全。先看第二行印什麼、再看 Console 有沒有 CSP 違規訊息：
img 還在 DOM 裡就代表這一層照樣把字串解析成 HTML，只是這一條 payload 被環境擋了。

再貼這兩行看修法：

  box.textContent = '<img src=x onerror=alert("B")>';
  console.log("img 元素還在嗎：", !!box.querySelector("img"));

印 false，畫面上出現的是那串字本身。

（字串裡的 <\/script> 不是打錯。存成 .html 檔的時候，字串中間那個結束標籤
會先把外層的 <script> 區塊關掉。加一個反斜線在 JavaScript 裡是同一個字串。）

以上驗的是機制。要驗你自己那支應用，payload 必須確定抵達 answer：
把 ask() 暫時改成回聲，不要打聊天輸入框，模型不一定原樣覆述。
判準看 DOM 裡有沒有 img，不要只看 alert，見 README 的「打哪裡」與「什麼情況不適用」。
EOT
  exit 2
fi
printf '瀏覽器：%s\n' "$("$CH" --version 2>/dev/null)"

# ── 產一份測試站台 ───────────────────────────────────────────
# 不比對程式碼長相，跑它。只有 api.js 換掉，render.js 一個字都沒動。
#   before/ after/      payload 從輸入框進去，ask() 是回聲（讀者手動走的那條路）
#   m-before/ m-after/  payload 由模型端決定形狀，五種回法（第 6 節）
mk_site() {  # mk_site <目錄> <來源版本> <api.js 內容檔>
  mkdir -p "$WS/$1"
  cp "$HERE/$2/render.js" "$WS/$1/render.js"
  cp "$3" "$WS/$1/api.js"
}

cat > "$WS/api-echo.js" <<'EOF'
// 模型端換成回聲。這是 README「打哪裡」那節教讀者做的同一件事：
// 讓 payload 確定抵達 answer，不必看模型願不願意原樣覆述。
export async function ask(q) {
  return q;
}
EOF

cat > "$WS/api-arms.js" <<'EOF'
// 五種模型回法。同一條 payload，差別只在模型把它包成什麼形狀。
const P = '<img src=x onerror="window.fired.push(\'img-onerror\')">';
const ARMS = {
  raw:    () => P,
  fence:  () => '```html\n' + P + '\n```',
  inline: () => '`' + P + '`',
  escape: () => P.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'),
  prose:  () => '我不能提供那段程式碼，那看起來像是攻擊字串。',
};
export async function ask() {
  return (ARMS[location.hash.slice(1)] || ARMS.raw)();
}
EOF

cat > "$WS/page.html" <<'EOF'
<!doctype html><meta charset="utf-8">
<form id="ask-form"><input name="q" value=""></form>
<div id="answer"></div>
<div id="out"></div>
<script>
window.fired = [];
window.alert = () => window.fired.push("alert");
// payload 從輸入框進去，跟讀者手動打的那條路一樣。
// 五臂那組不吃這個（模型端自己決定回什麼），輸入框留空就好。
const P = { script: '<scr' + 'ipt>window.fired.push("script-tag")</scr' + 'ipt>',
            img:    '<img src=x onerror="window.fired.push(\'img-onerror\')">' };
const want = P[location.hash.slice(1)];
if (want) document.querySelector("input[name=q]").value = want;
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

# 第 7 節用：同一段程式碼，一頁沒有 CSP、一頁有。不經過 render.js，
# 因為要量的是瀏覽器對 inline 事件處理器的處置，不是這支應用的修法
for v in nocsp withcsp; do
  mkdir -p "$WS/$v"
  cat > "$WS/$v/h.js" <<'EOF'
window.fired = [];
addEventListener("load", () => {
  const box = document.getElementById("answer");
  box.innerHTML = '<img src=x onerror="window.fired.push(\'img-onerror\')">';
  setTimeout(() => {
    document.getElementById("out").textContent =
      "RESULT fired=" + (window.fired.length > 0) +
      " imgInDOM=" + !!box.querySelector("img");
  }, 500);
});
EOF
done
printf '<!doctype html><meta charset="utf-8">\n<div id="answer"></div><div id="out"></div><script src="./h.js"></script>\n' > "$WS/nocsp/index.html"
{ printf '<!doctype html><meta charset="utf-8">\n'
  printf '<meta http-equiv="Content-Security-Policy" content="default-src %s; script-src %s">\n' "'none'" "'self'"
  printf '<div id="answer"></div><div id="out"></div><script src="./h.js"></script>\n'
} > "$WS/withcsp/index.html"

for pair in "before:before:api-echo.js" "after:after:api-echo.js" \
            "m-before:before:api-arms.js" "m-after:after:api-arms.js"; do
  d=${pair%%:*}; rest=${pair#*:}; v=${rest%%:*}; api=${rest##*:}
  mk_site "$d" "$v" "$WS/$api"
  cp "$WS/page.html" "$WS/$d/index.html"
done

PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
( cd "$WS" && python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) &
SRV_PID=$!
for _ in $(seq 1 40); do
  curl -sf "http://127.0.0.1:$PORT/before/index.html" >/dev/null 2>&1 && break
  sleep 0.1
done

# ── 跑一次瀏覽器 ─────────────────────────────────────────────
CH_TIMEOUT_S=30
run() {  # run <目錄> <hash>；印出 RESULT 那一行，失敗時把 Chrome 自己說的話印到 stderr
  local out=$WS/dom.out err=$WS/dom.err pid waited=0
  : > "$err"
  # --user-data-dir 不能省。上面的 fallback 鏈包含一般的 google-chrome，
  # 沒有這一行它會去用你真實的瀏覽器設定檔，而 README 寫的是「不碰你的檔案」。
  # 沒有 --no-sandbox：關掉沙箱是把瀏覽器最外層那道隔離拿掉，不該為了省事
  # 寫進一份資安 recipe。在 root 底下跑不起來的話，換成非 root 使用者。
  "$CH" --headless --disable-gpu \
        --user-data-dir="$WS/chrome-profile" \
        --virtual-time-budget=4000 \
        --dump-dom "http://127.0.0.1:$PORT/$1/index.html#$2" > "$out" 2> "$err" &
  pid=$!
  # 硬逾時。--virtual-time-budget 管的是頁面裡的虛擬時間，不是牆鐘上限，
  # Chrome 自己起不來（權限、設定檔鎖住）的話它會一直等下去
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge $((CH_TIMEOUT_S * 5)) ]; then
      kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      printf '  [!] Chrome 超過 %s 秒沒有結束，已強制中止。它自己說：\n' "$CH_TIMEOUT_S" >&2
      sed 's/^/      /' "$err" | head -8 >&2
      [ -s "$err" ] || printf '      （stderr 是空的）\n' >&2
      return 1
    fi
    sleep 0.2; waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null
  local r
  r=$(grep -o 'RESULT fired=[^<]*' "$out" | head -1)
  if [ -z "$r" ]; then
    # 這支 recipe 講的就是假綠燈，它自己的失敗路徑不能是靜默。
    # 吞掉 stderr 的話，使用者看到的是「卡住」而不是「Chrome 起不來，原因是這個」
    printf '  [!] 這一趟沒有拿到結果。Chrome 的 stderr：\n' >&2
    sed 's/^/      /' "$err" | head -8 >&2
    [ -s "$err" ] || printf '      （stderr 是空的，多半是頁面沒載起來或 JavaScript 出錯）\n' >&2
    return 1
  fi
  printf '%s' "$r"
}

want() {  # want <格號> <版本> <payload> <期待的 fired> <說明> [額外要出現的字串]
  # 第 5 節比的是前四格的結果，所以單跑 5 的時候前四格也要跑，
  # 否則它拿空字串去比，會紅得像有洞，其實是依賴沒備齊
  [ -n "$ONLY" ] && [ "$ONLY" != "$1" ] && [ "$ONLY" != 5 ] && return 0
  printf '\n=== %s. %s 版 × %s ===\n' "$1" "$2" "$3"
  R=$(run "$2" "$3") || R=""
  printf '  %s\n' "${R:-（沒有結果，看上面 Chrome 說了什麼）}"
  printf '  期待：%s\n' "$5"
  N=0
  [ -n "$R" ] || { bad "這一格沒跑出結果"; eval "R$1="; return 0; }
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
if [ -z "$ONLY" ] || [ "$ONLY" = 5 ]; then
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

# ── 模型把 payload 包成不同形狀，哪幾種還打得穿 ────────────────
if [ -z "$ONLY" ] || [ "$ONLY" = 6 ]; then
  printf '\n=== 6. 五種模型回法 ===\n'
  printf '  %-8s %-40s %s\n' 回法 'before（有洞）' 'after（修好）'
  N=0
  for a in raw fence inline escape prose; do
    B=$(run m-before "$a") || B=""
    A=$(run m-after  "$a") || A=""
    printf '  %-8s %-40s %s\n' "$a" "${B:-（沒有結果）}" "${A:-（沒有結果）}"
    eval "B_$a=\$B"; eval "A_$a=\$A"
  done
  # 原樣覆述要打得穿，否則整組構造有問題，先懷疑構造不要先懷疑結論
  printf '%s' "${B_raw:-}" | grep -qF 'fired=true' \
    || { bad "原樣覆述沒打穿有洞的版本，反例沒重現"; N=1; }
  # 這一節的重點：markdown 圍籬與行內反引號都只是字元，擋不住
  for a in fence inline; do
    eval "R=\${B_$a:-}"
    printf '%s' "$R" | grep -qF 'fired=true' \
      || { bad "${a} 那臂沒打穿。圍籬與反引號是 markdown 的語法不是 HTML 的，應該擋不住"; N=1; }
  done
  # 只有模型自己 escape 或根本不覆述才不會出事
  for a in escape prose; do
    eval "R=\${B_$a:-}"
    printf '%s' "$R" | grep -qF 'fired=false' \
      || { bad "${a} 那臂竟然打穿了，README 那張表要重寫"; N=1; }
  done
  # 修好那版對五種回法一律不執行、DOM 裡沒有 img
  for a in raw fence inline escape prose; do
    eval "R=\${A_$a:-}"
    printf '%s' "$R" | grep -qF 'fired=false' \
      || { bad "修好那版在 ${a} 這臂事件還是發生了"; N=1; }
    printf '%s' "$R" | grep -qF 'imgInDOM=false' \
      || { bad "修好那版在 ${a} 這臂 DOM 裡還有 img"; N=1; }
  done
  [ "$N" = 0 ] \
    && ok "圍籬與反引號都擋不住，只有 escape 與拒答不會出事；修好那版五種都擋住" \
    || bad "五種回法的結果跟 README 那張表對不上"
fi

# ── 有 CSP 的頁面上，「沒跳」為什麼不能當成修好了 ────────────
if [ -z "$ONLY" ] || [ "$ONLY" = 7 ]; then
  printf '\n=== 7. CSP 擋掉 onerror 的時候，img 還在不在 ===\n'
  N=0
  for v in nocsp withcsp; do
    R=$(run "$v" "") || R=""
    printf '  %-9s %s\n' "$v" "${R:-（沒有結果）}"
    eval "C_$v=\$R"
  done
  printf '%s' "${C_nocsp:-}"   | grep -qF 'fired=true'  || { bad "沒有 CSP 的頁面竟然沒發生，構造有問題"; N=1; }
  printf '%s' "${C_withcsp:-}" | grep -qF 'fired=false' || { bad "CSP 沒擋掉 onerror，這一節的前提不成立"; N=1; }
  # 整節的重點：被擋掉的時候元素還在，所以 imgInDOM 分得出「環境擋的」與「你修好的」
  printf '%s' "${C_withcsp:-}" | grep -qF 'imgInDOM=true' \
    || { bad "CSP 擋掉之後 img 也不在 DOM 裡，那 README 那條 imgInDOM 判準就沒有意義"; N=1; }
  [ "$N" = 0 ] \
    && ok "有 CSP 時事件沒發生但 img 還在 DOM。只看事件會把環境防線讀成自己修好了" \
    || bad "CSP 那節的結果跟 README 寫的對不上"
fi

printf '\n════════ %s 綠 / %s 紅 / %s 跳過 ════════\n' "$PASS" "$FAIL" "$SKIP"
# 跑了零項不算通過。上面那道節號檢查擋掉已知的入口，這條擋掉還沒想到的：
# 只要有一條路徑讓所有檢查都沒執行，沒有這一行就會拿到綠燈。
if [ $((PASS + FAIL + SKIP)) -eq 0 ]; then
  printf '一項檢查都沒有執行，這不算通過\n' >&2
  exit 1
fi

# 離開碼的意思，全 repo 一致（Day 22 定的）：
#   0 綠，而且真的驗過了
#   1 紅，這是你要它擋你的那種
#   2 環境不到位或有節被跳過，沒有結論。跳過不是通過
[ "${FAIL}" != 0 ] && exit 1
[ "${SKIP}" != 0 ] && exit 2
exit 0
