#!/usr/bin/env bash
# 03 處置外洩憑證時的三個假通過
#
#   bash verify.sh        跑全部三個
#   bash verify.sh 2      只跑第 2 個
#
# 全部在 mktemp -d 裡進行，不碰你的任何檔案，跑完自動清掉。
# 情境 1 需要 gitleaks，系統沒裝會自己抓一份到暫存目錄（用完刪掉，不會裝進系統）。
# 情境 2 要連外網打兩家的公開端點，用的是明顯無效的假金鑰，不會動到任何帳號。

set -u
ONLY="${1:-}"
PASS=0; FAIL=0; SKIP=0
hdr()  { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
ok()   { printf '  \033[32m[OK]\033[0m   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m[FAIL]\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33m[SKIP]\033[0m %s\n' "$1"; SKIP=$((SKIP+1)); }
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
G()    { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

WS=$(mktemp -d); trap 'rm -rf "$WS"' EXIT

# ─────────────────────────────────────────────────────────────
# 1. 掃描器的離開碼：「找到祕密」與「掃描器自己壞掉」長得一樣
# ─────────────────────────────────────────────────────────────
if want 1; then
hdr "1. pre-commit hook 分不出「有祕密」與「工具壞掉」"

GL=$(command -v gitleaks || true)
if [ -z "$GL" ]; then
  OS=$(uname -s | tr 'A-Z' 'a-z'); ARCH=$(uname -m)
  case "$ARCH" in x86_64) ARCH=x64 ;; aarch64) ARCH=arm64 ;; esac
  U=$(curl -sS -m 20 https://api.github.com/repos/gitleaks/gitleaks/releases/latest 2>/dev/null \
      | grep -oE '"browser_download_url": "[^"]+"' | cut -d'"' -f4 \
      | grep "${OS}_${ARCH}" | head -1)
  if [ -n "$U" ] && curl -sSL -m 60 -o "$WS/g.tgz" "$U" 2>/dev/null; then
    tar xzf "$WS/g.tgz" -C "$WS" 2>/dev/null && [ -x "$WS/gitleaks" ] && GL="$WS/gitleaks"
  fi
fi

if [ -z "$GL" ]; then
  skip "抓不到 gitleaks（沒網路或這個平台沒有預編譯檔），情境 1 跳過"
else
  printf '  用的是 gitleaks %s\n\n' "$($GL version 2>/dev/null)"
  R=$WS/c1; mkdir -p "$R"; cd "$R"; G init -q .

  echo "hello world" > clean.txt; G add clean.txt
  $GL git --staged --redact               >/dev/null 2>&1; NAIVE_CLEAN=$?
  $GL git --staged --redact --exit-code 2 >/dev/null 2>&1; FIXED_CLEAN=$?

  # 真祕密：現生一把私鑰。它從沒離開過這台機器，而 private-key 規則不看熵
  openssl genrsa -out secret.pem 2048 2>/dev/null; G add secret.pem
  $GL git --staged --redact               >/dev/null 2>&1; NAIVE_LEAK=$?
  $GL git --staged --redact --exit-code 2 >/dev/null 2>&1; FIXED_LEAK=$?

  # 工具壞掉：指向一個不存在的設定檔
  $GL git --staged --redact               -c /nonexistent.toml >/dev/null 2>&1; NAIVE_ERR=$?
  $GL git --staged --redact --exit-code 2 -c /nonexistent.toml >/dev/null 2>&1; FIXED_ERR=$?

  printf '                        乾淨   有祕密   設定檔壞掉\n'
  printf '  naive（預設）           %s       %s          %s\n' "$NAIVE_CLEAN" "$NAIVE_LEAK" "$NAIVE_ERR"
  printf '  fixed（--exit-code 2）  %s       %s          %s\n' "$FIXED_CLEAN" "$FIXED_LEAK" "$FIXED_ERR"

  [ "$NAIVE_LEAK" = "$NAIVE_ERR" ] \
    && ok "naive：有祕密與工具壞掉都回 ${NAIVE_LEAK}，hook 的 || 分不出來" \
    || bad "naive 竟然分得開（$NAIVE_LEAK vs ${NAIVE_ERR}），這版 gitleaks 行為變了"

  [ "$FIXED_LEAK" = 2 ] && [ "$FIXED_ERR" != 2 ] \
    && ok "fixed：有祕密回 2、工具壞掉回 ${FIXED_ERR}，hook 才判得對" \
    || bad "fixed 沒有把兩者分開"

  # 把兩種 hook 都裝起來跑一次，看讀者實際會看到什麼
  for MODE in naive fixed; do
    R2=$WS/c1-$MODE; mkdir -p "$R2"; cd "$R2"; G init -q .
    echo base > f.txt; G add .; G commit -qm base
    G config core.hooksPath .githooks; mkdir -p .githooks
    if [ "$MODE" = naive ]; then
      cat > .githooks/pre-commit <<EOF
