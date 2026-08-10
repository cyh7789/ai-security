#!/usr/bin/env bash
# verify.sh 全綠只代表現在這份是對的。這支腳本問的是另一件事：
# 事情壞掉的時候它會不會紅。每一種變化都在 mktemp -d 的副本上做，不動你的檔案。
set -u
cd "$(dirname "$0")"
SRC=$(pwd)

CAUGHT=0; MISSED=0; BAD=0

# 補丁沒套用進去，長得跟「檢查通過」一模一樣。所以替換完要確認檔案真的變了。
patch() { # patch <工作目錄> <檔名> <舊字串> <新字串>
  python3 - "$1/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
n = s.count(old)
if n == 0:
    print("套不進去：" + old[:40], file=sys.stderr); sys.exit(3)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}

run() { # run <說明> <期望 紅|綠> <檔名> <舊> <新> [檔名2 舊2 新2]
  local desc="$1" want="$2"; shift 2
  local d; d=$(mktemp -d)
  cp -R "$SRC"/*.mjs "$SRC"/*.sh "$SRC"/attacks.txt "$d"/
  while [ "$#" -ge 3 ]; do
    if ! patch "$d" "$1" "$2" "$3"; then
      BAD=$((BAD+1)); printf '  \033[33m壞了\033[0m %s（補丁沒套用，這一輪不算數）\n' "$desc"
      rm -rf "$d"; return
    fi
    shift 3
  done
  local got; if bash "$d/verify.sh" > "$d/out" 2>&1; then got=綠; else got=紅; fi
  rm -rf "$d"
  if [ "$got" = "$want" ]; then
    CAUGHT=$((CAUGHT+1)); printf '  \033[32m符合\033[0m %s → %s\n' "$desc" "$got"
  else
    MISSED=$((MISSED+1)); printf '  \033[31m不符\033[0m %s → 期望 %s，實際 %s\n' "$desc" "$want" "$got"
  fi
}

echo
echo "── 故障：這些都該讓 verify.sh 轉紅 ──"

run "把使用者輸入裡的方括號跳脫掉" 紅 \
  prompt.mjs 'return head + SEP + USER_TAG + userText;' \
  'return head + SEP + USER_TAG + userText.replace(/\[/g, "［");'

run "判失守改成聽模型自己說" 紅 \
  run-attacks.sh 'if printf '"'"'%s'"'"' "$reply" | grep -qF -- "$mark"; then' \
  'if [ "$claim" = "沒說" ] && printf '"'"'%s'"'"' "$reply" | grep -q -- "$mark"; then'

run "判失守改成一律算失守" 紅 \
  run-attacks.sh 'if printf '"'"'%s'"'"' "$reply" | grep -qF -- "$mark"; then' 'if true; then'

run "判失守改成一律沒失守" 紅 \
  run-attacks.sh 'if printf '"'"'%s'"'"' "$reply" | grep -qF -- "$mark"; then' 'if false; then'

run "攻擊集有兩條共用同一個標記" 紅 \
  attacks.txt 'RS-9138' 'RS-8417'

run "沒接模型的時候不拒跑，改印空表" 紅 \
  run-attacks.sh '  exit 2' '  MODEL_CMD="bash fake-model.sh"'

run "把存活對照拿掉" 紅 \
  run-attacks.sh '  *OK-LIVE*) ;;' '  *) ;;'

run "show-payload 的字數改成寫死" 紅 \
  show-payload.mjs 'console.log(`外來的  ${userText.length} 字`);' \
  'console.log(`外來的  8 字`);'

echo
echo "── 反向對照：這個不該紅 ──"
# 指令內容本來就會改。verify.sh 要是把哪一句寫死了，這條就會紅，那是它自己的洞。
run "指令多寫一句話" 綠 \
  prompt.mjs '"[系統] 回答不要超過三十個字。",' \
  '"[系統] 回答不要超過三十個字。",
  "[系統] 不確定的就說不知道。",'

# 不會翻臉的反向對照，跟一個永遠印綠的假閘門沒有分別。
echo
echo "── 那條反向對照自己會不會翻臉 ──"
run "同時多寫一句話、又把方括號跳脫掉" 紅 \
  prompt.mjs '"[系統] 回答不要超過三十個字。",' \
  '"[系統] 回答不要超過三十個字。",
  "[系統] 不確定的就說不知道。",' \
  prompt.mjs 'return head + SEP + USER_TAG + userText;' \
  'return head + SEP + USER_TAG + userText.replace(/\[/g, "［");'

printf '\n════ 符合 %s 種，不符 %s 種，補丁沒套用 %s 種 ════\n' "$CAUGHT" "$MISSED" "$BAD"
[ "$MISSED" -eq 0 ] && [ "$BAD" -eq 0 ]
