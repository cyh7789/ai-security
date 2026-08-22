#!/usr/bin/env bash
# 這一份的閘。跑完會告訴你哪一條沒過。
#
#   bash verify.sh
#
# 離開碼照 Day 22 那份公約：0 全過、1 有東西紅了、2 環境不到位（沒有結論）。
set -u
cd "$(dirname "$0")"

# 這一行是必要的，不是習慣問題。macOS 內建的 awk（version 20200816）在
# en_US.UTF-8 底下，$n == "<任何含中文的字串>" 一律成立：拿一個資料裡根本
# 沒有的值去比，三列全中（2026-08-22 實測，LC_ALL=C 下才回正確的 0）。
# 這份的判準幾乎每一條都在比中文欄位，不釘住 locale 的話會整片假綠。
# Day 16 的 verify.sh:270 就撞過同一件事，我今天又踩了一次。
export LC_ALL=C
PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  綠\t%s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  紅\t%s\n' "$1"; [ $# -gt 1 ] && printf '    \t%s\n' "$2"; }

command -v node >/dev/null || { echo "沒有 node，沒有結論"; exit 2; }

# surface.tsv 的資料列（去掉註解與表頭）
data() { grep -v '^#' surface.tsv | grep -v '^id	'; }

echo "── 一、清單本身"

# 不要寫成「至少幾列」。下限擋不了刪兩列走人，而列數正是這份清單的產出本身。
# 這裡跟 reach.log 的資料列數互相釘，兩邊要一起改才動得了。
N=$(data | grep -c .)
NR_=$(grep -vc '^id	' reach.log 2>/dev/null || echo 0)
[ "$N" = "$NR_" ] && ok "surface.tsv 與 reach.log 都是 ${N} 列" \
  || bad "surface.tsv ${N} 列、reach.log ${NR_} 列，兩邊對不上（reach.log 要重跑：bash reach.sh > reach.log）"

# 「可達」只有三個值。這一條擋的是「應該可以」那種寫法混進來。
BADV=$(data | awk -F'\t' '$5!="到得了" && $5!="被擋死" && $5!="沒驗過" {print $1"="$5}')
[ -z "$BADV" ] && ok "可達欄只有三個值" || bad "可達欄出現別的值" "$BADV"

# 每一列都要有證據。空的那格等於憑感覺填的。
NOEV=$(data | awk -F'\t' '$6=="" || $6=="-" {print $1}')
# 「非空」擋不掉隨便寫一句。每一列的證據要指得到一個真的存在的檔案，
# 不然那一格只是話術。這裡抓 xx-name/file.ext 這種寫法逐一確認。
GHOSTF=$(data | awk -F'\t' '{print $1"\t"$6}' | while IFS='	' read -r id ev; do
  for f in $(printf '%s' "$ev" | grep -oE '[0-9]{2}/[a-z0-9.-]+\.(mjs|cjs|sh|tsv|txt|jsonl)'); do
    d=$(printf '%s' "$f" | cut -d/ -f1); b=$(printf '%s' "$f" | cut -d/ -f2)
    ls ../"${d}"-*/"${b}" >/dev/null 2>&1 || echo "${id}:${f}"
  done
done)
if [ -z "$NOEV" ] && [ -z "$GHOSTF" ]; then ok "每一列都有證據，引到的檔案都存在"
else bad "證據欄有問題" "空的：${NOEV:-無}／指不到的檔：${GHOSTF:-無}"; fi

echo "── 二、可達性要跟 reach.sh 跑出來的對得上"

# 這是這份 recipe 最重要的一條：可達不是人填的，是跑出來的。
bash reach.sh > /tmp/d23-reach.$$ 2>/dev/null
RC=$?
if [ "$RC" = 2 ]; then
  echo "  reach.sh 回 2，有列沒跑動，沒有結論"
  rm -f /tmp/d23-reach.$$
  exit 2
fi