#!/usr/bin/env bash
$GL git --staged --redact -c /nonexistent.toml || {
  echo "偵測到疑似祕密，commit 中止"
  exit 1
}
EOF
    else
      cat > .githooks/pre-commit <<EOF
#!/usr/bin/env bash
$GL git --staged --redact --exit-code 2 -c /nonexistent.toml
case \$? in
  0) ;;
  2) echo "偵測到疑似祕密，commit 中止"; exit 1 ;;
  *) echo "gitleaks 沒跑完，這次等於沒掃，commit 中止"; exit 1 ;;
esac
EOF
    fi
    chmod +x .githooks/pre-commit
    echo "這個檔案裡什麼祕密都沒有" > innocent.txt; G add innocent.txt
    OUT=$(G commit -m "設定檔是壞的，但這次 commit 其實乾淨" 2>&1)
    printf '  %-5s hook 對一個乾淨的 commit 說：%s\n' "$MODE" \
      "$(printf '%s' "$OUT" | grep -E '偵測到|沒跑完' | head -1)"
    if [ "$MODE" = naive ]; then
      printf '%s' "$OUT" | grep -q '偵測到疑似祕密' \
        && ok "naive 對著一個沒有祕密的 commit 喊「偵測到疑似祕密」，你會開始不相信它" \
        || bad "naive 沒有重現誤報"
    else
      printf '%s' "$OUT" | grep -q '沒跑完' \
        && ok "fixed 講的是「這次等於沒掃」，你知道要去修設定檔而不是去找祕密" \
        || bad "fixed 的訊息不對"
    fi
  done
fi
fi

# ─────────────────────────────────────────────────────────────
# 2. 驗證撤銷：標頭寫錯，有效的金鑰也會看起來像已撤銷
# ─────────────────────────────────────────────────────────────
if want 2; then
hdr "2. 撤銷驗證只換網址，會把「標頭寫錯」誤讀成「撤銷成功」"

if ! curl -sS -m 10 -o /dev/null https://api.anthropic.com/v1/models 2>/dev/null; then
  skip "連不到外網，情境 2 跳過"
