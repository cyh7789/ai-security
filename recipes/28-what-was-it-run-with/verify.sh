#!/usr/bin/env bash
# 這一天的檢查。跑：bash verify.sh
#
# 離開碼照 Day 22 那份公約：0 全部通過、1 有沒過的、2 環境不到位或有節被跳過，沒有結論。
#
# 這一天的產出是一支對帳腳本，而對帳腳本最容易壞的方式是「永遠說對得上」。
# 所以底下每一條都先把某一格弄成不一樣的，再問它抓不抓得到，而且要抓得準：
# 只說「有格子不合」不算，要指名是哪一格。指不準的話，四格會互相掩護。
set -u
cd "$(dirname "$0")"
export LC_ALL=C
G=0; B=0; S=0
case_() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  通過\t%s\n' "$1"; G=$((G+1)); }
bad()  { printf '  沒過\t%s\n' "$1"; B=$((B+1)); }
skip() { printf '  沒有結論\t%s\n' "$1"; S=$((S+1)); }

MODEL="${ANTARES_MLX:-./antares-1b-mlx}"
REC27=../27-ask-by-cwe

# 假模型目錄：只有 config.json 與一個幾位元組的 model.safetensors。
# 對帳的邏輯跟權重內容無關，所以大部分條目不需要那 1 GB 的真檔案；
# 真模型只留給第 2 條，證明這支在真的東西上跑得動。
FAKE=$(mktemp -d)
trap 'rm -rf "$FAKE"' EXIT
mkfake() {  # mkfake <bits> <權重內容>
  printf '{"quantization":{"group_size":64,"bits":%s,"mode":"affine"}}\n' "$1" > "$FAKE/config.json"
  printf '%s' "$2" > "$FAKE/model.safetensors"
}

# 只印判定那幾行，不印說明文字，比對才穩。
verdict() {  # verdict <格名> <check 的輸出>
  printf '%s\n' "$2" | awk -v k="$1" '$2==k {print $1}'
}

# ─────────────────────────────────────────────────────────────
case_ "1 成分表存在，五格齊全"
if [ ! -f stamp.json ]; then
  bad "沒有 stamp.json，先跑 python3 stamp.py record <模型目錄>"
