#!/usr/bin/env bash
# 把 verify.sh 的每一條各弄壞一次，看它會不會紅。
#
#   bash mutations.sh
#
# 一條檢查沒有被咬過，它就只是一段跑得動的程式，不是一道閘。
# 每個突變破壞的是機制本身（方向自己重算、對照表少一列、存檔的版本欄造假），
# 不是刪掉我自己加的那幾行。
#
# 這一份的突變分兩種來源：改腳本，跟改存檔。改存檔那幾條特別重要，
# 因為這一天要防的就是「有人事後把那份 before 改得好看一點」。
set -u
cd "$(dirname "$0")"
export LC_ALL=C
R=..

BACKUP=$(mktemp -d)
FILES="README.md snapshot.sh compare.sh verify.sh"
cp $FILES "${BACKUP}/"
mkdir -p "${BACKUP}/snap"
for d in before-default after-default before-gate after-gate final; do
  mkdir -p "${BACKUP}/snap/$d"; cp "$d/run.tsv" "${BACKUP}/snap/$d/"
done
restore() {
  cp "${BACKUP}"/*.md "${BACKUP}"/*.sh .
  for d in before-default after-default before-gate after-gate final; do
    cp "${BACKUP}/snap/$d/run.tsv" "$d/"
  done
}
trap 'restore; rm -rf "${BACKUP}"' EXIT

G=0; B=0
sub() { python3 -c '
import io,sys
p=sys.argv[1]; s=io.open(p,encoding="utf8").read()
for i in range(2,len(sys.argv),2):
    a,b=[x.replace("\\n","\n").replace("\\t","\t") for x in (sys.argv[i],sys.argv[i+1])]
    if s.count(a)!=1: sys.exit(f"樣式不只一處或找不到：{a!r}")
    s=s.replace(a,b)
io.open(p,"w",encoding="utf8").write(s)' "$@"; }

if bash verify.sh >/dev/null 2>&1; then
  printf '基線：verify.sh 綠\n\n'
else
  echo "基線就不是綠的，突變的結果沒有意義。先修 verify.sh。" >&2
  exit 2
fi

bite() {  # $1=描述 $2=預期咬到的條號 $3.. = sub 的參數
  local desc=$1 want=$2; shift 2
  sub "$@" || { printf '  跳過\t%-44s 樣式對不上\n' "${desc}"; B=$((B+1)); restore; return; }
  local out rc
  out=$(bash verify.sh 2>&1); rc=$?
  restore
  # 只認離開碼 1。離開碼 2 是「這一跑沒有結論」，算成咬到的話，
  # 一個讓 verify.sh 開頭就死掉的突變會被記成成功。
  if [ "$rc" = 1 ]; then
    local hit
    hit=$(printf '%s' "${out}" | awk -v w="${want}" '/^=== /{n=$2} /^  紅/{print n}' | sort -u | tr '\n' ' ')
    case " ${hit} " in
      *" ${want} "*) printf '  咬到\t%-44s 第 %s 條\n' "${desc}" "${want}"; G=$((G+1)) ;;
      *) printf '  咬錯\t%-44s 預期第 %s 條，紅的是：%s\n' "${desc}" "${want}" "${hit}"; B=$((B+1)) ;;
    esac
  else
    printf '  沒咬到\t%-44s 離開碼 %s\n' "${desc}" "${rc}"; B=$((B+1))
  fi
}

echo "=== 突變：改腳本 ==="
bite "重跑改成拿現在這一版，不從版控取" 1 verify.sh \
  '  git -C "$ROOT" show "${c}:recipes/${rec}/${f}" > "$t/r/$f" 2>/dev/null || { rm -rf "$t"; return 1; }' \
  '  cp "$R/$rec/$f" "$t/r/$f" || { rm -rf "$t"; return 1; }'
bite "compare 自己算方向，不分期望" 13 compare.sh \
  '    chg=$(direction "$want" "$got")' '    chg=補起來了'
bite "compare 不再點出同一個 commit" 14 compare.sh \
  'if [ "$CA" = "$CB" ]; then' 'if false; then'
bite "沒走到終點也照樣給一個方向" 19 compare.sh \
  '  elif [ "$got" != 擋住 ] && [ "$got" != 沒擋 ]; then' '  elif false; then'
bite "compare 靜靜收下多出來的案例" 15 compare.sh \
  'if [ -n "$(printf '"'"'%s'"'"' "$EXTRA" | tr -d '"'"' '"'"')" ]; then' 'if false; then'
# 把「這幾個 SHA 在不在」換回「是不是淺複製」，也就是這一條修掉的那個 bug。
# 咬得到的原因：第 20 條會造一個深度 100 的複本，那種複本 is-shallow 是 true
# 而五個 SHA 都在，舊寫法會在那裡誤判成沒有結論。本機不淺，所以這個突變
# 只有靠第 20 條那個複本才咬得到。
bite "偵測退回問淺複製，不問 SHA 在不在" 20 verify.sh \
  '  git -C "$ROOT" cat-file -e "${c}^{commit}" 2>/dev/null || MISSING="${MISSING} ${d}(${c})"' \
  '  [ "$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = true ] && MISSING="${MISSING} ${d}"'
bite "snapshot 的髒欄永遠寫 no" 17 snapshot.sh \
  'if [ -n "$(git status --porcelain -- "$R" ":(exclude)$R/$SELF" 2>/dev/null)" ]; then DIRTY=yes; else DIRTY=no; fi' \
  'DIRTY=no'
# 項數從 verify.sh 自己數，不寫死：加一條檢查就換一個數字，寫死的話錨點會對不上。
bite "README 的項數沒跟上" 16 README.md \
  "自己的檢查，$(grep -c '^case_ \"' verify.sh) 項" "自己的檢查，1 項"

echo
echo "=== 突變：改存檔（事後把紀錄改得好看一點）==="
# 咬的是祖先關係那一支，不是「這個 SHA 在不在版控裡」：塞一個不成立的字串進去，
# 紅的會是後者，而 README 把第 5 條列為對抗「順序偷偷倒過來」的防法，
# 那個防法真正的機制是 merge-base --is-ancestor。
# 改 final 的而不是 before 的：before-default 與 before-gate 的 commit 還被第 1、3 條
# 拿去重跑，動它們會同時咬到兩條，而 bite 只認一條。
# 前一個值從檔案自己讀，不寫死：final 重存過就換一個 SHA，寫死的話錨點會對不上。
# 後一個是 Day 24 交件那一版（main 上的 4b810fd），它必定早於這條分支的每一個 commit。
bite "把 final 的 commit 換成 before 之前的" 5 final/run.tsv \
  "# commit\t$(sed -n 's/^# commit\t//p' final/run.tsv)" \
  "# commit\t$(git rev-parse 4b810fd)"
bite "把某一份的髒欄改成 yes" 6 final/run.tsv \
  '# 被量的那些 recipe 有未提交的改動\tno' '# 被量的那些 recipe 有未提交的改動\tyes'
bite "把主線那一條的 after 改回沒擋" 7 after-default/run.tsv \
  'C13\tR10\t擋\t沒擋\t擋住\t補起來了' 'C13\tR10\t擋\t沒擋\t沒擋\t缺口'
bite "一條本來擋得住的對照組在 final 破了" 9 final/run.tsv \
  'C04\tR5\t擋\t擋住\t擋住\t符合' 'C04\tR5\t擋\t擋住\t沒擋\t退步了'
bite "正常客人被擋掉了而紀錄照樣說符合" 10 final/run.tsv \
  'C15\tR15\t可接受\t沒擋\t沒擋\t符合' 'C15\tR15\t可接受\t沒擋\t擋住\t誤擋了'
bite "把不修的那條也塗成綠的" 12 final/run.tsv \
  'C07\tR10\t擋\t沒擋\t沒擋\t缺口' 'C07\tR10\t擋\t擋住\t擋住\t符合'

echo
echo "=== 反向控制：不影響行為的改動，要維持綠 ==="
sub compare.sh '# 兩份存檔逐條對照' '# 兩份存檔逐條對照（註解改過）'
if bash verify.sh >/dev/null 2>&1; then printf '  沒誤咬\t只改註解\n'; G=$((G+1)); else printf '  誤咬\t只改註解\n'; B=$((B+1)); fi
restore

printf '\n%s 種咬到 %s 種沒咬到\n' "$G" "$B"
[ "$B" = 0 ] || exit 1