MISMATCH=$(awk -F'\t' '
  NR==FNR {
    if (FNR==1 || $1=="") next
    stop[$1]=$4
    next
  }
  /^#/ || $1=="id" || NF<5 { next }
  {
    s = stop[$1]
    if (s == "") { print $1"：reach.log 裡沒有這一列"; next }
    want = (s ~ /^到達/ || s ~ /^抵達/) ? "到得了" : (s ~ /^閘:/) ? "被擋死" : (s ~ /^沒驗過/) ? "沒驗過" : "看不懂"
    if (want != $5) print $1"：清單寫 "$5"，實跑是 "s" 也就是 "want
  }
' /tmp/d23-reach.$$ <(data))
[ -z "$MISMATCH" ] && ok "每一列的可達都跟實跑一致" || bad "清單跟實跑對不上" "$MISMATCH"

# 反過來也要查：reach.sh 跑了但清單上沒有的列，等於量了卻沒記。
ORPHAN=$(awk -F'\t' 'NR==FNR && !/^#/ && $1!="id" {have[$1]=1; next} FNR>1 && $1!="" && !($1 in have) {print $1}' <(data) /tmp/d23-reach.$$)
[ -z "$ORPHAN" ] && ok "實跑的每一列都在清單上" || bad "這些列跑了卻沒記進清單" "$ORPHAN"

echo "── 三、Day 24 要接得下去"

# 規格 Day 24 動作 3 要一條已知會被打穿的基線案例。
# 今天全部標成被擋死的話，明天那天的【判斷】會落空。
BASE=$(data | awk -F'\t' '$5=="到得了" && $7 ~ /^是/ {print $1}' | tr '\n' ' ')
[ -n "$BASE" ] && ok "有到得了而且要出案例的列：${BASE}" || bad "沒有任何一條到得了的基線案例，Day 24 沒有東西可以驗"

# 規格【接點】要逐條核對知識庫寫入口。這一列不能因為還沒接上就從清單消失。
data | awk -F'\t' '$2 ~ /知識庫/' | grep -q . \
  && ok "知識庫那一類有列進來" || bad "清單上找不到知識庫那一類"

echo "── 四、骨架"

node gen-skeletons.mjs --check >/dev/null 2>&1 \
  && ok "骨架跟 surface.tsv 一致" || bad "骨架跟 surface.tsv 對不上，跑 node gen-skeletons.mjs 重生"

# 骨架今天不准有 assert 條件：成功條件由人定，那是 Day 24 的事。
HASASSERT=$(grep -lE 'assert|strictEqual|deepEqual' skeletons/*.test.mjs 2>/dev/null | tr '\n' ' ')
[ -z "$HASASSERT" ] && ok "骨架裡沒有 assert 條件" || bad "骨架裡出現 assert 條件" "$HASASSERT"

# 骨架不准偷偷混進 Day 14 的固定攻擊集。
# grep 的離開碼 2（檔案讀不到）跟 1（沒找到）不能走同一個分支，
# 不然檔案不見的時候這條會印綠，而那是「跑不動卻宣稱驗過」。
A14=../14-same-attacks-every-time/attacks.jsonl
if [ ! -r "$A14" ]; then
  echo "  讀不到 ${A14}，沒有結論"; rm -f /tmp/d23-reach.$$; exit 2
elif grep -q '23-what-can-actually-reach-it' "$A14"; then
  bad "骨架混進 14/attacks.jsonl 了，那是 Day 24 才動的"
else
  ok "14/attacks.jsonl 沒有被動到"
fi

echo "── 五、白箱那半"

# 模型列了幾條、我擋掉幾條。這個比例是規格【分工】要的證據，
# 而它只有在「判決的列數等於模型列的列數」時才算得準。
MROWS=$(grep -vc '^編號' whitebox/sol-paths.tsv)
VROWS=$(grep -v '^#' whitebox/verdicts.tsv | grep -vc '^它列的')
[ "$MROWS" = "$VROWS" ] && ok "模型列 ${MROWS} 條，判決也是 ${VROWS} 條" \
  || bad "模型列 ${MROWS} 條，判決只有 ${VROWS} 條，有沒判的"

# 這三個數字是文章直接引用的，不能只驗「在合理區間」。釘死，改判決就要一起改這裡。
TAKE=$(grep -v '^#' whitebox/verdicts.tsv | awk -F'\t' '$2=="收"' | grep -c .)
FIX=$(grep -v '^#' whitebox/verdicts.tsv | awk -F'\t' '$2=="更正後收"' | grep -c .)
IN=$((TAKE+FIX))
[ "$TAKE" = 10 ] && [ "$FIX" = 1 ] && [ "$IN" -lt "$MROWS" ] \
  && ok "收 ${TAKE}、更正後收 ${FIX}，進清單 ${IN} 條、擋掉 $((MROWS-IN)) 條" \
  || bad "判決分佈變了（收 ${TAKE}、更正後收 ${FIX}、共 ${MROWS}），文章那張表要跟著改"

# 判「收」的那些列，對應欄指的 id 要真的在清單上。
GHOST=$(grep -v '^#' whitebox/verdicts.tsv | awk -F'\t' '$2=="收"||$2=="更正後收"{print $4}' | sort -u \
        | while read -r i; do data | cut -f1 | grep -qx "$i" || echo "$i"; done)
[ -z "$GHOST" ] && ok "判決指到的 id 都在清單上" || bad "判決指到清單上沒有的 id" "$GHOST"

# 判「引用對不上」的那兩列，要自己重現得了：那些檔案真的不存在。
STILL=$(grep -v '^#' whitebox/verdicts.tsv | awk -F'\t' '$2=="引用對不上"{print $3}' \
        | grep -oE '1[0-9]-[a-z-]+/[a-z-]+\.(mjs|cjs)' | sort -u \
        | while read -r f; do
            [ -e "../$f" ] && echo "$f 其實存在"
            # 那個路徑要真的是模型寫的，不然編一個不存在的檔名就能拿到這個判決
            grep -q "$f" whitebox/sol-paths.tsv || echo "$f 不在模型交的原文裡"
          done)
[ -z "$STILL" ] && ok "判成引用對不上的檔案確實不存在，而且真的是模型寫的" || bad "判錯了" "$STILL"

echo "── 六、佐證文件那條路徑"

# R2 跟 R3 的差別要真的存在：--gate both 得真的把附件送進場景那道閘。
# 不然那兩列在講同一件事，R3 是空的。
B=$(node intake.mjs --doc docs/injected.txt --gate both 2>/dev/null | cut -f4)
T=$(node intake.mjs --doc docs/injected.txt 2>/dev/null | cut -f4)
[ "$T" = "allow(NOT_GATED)" ] && [ "$B" = "allow(SCENARIO_OK)" ] \
  && ok "typed 沒閘到附件、both 閘到了而且照樣放行" \
  || bad "R2 與 R3 的差別不成立" "typed=${T} both=${B}"

# 兩份佐證文件只差最後那段。差太多的話 R2 量到的就不只是那一段。
# 釘死行數，不用上限。上限放得過「只改一份」那種單邊修改，
# 而單邊修改會讓 R2 量到的不只是夾帶那一段（2026-08-22 審查指出這條沒有突變覆蓋）。
D=$(diff docs/order-shot.txt docs/injected.txt | grep -c '^>')
E=$(diff docs/order-shot.txt docs/injected.txt | grep -c '^<')
[ "$D" = 4 ] && [ "$E" = 0 ] \
  && ok "兩份佐證文件只差夾帶的那 4 行，其餘逐字相同" \
  || bad "兩份佐證文件多了 ${D} 行、少了 ${E} 行，不是只差夾帶那一段"

echo
echo "${PASS} 綠 ${FAIL} 紅"
rm -f /tmp/d23-reach.$$
[ "$FAIL" = 0 ] || exit 1
