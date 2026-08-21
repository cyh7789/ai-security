#!/usr/bin/env bash
# 04 貼給 AI 之前的紅線檢查
#
#   bash verify.sh        跑全部
#   bash verify.sh 3      只跑第 3 節
#
# 全部在 mktemp -d 裡進行，不碰你的任何檔案，跑完自動清掉。
# 需要 bash 與 realpath（macOS 與多數 Linux 內建）。
#
# 最後一節是突變測試。它不是用 sed 去改原始碼的文字，那樣會綁死在寫法上，
# 重構一次就整組紅燈。這裡改成準備幾份「少掉某個設計決定」的完整腳本，
# 每一份都必須讓對應的斷言轉紅。

set -u
ONLY="${1:-}"
PASS=0; FAIL=0; SKIP=0
hdr()  { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
ok()   { printf '  \033[32m[OK]\033[0m   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m[FAIL]\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33m[SKIP]\033[0m %s\n' "$1"; SKIP=$((SKIP+1)); }
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

HERE=$(cd "$(dirname "$0")" && pwd)
SUT=$HERE/check-before-paste.sh
[ -f "$SUT" ] || { echo "找不到 check-before-paste.sh"; exit 1; }

WS=$(mktemp -d); trap 'rm -rf "$WS"' EXIT
cd "$WS"

mkdir -p fixtures/nested src config "space dir"
printf 'DB_PASSWORD=hunter2\n'      > .env
printf 'DB_PASSWORD=local\n'        > .env.local
printf 'export FOO=bar\n'           > .envrc
printf 'services: {}\n'             > docker-compose.yml
printf '[{"n":"real"}]\n'           > fixtures/real.json
printf '[{"n":"deep"}]\n'           > "fixtures/nested/a b.json"
printf 'token: abc\n'               > config/secrets.yml
printf 'export const f = 1;\n'      > src/format.js
printf 'ok\n'                       > "space dir/ok file"
ln -s ../fixtures/real.json src/link.json      # 指向紅線區的 symlink
ln -s ./nowhere.json        src/dangling.json  # 失效的 symlink
ln    fixtures/real.json    src/hard.json      # hard link，realpath 解不回去

run() { bash "$1" "$2" 2>&1; }
rc()  { bash "$1" "$2" >/dev/null 2>&1; echo $?; }
rcs() { rc "$SUT" "$1"; }

# ─────────────────────────────────────────────────────────────
if want 1; then
hdr "1. 基本：紅線上的擋、乾淨的放行"
for F in .env docker-compose.yml config/secrets.yml fixtures/real.json src/format.js; do
  printf '  %-24s %s\n' "$F" "$(run "$SUT" "$F")"
done
[ "$(rcs .env)" = 1 ] && [ "$(rcs docker-compose.yml)" = 1 ] \
  && [ "$(rcs config/secrets.yml)" = 1 ] && [ "$(rcs fixtures/real.json)" = 1 ] \
  && [ "$(rcs src/format.js)" = 0 ] \
  && ok "四條紅線都擋，乾淨的放行。只驗會過的那半，驗到的是腳本會印字" \
  || bad "紅線或放行有一邊不對"
fi

# ─────────────────────────────────────────────────────────────
if want 2; then
hdr "2. .env 的變體：寫 .env* 不是 .env.*"
for F in .env.local .envrc; do
  printf '  %-24s %s\n' "$F" "$(run "$SUT" "$F")"
done
[ "$(rcs .env.local)" = 1 ] && [ "$(rcs .envrc)" = 1 ] \
  && ok "兩個變體都擋。寫成 .env.* 的話 .envrc 會漏，而 direnv 的設定檔常有東西" \
  || bad ".env 變體有漏"
fi

# ─────────────────────────────────────────────────────────────
if want 3; then
hdr "3. symlink 指向紅線區"
printf '  src/link.json 指向 %s\n' "$(readlink src/link.json)"
printf '  %-24s %s\n' src/link.json "$(run "$SUT" src/link.json)"
[ "$(rcs src/link.json)" = 1 ] \
  && ok "解成真實路徑才擋得住。只看字串的話它長得像 src/ 底下的普通檔案" \
  || bad "symlink 繞過去了"
fi

# ─────────────────────────────────────────────────────────────
if want 4; then
hdr "4. 三種「沒檢查成功」，都要回 2 而且訊息分得開"
for F in "src/dangling.json" "nope.json" "fixtures"; do
  printf '  %-24s rc=%s  %s\n' "$F" "$(rcs "$F")" "$(run "$SUT" "$F" | head -1)"
done
printf '  %-24s rc=%s  %s\n' "(沒有參數)" \
  "$(bash "$SUT" >/dev/null 2>&1; echo $?)" "$(bash "$SUT" 2>&1 | head -1)"

N=0
[ "$(rcs src/dangling.json)" = 2 ] || N=1
[ "$(rcs nope.json)" = 2 ]         || N=1
[ "$(rcs fixtures)" = 2 ]          || N=1
[ "$N" = 0 ] \
  && ok "失效連結、不存在、目錄，三種都回 2 不是 0。沒檢查成功不能長得像通過" \
  || bad "有情境回了 0，那會被當成乾淨"

run "$SUT" src/dangling.json | grep -q '失效' \
  && ok "失效的 symlink 講的是「連結壞了」，不是「找不到」，兩者該做的事不一樣" \
  || bad "失效連結的訊息沒有跟找不到分開"
fi

# ─────────────────────────────────────────────────────────────
if want 5; then
hdr "5. 路徑裡有空白"
printf '  %-24s %s\n' "space dir/ok file"      "$(run "$SUT" "space dir/ok file")"
printf '  %-24s %s\n' "fixtures/nested/a b.json" "$(run "$SUT" "fixtures/nested/a b.json")"
[ "$(rcs "space dir/ok file")" = 0 ] && [ "$(rcs "fixtures/nested/a b.json")" = 1 ] \
  && ok "含空白的路徑處理正確，巢狀 fixtures 也擋得住" \
  || bad "空白或巢狀路徑有問題"
fi

# ─────────────────────────────────────────────────────────────
if want 6; then
hdr "6. 這支腳本擋不住什麼（邊界，不是 bug）"

printf 'const KEY = "sk-proj-8Kj2mNp4qR7sT9vXwYzA3bC5dE6fG1hI";\n' > src/hardcoded.js
printf '  %-24s %s\n' src/hardcoded.js "$(run "$SUT" src/hardcoded.js)"
[ "$(rcs src/hardcoded.js)" = 0 ] \
  && ok "寫死在 .js 裡的金鑰它放行。清單管檔案，管不到內容" \
  || bad "預期放行"

printf '  %-24s %s\n' src/hard.json "$(run "$SUT" src/hard.json)"
printf '  （src/hard.json 是 fixtures/real.json 的 hard link，inode 相同）\n'
[ "$(rcs src/hard.json)" = 0 ] \
  && ok "hard link 繞得過去。realpath 只解 symlink，同一個 inode 的另一個名字它看不出來" \
  || bad "預期放行（這是已知邊界）"
printf '  要擋 hard link 得比對 inode，成本是掃過整個紅線目錄，這支沒有做\n'
fi

# ─────────────────────────────────────────────────────────────
if want 7; then
hdr "7. 突變測試：拿掉一個設計決定，對應的斷言必須轉紅"

# 每份突變是一支完整的腳本，不是對原始碼做字串替換。
# 這樣重構受測腳本不會讓突變框架假性紅燈
mk() {  # mk <檔名> <要拿掉什麼>
  case "$2" in
    env-glob)   PAT='.env|docker-compose.yml' ;;
    *)          PAT='.env*|docker-compose.yml' ;;
  esac
  case "$2" in
    no-realpath) RESOLVE='R=$T' ;;
    *)           RESOLVE='R=$(realpath "$T" 2>/dev/null) || { echo x; exit 2; }' ;;
  esac
  case "$2" in
    merge-case) DIRCASE='case "$(basename "$R")" in' ;;
    *)          DIRCASE='case "$R" in' ;;
  esac
  case "$2" in
    exit0)      FAILRC=0 ;;
    *)          FAILRC=2 ;;
  esac
  cat > "$1" <<EOF