else
  MISS=$(python3 -c "
import json
was = json.load(open('stamp.json'))
print(' '.join(k for k in ('model','quant','prompt','script','corpus') if k not in was))")
  [ -z "$MISS" ] && ok "model、quant、prompt、script、corpus 五格都在" \
    || bad "成分表少了這幾格：$MISS"
fi

case_ "2 對真的模型跑一次，五格對得上"
if [ ! -r "$MODEL/config.json" ]; then
  skip "找不到模型（$MODEL），這一條驗不掉。設 ANTARES_MLX 指過去"
else
  OUT=$(python3 stamp.py check "$MODEL" 2>&1); RC=$?
  if [ "$RC" = 0 ]; then
    ok "五格都通過，rc=0"
  else
    bad "rc=$RC，輸出：$(printf '%s' "$OUT" | tr '\n' '｜')"
  fi
fi

case_ "3 換描述之前那一輪：只有 prompt 那格不同"
# 這一條是這一天的骨幹。Day 27 換掉兩條類別描述，其中一題答案就翻了，
# 而兩輪存檔的 run.json 在 model 欄逐字相同，看不出差別在哪。
if [ ! -r "$MODEL/config.json" ]; then
  skip "找不到模型（$MODEL），這一條驗不掉"
elif [ ! -r "$REC27/cwes-firstdraft.tsv" ]; then
  bad "找不到 $REC27/cwes-firstdraft.tsv，換描述之前那一輪的表不見了"
else
  OUT=$(python3 stamp.py check "$MODEL" --cwes "$REC27/cwes-firstdraft.tsv" 2>&1); RC=$?
  P=$(verdict prompt "$OUT"); M=$(verdict model "$OUT")
  Q=$(verdict quant "$OUT"); SC=$(verdict script "$OUT"); C=$(verdict corpus "$OUT")
  if [ "$RC" = 1 ] && [ "$P" = 沒過 ] && [ "$M$Q$SC$C" = 通過通過通過通過 ]; then
    ok "prompt 那格不合、另外四格照樣通過，rc=1"
  else
    bad "rc=$RC，五格判定是 model=$M quant=$Q prompt=$P script=$SC corpus=$C"
  fi
fi

case_ "4 量化參數改掉，抓得到而且只有 quant 那格"
mkfake 4 weights-v1
python3 stamp.py record "$FAKE" "$FAKE/stamp.json" >/dev/null 2>&1
mkfake 8 weights-v1
OUT=$(python3 stamp.py check "$FAKE" "$FAKE/stamp.json" 2>&1); RC=$?
Q=$(verdict quant "$OUT"); M=$(verdict model "$OUT")
if [ "$RC" = 1 ] && [ "$Q" = 沒過 ] && [ "$M" = 通過 ]; then
  ok "4 bits 換成 8 bits：quant 那格不合，model 那格不動"
else
  bad "rc=$RC，quant=$Q model=$M"
fi

case_ "5 權重換一份，抓得到而且只有 model 那格"
mkfake 4 weights-v1
python3 stamp.py record "$FAKE" "$FAKE/stamp.json" >/dev/null 2>&1
mkfake 4 weights-v2
OUT=$(python3 stamp.py check "$FAKE" "$FAKE/stamp.json" 2>&1); RC=$?
M=$(verdict model "$OUT"); Q=$(verdict quant "$OUT")
if [ "$RC" = 1 ] && [ "$M" = 沒過 ] && [ "$Q" = 通過 ]; then
  ok "換一份權重：model 那格不合，quant 那格不動"
else
  bad "rc=$RC，model=$M quant=$Q"
fi

case_ "6 提示樣板跟腳本分得開：改註解只動 script 那格"
# 這一條驗的是成分的邊界畫對了。整支 hunt.py 一起算的話，改一個註解會讓
# prompt 那格跟著動，而「今天是提示變了還是程式變了」正是這張表要回答的。
if [ ! -r "$MODEL/config.json" ]; then
  skip "找不到模型（$MODEL），這一條驗不掉"
elif [ ! -w "$REC27/hunt.py" ]; then
  bad "改不動 $REC27/hunt.py，這一條驗不掉"
else
  cp "$REC27/hunt.py" "$FAKE/hunt.py.bak"
  printf '\n# 這一行是 verify.sh 暫時加的，跑完會拿掉\n' >> "$REC27/hunt.py"
  OUT=$(python3 stamp.py check "$MODEL" 2>&1); RC=$?
  cp "$FAKE/hunt.py.bak" "$REC27/hunt.py"
  SC=$(verdict script "$OUT"); P=$(verdict prompt "$OUT")
  if [ "$RC" = 1 ] && [ "$SC" = 沒過 ] && [ "$P" = 通過 ]; then
    ok "加一行註解：script 那格不合，prompt 那格不動"
  else
    bad "rc=$RC，script=$SC prompt=$P"
  fi
fi

case_ "7 被掃的程式碼改了，corpus 那格抓得到"
# 這一格是第二版才補的。第一版只有四格，沒有它，改掉 playground 裡任何一個 .js
# 都會全部通過，而被掃的程式碼是輸入裡最大的一塊。
PG=../../playground
VICTIM=$PG/src/api.js
if [ ! -r "$MODEL/config.json" ]; then
  skip "找不到模型（$MODEL），這一條驗不掉"
elif [ ! -w "$VICTIM" ]; then
  bad "改不動 $VICTIM，這一條驗不掉"
else
  cp "$VICTIM" "$FAKE/api.js.bak"
  printf '\n// 這一行是 verify.sh 暫時加的，跑完會拿掉\n' >> "$VICTIM"
  OUT=$(python3 stamp.py check "$MODEL" 2>&1); RC=$?
  cp "$FAKE/api.js.bak" "$VICTIM"
  C=$(verdict corpus "$OUT"); SC=$(verdict script "$OUT"); P=$(verdict prompt "$OUT")
  if [ "$RC" = 1 ] && [ "$C" = 沒過 ] && [ "$SC$P" = 通過通過 ]; then
    ok "被掃的檔案加一行：corpus 那格不合，script 與 prompt 不動"
  else
    bad "rc=$RC，corpus=$C script=$SC prompt=$P"
  fi
fi

case_ "8 corpus 收的檔案跟 hunt.py 掃的是同一組"
# 兩邊的收檔規則各寫一次，改一邊就靜默失效：stamp 記的是 A 組、模型讀的是 B 組，
# 而對帳照樣說通過。
#
# 比的是排序後的完整清單，不是檔案數。只比數量的話，「少收一個、多收另一個」
# 總數不變就矇混過去，而那是真的構造得出來的：playground/test/setup.js 就在那裡。
# 也不讀 stamp.json 存著的值，收檔規則改掉而沒重記，讀存檔會拿舊值替它掩護。
HAVE=$(cd "$PG" && find . -name '*.js' -not -path './test/*' | sed 's|^\./||' | sort | tr '\n' ' ')
if [ ! -r "$MODEL/config.json" ]; then
  skip "找不到模型（$MODEL），現算不了"
else
  python3 stamp.py record "$MODEL" "$FAKE/corpus-probe.json" >/dev/null 2>&1
  SAID=$(python3 -c "
import json, sys
print(' '.join(json.load(open(sys.argv[1]))['corpus'].get('檔', [])) + ' ')" "$FAKE/corpus-probe.json")
  if [ "$SAID" = " " ]; then
    bad "corpus 那格沒有檔案清單"
  elif [ "$HAVE" = "$SAID" ]; then
    ok "兩邊收的是同一組：${HAVE}"
  else
    bad "stamp 收的是 ${SAID}／hunt.py 那組規則收的是 ${HAVE}"
  fi
fi

case_ "9 缺東西是沒有結論，不是不合"
# 這兩件事混在一起的話，一台沒有模型的機器會把整張表印成不合，
# 而其實一格都沒比到。反過來也一樣糟：把缺檔當成通過。
mkfake 4 weights-v1
python3 stamp.py check "$FAKE" "$FAKE/nothing-here.json" >/dev/null 2>&1
[ "$?" = 2 ] && ok "沒有成分表：rc=2" || bad "沒有成分表時的離開碼不是 2"

python3 -c "
import json, sys
p = sys.argv[1] + '/stamp.json'
d = json.load(open(p)); del d['prompt']; json.dump(d, open(p, 'w'))" "$FAKE"
python3 stamp.py check "$FAKE" "$FAKE/stamp.json" >/dev/null 2>&1
[ "$?" = 2 ] && ok "成分表少一格：rc=2" || bad "成分表少一格時的離開碼不是 2"

rm -f "$FAKE/model.safetensors"
python3 stamp.py check "$FAKE" "$FAKE/stamp.json" >/dev/null 2>&1
[ "$?" = 2 ] && ok "權重檔不見了：rc=2" || bad "權重檔不見時的離開碼不是 2"

case_ "10 索引表收了這一份"
if grep -q '28-what-was-it-run-with' ../../README.md; then
  ok "README 的索引表有這一列"
else
  bad "README 的索引表沒有這一份 recipe"
fi

# ─────────────────────────────────────────────────────────────
printf '\n通過 %s、沒過 %s、沒有結論 %s\n' "$G" "$B" "$S"
[ "$B" = 0 ] || exit 1
[ "$S" = 0 ] || exit 2
exit 0
