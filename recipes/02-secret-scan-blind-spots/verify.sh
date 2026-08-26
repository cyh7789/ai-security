#!/usr/bin/env bash
# 祕密掃描的六個假通過
#
# 這支腳本不檢查你的專案。它造六個最小情境，每個情境跑兩種檢查：
#   naive   常見的、直覺的那種寫法
#   fixed   知道坑在哪之後的寫法
# 每個情境裡 naive 都會給你一個「看起來沒事」的結果，而東西其實在那裡。
#
#   bash verify.sh          跑全部
#   bash verify.sh 3        只跑第 3 個
#
# 整支跑在 mktemp -d 開的暫存目錄裡，不碰你的任何檔案。

set -u
ONLY=${1:-}
PASS=0; FAIL=0
hdr() { printf '\n\033[1m%s\033[0m\n' "$1"; }
naive() { printf '  naive  %-46s → %s\n' "$1" "$2"; }
fixed() { printf '  fixed  %-46s → %s\n' "$1" "$2"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
run() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
G()   { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

WS=$(mktemp -d); trap 'rm -rf "$WS"' EXIT
printf 'git %s／bash %s\n' "$(git --version | awk '{print $3}')" "${BASH_VERSION%%(*}"

# ── 1 ────────────────────────────────────────────────────────
if run 1; then
hdr "1. 檔案早就被 track 了，加 .gitignore 沒有用"
R=$WS/c1; mkdir -p "$R"; cd "$R"; G init -q .
echo "API_KEY=sk-real-one" > .env; G add -f .env; G commit -qm init
printf '.env*\n' > .gitignore; G add .gitignore; G commit -qm "補 .gitignore"
A=$(G status --short | wc -l | tr -d ' ')
naive "補完 .gitignore 看 git status" "${A} 行改動，乾乾淨淨，看起來沒事了"
B=$(G check-ignore -v .env >/dev/null 2>&1; echo $?)
fixed "git check-ignore -v .env" "exit=${B}（沒有輸出）"
C=$(G ls-files --error-unmatch .env >/dev/null 2>&1; echo $?)
fixed "git ls-files --error-unmatch .env" "exit=${C}（0 代表還在索引裡）"
[ "$C" = 0 ] && ok "檔案其實還被追蹤著，要先 git rm --cached" || no "情境沒造對"
fi

# ── 2 ────────────────────────────────────────────────────────
if run 2; then
hdr "2. check-ignore 有輸出，不代表被擋"
R=$WS/c2; mkdir -p "$R"; cd "$R"; G init -q .
printf '.env*\n!.env.example\n' > .gitignore
echo x > .env; echo x > .env.example
O=$(G check-ignore -v .env.example 2>/dev/null); E=$?
naive "看到輸出就當成有擋" "${O}（exit=${E}）"
fixed "看規則開頭有沒有 !" "有 ! 就是放行，不是擋下"
echo "$O" | grep -q '!' && ok "否定規則也會印出來，而且一樣 exit 0" || no "情境沒造對"
fi

# ── 3 ────────────────────────────────────────────────────────
if run 3; then
hdr "3. 查歷史的 pathspec 只比對檔名"
R=$WS/c3; mkdir -p "$R/config"; cd "$R"; G init -q .
mkdir -p backend; echo "KEY=sk-in-subdir" > backend/.env
G add -A; G commit -qm "加 backend/.env"
printf 'db: postgres://user:pw@host/db\n' > config/secrets.json
G add -A; G commit -qm "加 config/secrets.json"
A=$(G log --all --full-history --oneline -- .env | wc -l | tr -d ' ')
naive "-- .env（沒引號、寫死檔名）" "$A 筆"
B=$(G log --all --full-history --oneline -- '*.env*' | wc -l | tr -d ' ')
naive "-- '*.env*'" "$B 筆（漏掉 secrets.json）"
C=$(G log --all --full-history --oneline -- '*.env*' '*secret*' '*credential*' '*.pem' '*.key' | wc -l | tr -d ' ')
fixed "多給幾個 pattern" "$C 筆"
[ "$A" = 0 ] && [ "$C" -gt "$B" ] && ok "檔名不叫 .env 的，那條指令一個都不認" || no "情境沒造對"
fi

# ── 4 ────────────────────────────────────────────────────────
if run 4; then
hdr "4. merge 簡化會把整條側支藏起來"
R=$WS/c4; mkdir -p "$R"; cd "$R"; G init -q .
echo base > f; G add .; G commit -qm base
G checkout -qb side; echo "KEY=sk-merged-away" > .env; G add -f .env; G commit -qm "side: 加 .env"
G checkout -q main; echo m > m; G add m; G commit -qm "main: 別的改動"
G merge -q -s ours --no-ff side -m "merge"; G branch -qD side
A=$(G log --all --oneline -- '*.env*' | wc -l | tr -d ' ')
naive "git log --all -- '*.env*'" "$A 筆"
B=$(G log --all --full-history --oneline -- '*.env*' | wc -l | tr -d ' ')
fixed "加上 --full-history" "$B 筆"
H=$(G log --all --full-history --format=%h -- '*.env*' | tail -1)
printf '  那個 commit 裡有什麼：%s\n' "$(G show "$H":.env 2>/dev/null)"
[ "$A" = 0 ] && [ "$B" -gt 0 ] && ok "合併結果跟主線一樣時，那一側預設被跳過" || no "情境沒造對"
fi

# ── 5 ────────────────────────────────────────────────────────
if run 5; then
hdr "5. 用 sed 遮值，路徑含冒號就漏"
R=$WS/c5; mkdir -p "$R/a:b"; cd "$R"
printf 'DATABASE_PASSWORD=sk-LEAKED-1\n' > 'a:b/conf.env'
printf 'const SESSION_SECRET = "sk-LEAKED-2"\n' > front.js
A=$(grep -rnIiE '(api[_-]?key|secret|token|password)[[:space:]]*[:=]' . \
    | sed -E 's/^([^:]+:[0-9]+:[^:=]*)[:=].*/\1= <值略>/' | grep -c 'sk-LEAKED' || true)
naive "grep | sed 's/值/<值略>/'" "$A 行把明文印出來了"
grep -rnIiE '(api[_-]?key|secret|token|password)[[:space:]]*[:=]' . \
  | sed -E 's/^([^:]+:[0-9]+:[^:=]*)[:=].*/\1= <值略>/' | sed 's/^/         /'
B=$(grep -rnIioE '[[:alnum:]_]*(api[_-]?key|secret|token|password)[[:alnum:]_]*[[:space:]]*[:=]' . \
    | grep -c 'sk-LEAKED' || true)
fixed "grep -o（值不進輸出）" "$B 行"
grep -rnIioE '[[:alnum:]_]*(api[_-]?key|secret|token|password)[[:alnum:]_]*[[:space:]]*[:=]' . | sed 's/^/         /'
[ "$A" -gt 0 ] && [ "$B" = 0 ] && ok "sed 對不上的行是原樣輸出的，失敗方式是靜默洩漏" || no "情境沒造對"
fi

# ── 6 ────────────────────────────────────────────────────────
if run 6; then
hdr "6. 驗有沒有漏出去，搜關鍵字會兩頭錯"
R=$WS/c6; mkdir -p "$R"; cd "$R"
BAIT="sk-proj-000000000000BAIT0802"
printf '{"error":"Authorization header is required"}\n' > no-leak.json
printf '{"error":"invalid key: %s"}\n' "$BAIT" > leaked.json
A1=$(grep -ci 'sk-\|authorization' no-leak.json); A2=$(grep -ci 'sk-\|authorization' leaked.json)
naive "grep -ci 'sk-\\|authorization'" "沒漏的回 ${A1}（假陽性）、漏了的回 $A2"
B1=$(grep -c 'BAIT0802' no-leak.json); B2=$(grep -c 'BAIT0802' leaked.json)
fixed "只搜自己種的誘餌尾碼" "沒漏的回 ${B1}、漏了的回 $B2"
[ "$A1" -gt 0 ] && [ "$B1" = 0 ] && [ "$B2" -gt 0 ] && ok "誘餌是你自己種的，只有它出現才算數" || no "情境沒造對"

printf '\n  另外一種假 0：服務根本沒起來\n'
RESP=$R/resp.txt; rm -f "$RESP"
OUT=$(curl -sS -o "$RESP" -w '%{http_code}' "http://localhost:59999/" 2>&1); RC=$?
N=$(grep -c 'BAIT0802' "$RESP" 2>/dev/null); N=${N:-0}
naive "只看 grep 的數字" "${N}（跟真的沒漏長得一樣）"
fixed "先看 curl 的離開碼與狀態碼" "exit=${RC}，狀態碼=$(echo "$OUT" | tail -c 4)"
[ "$RC" != 0 ] && [ "$N" = 0 ] && ok "連不上的時候也是 0，所以狀態碼要先看" || no "情境沒造對"

printf '\n  第三種：上一次的殘留檔\n'
printf 'invalid key: %s\n' "$BAIT" > "$RESP"     # 假裝這是上一次跑剩下的
curl -sS -o "$RESP" -w '' "http://localhost:59999/" 2>/dev/null || true
M=$(grep -c 'BAIT0802' "$RESP")
naive "連不上，但沒先刪檔" "${M}（讀到的是上一次的內容）"
rm -f "$RESP"; curl -sS -o "$RESP" -w '' "http://localhost:59999/" 2>/dev/null || true
K=$(grep -c 'BAIT0802' "$RESP" 2>/dev/null); K=${K:-0}
fixed "跑之前先 rm -f" "$K"
[ "$M" -gt 0 ] && [ "$K" = 0 ] && ok "curl 連不上時不會覆蓋 -o 的檔案" || no "情境沒造對"
fi

printf '\n════════ 通過 %s／沒過 %s ════════\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