else
  # naive：拿 A 家的驗證格式去打 B 家，只換網址沒換標頭
  NAIVE=$(curl -sS -m 15 https://api.anthropic.com/v1/models \
          -H "Authorization: Bearer any-key-at-all" 2>&1)
  # fixed：照文件用對標頭，金鑰本身是無效的
  FIXED=$(curl -sS -m 15 https://api.anthropic.com/v1/models \
          -H "x-api-key: sk-definitely-not-a-real-key" \
          -H "anthropic-version: 2023-06-01" 2>&1)

  printf '  naive（Bearer，標頭就錯了）：\n    %s\n' "$(printf '%s' "$NAIVE" | tr -d '\n' | cut -c1-130)"
  printf '  fixed（標頭正確，金鑰無效）：\n    %s\n' "$(printf '%s' "$FIXED" | tr -d '\n' | cut -c1-130)"

  NT=$(printf '%s' "$NAIVE" | grep -o '"type":"[a-z_]*"' | tail -1)
  FT=$(printf '%s' "$FIXED" | grep -o '"type":"[a-z_]*"' | tail -1)
  printf '\n  兩者的 type：%s  vs  %s\n' "${NT:-取不到}" "${FT:-取不到}"

  [ -n "$NT" ] && [ "$NT" = "$FT" ] \
    && ok "type 完全一樣。只看 type 的話，標頭寫錯跟金鑰真的死了分不出來" \
    || bad "type 不同（$NT vs ${FT}），這個誤判在目前的 API 上不成立了"

  NM=$(printf '%s' "$NAIVE" | grep -o '"message":"[^"]*"' | tail -1)
  FM=$(printf '%s' "$FIXED" | grep -o '"message":"[^"]*"' | tail -1)
  printf '  兩者的 message：\n    naive %s\n    fixed %s\n' "${NM:-取不到}" "${FM:-取不到}"
  [ -n "$NM" ] && [ "$NM" != "$FM" ] \
    && ok "message 不一樣，這是唯一分得出來的地方。所以要讀完整個回應，不能只看一個欄位" \
    || bad "連 message 都一樣，那這個驗證方法整個不成立"

  # 反向：撤銷驗證還有一個前提，端點本身要打得通
  NOTFOUND=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' \
             https://api.anthropic.com/v1/this-endpoint-does-not-exist \
             -H "x-api-key: sk-definitely-not-a-real-key" \
             -H "anthropic-version: 2023-06-01" 2>&1)
  printf '\n  打一個不存在的端點：HTTP %s\n' "$NOTFOUND"
  [ "$NOTFOUND" != 200 ] \
    && ok "端點錯了也會被拒絕。所以要挑一個撤銷前用同一把鑰匙打得通的端點來測" \
    || bad "不存在的端點竟然回 200"
fi
fi

# ─────────────────────────────────────────────────────────────
# 3. curl -s 把連線錯誤吞掉
# ─────────────────────────────────────────────────────────────
if want 3; then
hdr "3. curl -s 讓「打不到」跟「打到了被拒絕」長得一樣"

# 一個一定解析不了的網域
DEAD=https://api.provider.example/v1/models

NAIVE_OUT=$(curl -s  -m 8 "$DEAD" 2>&1); NAIVE_RC=$?
FIXED_OUT=$(curl -sS -m 8 "$DEAD" 2>&1); FIXED_RC=$?
CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 8 "$DEAD" 2>/dev/null)

printf '  naive  curl -s   輸出：「%s」離開碼 %s\n' "$NAIVE_OUT" "$NAIVE_RC"
printf '  fixed  curl -sS  輸出：「%s」離開碼 %s\n' "$FIXED_OUT" "$FIXED_RC"
printf '  只取狀態碼（-o /dev/null -w）：%s\n' "$CODE"

[ -z "$NAIVE_OUT" ] \
  && ok "naive 完全不出聲。畫面上什麼都沒有，你會以為指令跑完了" \
  || bad "naive 竟然有輸出，這台的 curl 行為不同"

printf '%s' "$FIXED_OUT" | grep -qi 'curl:' \
  && ok "fixed 講出 curl 的錯誤，你知道問題在連線不在憑證" \
  || bad "fixed 沒有顯示錯誤"

[ "$CODE" = "000" ] \
  && ok "狀態碼是 000。它不是 401 也不是任何「被拒絕」，別把它讀成撤銷成功" \
  || bad "預期 000，拿到 ${CODE}"
fi

# ─────────────────────────────────────────────────────────────
printf '\n════════ %s 綠 / %s 紅 / %s 跳過 ════════\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = 0 ]
