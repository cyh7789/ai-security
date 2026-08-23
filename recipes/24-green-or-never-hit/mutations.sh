#!/usr/bin/env bash
# 把 verify.sh 的每一條各弄壞一次，看它會不會紅。
#
#   bash mutations.sh
#
# 一條檢查沒有被咬過，它就只是一段跑得動的程式，不是一道閘。
# 每個突變破壞的是機制本身（判準看錯欄、對帳拿掉、閘門永遠說好），
# 不是刪掉我自己加的那幾行。刪除式的突變會咬到，但它證明不了那條檢查有在看什麼。
set -u
cd "$(dirname "$0")"
export LC_ALL=C

BACKUP=$(mktemp -d)
FILES="cases.tsv open-questions.tsv attacks-project.jsonl collect.mjs run.sh verify.sh cases.test.mjs kb-approved.txt retrieve.mjs"
cp $FILES "${BACKUP}/"
restore() { cp "${BACKUP}"/* .; }
trap 'restore; rm -rf "${BACKUP}"' EXIT

G=0; B=0
# 樣式裡的 \n 當成換行。有些突變非跨行不可：run.sh 裡「else echo 沒打到; fi」
# 出現兩次（agent_delete 與 fetchprobe），只有把下一行帶上才指得準是哪一個。
sub() { python3 -c '
import io,sys
p=sys.argv[1]; s=io.open(p,encoding="utf8").read()
for i in range(2,len(sys.argv),2):
    a,b=[x.replace("\\n","\n") for x in (sys.argv[i],sys.argv[i+1])]
    if s.count(a)!=1: sys.exit(f"樣式不只一處或找不到：{a!r}")
    s=s.replace(a,b)
io.open(p,"w",encoding="utf8").write(s)' "$@"; }

# 基線：動手之前 verify.sh 要是綠的。不先驗這件事的話，
# 一個本來就紅的 verify 會讓每一個突變都「咬到」。
if bash verify.sh >/dev/null 2>&1; then
  printf '基線：verify.sh 綠\n\n'
else
  echo "基線就不是綠的，突變的結果沒有意義。先修 verify.sh。" >&2
  exit 2
fi

bite() {  # $1=描述 $2=預期咬到的條號 $3.. = sub 的參數
  local desc=$1 want=$2; shift 2
  sub "$@" || { printf '  跳過\t%-42s 樣式對不上\n' "${desc}"; B=$((B+1)); restore; return; }
  local out rc
  out=$(bash verify.sh 2>&1); rc=$?
  restore
  # 只認離開碼 1。離開碼 2 是「這一跑沒有結論」，把它算成咬到的話，
  # 一個讓 verify.sh 開頭就死掉的突變會被記成成功（Day 23 付過這個學費）。
  if [ "$rc" = 1 ]; then
    local hit
    hit=$(printf '%s' "${out}" | awk -v w="${want}" '/^=== /{n=$2} /^  紅/{print n}' | sort -u | tr '\n' ' ')
    case " ${hit} " in
      *" ${want} "*) printf '  咬到\t%-42s 第 %s 條\n' "${desc}" "${want}"; G=$((G+1)) ;;
      *) printf '  咬錯\t%-42s 預期第 %s 條，紅的是：%s\n' "${desc}" "${want}" "${hit}"; B=$((B+1)) ;;
    esac
  else
    printf '  沒咬到\t%-42s 離開碼 %s\n' "${desc}" "${rc}"; B=$((B+1))
  fi
}

echo "=== 突變 ==="
bite "不認得的案例當成擋住了" 2 run.sh \
  '    *)   echo 跑不動 ;;' '    *)   echo 擋住 ;;'
bite "判準改成 grep 模型的回覆" 3 run.sh \
  '  d=$(printf '"'"'%s'"'"' "$out" | awk -F'"'"'\t'"'"' '"'"'{print $6}'"'"')' \
  '  d=$(grep -c . <<< "$REPLY_FILE"; printf '"'"'%s'"'"' "$out" | awk -F'"'"'\t'"'"' '"'"'{print $6}'"'"')'
bite "run.sh 有缺口也回 0" 4 run.sh \
  '    res=缺口; [ "$rc" -lt 1 ] && rc=1' '    res=缺口'
bite "判「有沒有出事」改成看閘怎麼回報" 12 run.sh \
  '  d=$(printf '"'"'%s'"'"' "$out" | awk -F'"'"'\t'"'"' '"'"'{print $6}'"'"')' \
  '  d=$([ "$(printf '"'"'%s'"'"' "$out" | awk -F'"'"'\t'"'"' '"'"'{print $4}'"'"')" = deny ] && echo no || echo yes)'
bite "一條基線案例被降級成可接受" 6 cases.tsv \
  '（agent 第六欄 deleted）	沒擋	意圖核對閘' '（agent 第六欄 deleted）	沒擋	X意圖核對閘' \
  'C01	R4	訂單備註欄裡的系統通知口吻，走意圖核對閘	擋' 'C01	R4	訂單備註欄裡的系統通知口吻，走意圖核對閘	可接受'
bite "collect.mjs 不再檢查期望欄的值域" 7 collect.mjs \
  'if (!["擋", "可接受"].includes(c.期望)) die' 'if (false) die'
bite "collect.mjs 不再跟攻擊面清單對帳" 8 collect.mjs \
  'if (missing.length) die' 'if (false) die'
bite "同一條路徑兩邊都掛" 9 open-questions.tsv \
  'Q1	R2	使用者上傳' 'Q1	R4	使用者上傳'
bite "open-questions 有一列答不出補法" 10 open-questions.tsv \
  '同 Q1。它現在唯一講得出口的結論' '-	它現在唯一講得出口的結論'
bite "collect.mjs 的 --check 永遠說一致" 11 collect.mjs \
  '  if (cur === out) {' '  if (true) {'
bite "C05 不再比對讀到的是誰的單" 13 run.sh \
  '  [ "$owner" != 2 ] && echo 沒擋 || echo 擋住' \
  '  [ -n "$owner" ] && echo 沒擋 || echo 擋住'
bite "核准清單改成從匯出檔自己算" 14 kb-approved.txt \
  'handbook:' '（這一份改成讀 demo/kb.jsonl 自己算）'
bite "檢索改讀本地抄來的知識庫" 15 retrieve.mjs \
  '../13-who-wrote-your-knowledge-base/demo/kb.jsonl' 'demo/kb.jsonl'
bite "測試名字不再帶狀態" 16 cases.test.mjs \
  'test(`${id}（${path}｜${state(want, now)}）${one}`' 'test(`${id}（${path}）${one}`'
bite "「沒打到」折回「跑不動」" 12 run.sh \
  '  else echo 沒打到; fi\n}\n\n# R7：讀取有沒有真的發生' '  else echo 跑不動; fi\n}\n\n# R7：讀取有沒有真的發生'
bite "方向不分期望，可接受那類也用同一套" 17 run.sh \
  '    [ "$2" = 沒擋 ] && echo 誤擋了 || echo 放行了' \
  '    [ "$2" = 沒擋 ] && echo 補起來了 || echo 退步了'
bite "collect.mjs 不再拿 reach.log 對帳" 11b collect.mjs \
  'if (dodged.length) {' 'if (false) {'
bite "run.sh 不再拿紀錄跟實測對帳" 18 run.sh \
  '  elif [ "$got" != "$now" ]; then' '  elif false; then'

echo
echo "=== 反向控制：不影響行為的改動，全部要維持綠 ==="
sub run.sh '# 跑 cases.tsv 上的每一個案例' '# 跑 cases.tsv 上的每一個案例（註解改過）'
if bash verify.sh >/dev/null 2>&1; then printf '  沒誤咬\t只改註解\n'; G=$((G+1)); else printf '  誤咬\t只改註解\n'; B=$((B+1)); fi
restore

printf '\n%s 種咬到 %s 種沒咬到\n' "$G" "$B"
[ "$B" = 0 ] || exit 1
