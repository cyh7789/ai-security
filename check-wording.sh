#!/usr/bin/env bash
# 掃這個 repo 的中文寫得像不像人講話。
#
#   bash check-wording.sh                          # 掃全部
#   bash check-wording.sh recipes/27-ask-by-cwe    # 只掃一個目錄
#
# 離開碼 0 乾淨、1 有東西要改。
#
# 為什麼要有這支：這些毛病寫的時候看不出來。作者天天在 recipe 裡寫「轉紅」「這道閘」，
# 寫著寫著就以為那是中文。腳本印什麼，文章就跟著寫什麼，所以源頭在 printf 那幾行。
#
# **存檔目錄一律跳過**：runs/、hunt*/、first-look/、names-only/、sources/、evidence/
# 裡面是跑出來的原始輸出與量測紀錄，那是證據不是文章。
#
# ── 這支自己壞過兩次，兩次都是「靜默掃不到」──────────────────
# 第一版：黑話那條用了 grep -E 不支援的 lookahead，整條比對不到任何東西。
# 第二版：改成白名單列舉（轉[綠紅]|全[綠紅]|…），漏掉「照樣綠」「永遠綠」「有紅」
#         這些沒列到的組合，更漏掉裸字（printf '  綠\t%s\n'）。它回報乾淨的時候，
#         repo 裡還有 313 處綠紅、240 處閘（2026-08-26 外審實測）。
#
# 所以現在改成**抓裸字再排除真詞**：寧可誤報讓人來看，不要漏報。
# 自檢也改成逐個分支各餵一行探針，一條分支壞掉就叫，不是整條規則都死才叫。
set -u
cd "$(dirname "$0")"
TARGET="${1:-.}"
BAD=0

files() {
  find "$TARGET" -type f \
    \( -name '*.md' -o -name '*.sh' -o -name '*.py' -o -name '*.mjs' -o -name '*.js' \
       -o -name '*.cjs' -o -name '*.tsv' -o -name '*.yml' -o -name '*.jsonl' -o -name '*.json' \) \
    -not -name '*.out' \
    -not -path '*/node_modules/*' -not -path '*/.git/*' \
    -not -path '*/runs/*' -not -path '*/hunt/*' -not -path '*/hunt-renamed/*' \
    -not -path '*/hunt-firstdraft/*' -not -path '*/first-look/*' -not -path '*/names-only/*' \
    -not -path '*/cwe-pages/*' -not -path '*/sources/*' -not -path '*/evidence/*' \
    -not -name 'check-wording.sh' \
    | sort
}

# 「紅」「綠」是真詞的場合。這張表要短，長了就等於白名單回來了。
#   紅線     底線、不可越過，標準中文
#   紅車軸草 成分名
#   綠色/紅色 + 六位色碼  真的在講顏色
#   信任邊界的紅綠        圖上真的用顏色區分
KEEP='紅線|紅車軸草|[綠紅]色 ?`?[0-9A-F]{6}|信任邊界的紅綠|綠底|紅底|裡的「閘」改成「檢查」'

scan() {  # scan <說明> <正規式>
  local desc="$1" re="$2" out n
  out=$(files | while read -r f; do
    grep -nE "$re" "$f" 2>/dev/null | grep -vE "$KEEP" | sed "s|^|${f}:|"
  done)
  [ -z "$out" ] && return 0
  n=$(printf '%s\n' "$out" | grep -c .)
  printf '\n【要改】%s：%s 處\n' "$desc" "$n"
  printf '%s\n' "$out" | head -10 | sed 's/^/  /'
  [ "$n" -gt 10 ] && printf '  …另外 %s 處\n' "$((n - 10))"
  BAD=1
}

# 抓裸字。排除交給 KEEP，不要在這裡列組合。
scan "綠／紅（判定一律寫通過、沒過、沒有結論）" '[綠紅]'
scan "閘／閘門（寫檢查、關卡）"                 '閘'
scan "咬（寫抓）"                               '咬'
scan "英文判定標籤（一律用中文）"               '\[ ?(OK|FAIL|SKIP|PASS) ?\]|['"'"'"]  (ok|OK|FAIL|SKIP|PASS) '
scan "翻面／翻掉（寫判定有沒有改變）"           '翻面|翻掉'
scan "沒測到（三態只有通過、沒過、沒有結論）"   '沒測到'
scan "翻譯腔句型"                               '跑行為的|對其進行|裡進行|中進行|做出[^，。]{0,4}的?(選擇|決定)|被認為是|所被'
scan "破折號"                                   '——'
scan "中國用語"                                 '視頻|質量|軟件|默認|緩存|調用|接口|字符串|網絡|數據庫|服務器|賦能|抓手|閉環|落地|痛點|顆粒度'
scan "自造詞（漏洞就叫漏洞）"                   '留洞|埋洞|下洞'

# ── 自檢：每一個分支各餵一行一定會中的假文字 ──────────────────
# 逐分支，不是逐規則。第二版的自檢是逐規則，把整條規則砍到只剩一個分支
# 照樣印「都抓得到」，等於沒在自檢。
printf '\n=== 規則自檢 ===\n'
PROBES='綠|紅|閘|咬|[OK]|[ OK ]|[FAIL]|[SKIP]|[PASS]|"  FAIL  x"|翻面|翻掉|沒測到|跑行為的|對其進行|裡進行|被認為是|——|默認|緩存|閉環|留洞'
DEAD=""
OLDIFS=$IFS; IFS='|'
for probe in $PROBES; do
  printf '%s\n' "$probe" | grep -qE '[綠紅]|閘|咬|\[ ?(OK|FAIL|SKIP|PASS) ?\]|['"'"'"]  (ok|OK|FAIL|SKIP|PASS) |翻面|翻掉|沒測到|跑行為的|對其進行|裡進行|被認為是|——|視頻|質量|軟件|默認|緩存|調用|接口|字符串|網絡|數據庫|服務器|賦能|抓手|閉環|落地|痛點|顆粒度|留洞|埋洞|下洞' \
    || DEAD="${DEAD} ${probe}"
done
IFS=$OLDIFS
# KEEP 也要自檢：它不能寬到把真的黑話放掉
printf '這道閘紅了\n' | grep -qvE "$KEEP" || DEAD="${DEAD} KEEP太寬"
printf '紅線檢查\n' | grep -qE "$KEEP" || DEAD="${DEAD} KEEP太窄"
if [ -n "$DEAD" ]; then
  printf '這幾個分支抓不到自己的探針，等於沒在掃：%s\n' "$DEAD"; BAD=1
else
  printf '每個分支都抓得到自己的探針，KEEP 放行真詞、擋住黑話\n'
fi

if [ "$BAD" = 0 ]; then
  printf '\n乾淨。\n'
else
  printf '\n唸出聲問一次：這句話你會這樣跟同事講嗎？\n'
fi
exit "$BAD"