#!/usr/bin/env bash
[ \$# -eq 1 ] || { echo no-arg; exit ${FAILRC}; }
T=\$1
if [ -L "\$T" ] && [ ! -e "\$T" ]; then echo dangling; exit ${FAILRC}; fi
[ -e "\$T" ] || { echo missing; exit ${FAILRC}; }
[ -d "\$T" ] && { echo isdir; exit ${FAILRC}; }
${RESOLVE}
case "\$(basename "\$R")" in
  ${PAT}) echo "踩到紅線：\$T"; exit 1 ;;
esac
${DIRCASE}
  */fixtures/*|*/config/secrets.*) echo "踩到紅線：\$T"; exit 1 ;;
esac
echo "不在紅線清單上：\$T"
EOF
}

MUT_FAIL=0
probe() {  # probe <突變名> <該漏掉的檔案> <預期突變後的離開碼>
  mk "$WS/m.sh" "$1"
  R=$(rc "$WS/m.sh" "$2")
  if [ "$R" = "$3" ]; then
    printf '  [殺得死] %-14s → %s 變成 rc=%s\n' "$1" "$2" "$R"
  else
    printf '  [殺不死] %-14s → %s 仍是 rc=%s，這個決定沒有被驗到\n' "$1" "$2" "$R"
    MUT_FAIL=$((MUT_FAIL+1))
  fi
}
probe env-glob   .envrc            0
probe no-realpath src/link.json    0
probe merge-case fixtures/real.json 0
probe exit0      nope.json         0

[ "$MUT_FAIL" = 0 ] \
  && ok "四個突變全部殺得死，四個設計決定都有對應的行為差異" \
  || bad "${MUT_FAIL} 個突變殺不死"

# 反向：確認突變框架本身沒有壞掉。原封不動的腳本必須通過同樣四個探針
mk "$WS/clean.sh" none
CN=0
[ "$(rc "$WS/clean.sh" .envrc)" = 1 ]             || CN=1
[ "$(rc "$WS/clean.sh" src/link.json)" = 1 ]      || CN=1
[ "$(rc "$WS/clean.sh" fixtures/real.json)" = 1 ] || CN=1
[ "$(rc "$WS/clean.sh" nope.json)" = 2 ]          || CN=1
[ "$CN" = 0 ] \
  && ok "沒突變的那份四個探針都正確，所以上面的紅燈是突變造成的不是探針壞掉" \
  || bad "未突變版本就不對，突變結果不可信"
fi

printf '\n════════ %s 綠 / %s 紅 / %s 跳過 ════════\n' "$PASS" "$FAIL" "$SKIP"

# 離開碼的意思，全 repo 一致（Day 22 定的）：
#   0 綠，而且真的驗過了
#   1 紅，這是你要它擋你的那種
#   2 環境不到位或有節被跳過，沒有結論。跳過不是通過
[ "${FAIL}" != 0 ] && exit 1
[ "${SKIP}" != 0 ] && exit 2
exit 0
