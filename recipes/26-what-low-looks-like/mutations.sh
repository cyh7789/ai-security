#!/usr/bin/env bash
# 把 verify.sh 的每一條各弄壞一次，看它會不會紅。
#
#   bash mutations.sh
#
# 一條檢查沒有被咬過，它就只是一段跑得動的程式，不是一道閘。
#
# 這一份的突變大多在改**存檔與核對表**，不是改腳本。理由是這一天要防的東西
# 就在那裡：一份核對表最容易壞的方式不是寫錯程式，是核的人憑印象填一格。
#
# 「沒有結論」不算「紅」。混在一起的話，一台沒有模型的機器會把整張突變表
# 印成十條通過，而其實一條都沒驗到（2026-08-25 實測，那一版跟真的跑過逐字相同）。
set -u
cd "$(dirname "$0")"
export LC_ALL=C

MODEL="${ANTARES_MLX:-./antares-1b-mlx}"
[ -r "$MODEL/config.json" ] || {
  echo "找不到模型（$MODEL）。M9 要真的重跑一輪，沒有模型這張表驗不掉，沒有結論。" >&2
  echo "設 ANTARES_MLX 指過去。" >&2
  exit 2
}

BACKUP=$(mktemp -d)
cp verdict.tsv POSITIONING.md "${BACKUP}/"
cp -R first-look "${BACKUP}/first-look"
PGNEW=../../playground/src/_mutation_probe.js
restore() {
  cp "${BACKUP}/verdict.tsv" "${BACKUP}/POSITIONING.md" .
  rm -rf first-look; cp -R "${BACKUP}/first-look" first-look
  rm -f "$PGNEW"
}
trap 'restore; rm -rf "$BACKUP"' EXIT

P=0; F=0
run() {  # $1=編號 $2=說明 $3=期望（紅／綠）
  local out rc got
  out=$(SKIP_RERUN="${SKIP_RERUN_THIS:-1}" ANTARES_MLX="$MODEL" bash verify.sh 2>&1); rc=$?
  case "$rc" in
    0) got=綠 ;;
    2) got=沒有結論 ;;
    *) got=紅 ;;
  esac
  if [ "$got" = "$3" ]; then printf '%s\t%s\t期望%s\t得到%s\t通過\n' "$1" "$2" "$3" "$got"; P=$((P+1))
  else printf '%s\t%s\t期望%s\t得到%s\t**沒咬到**\n' "$1" "$2" "$3" "$got"; F=$((F+1))
  fi
  restore
}

printf '編號\t突變\t期望\t得到\t結果\n'

printf 'export function noop() { return 1; }\n' > "$PGNEW"
run M1 "playground 多一個存檔沒收的 .js" 紅

: > first-look/src_render.js.txt
run M2 "把一份原始輸出清空" 紅

python3 -c "
import json;p='first-look/run.json';d=json.load(open(p));d['total_seconds']=99.9;json.dump(d,open(p,'w'))"
run M3 "存檔的總秒數改掉，逐檔不動" 紅

# 只改一個字：把 sanitization 改成 validation。核對表看起來照樣像有引原句。
python3 -c "
p='verdict.tsv';s=open(p).read();open(p,'w').write(s.replace('without sanitization.','without validation.'))"
run M4 "核對表的依據改一個字（憑印象填）" 紅

python3 -c "
p='verdict.tsv';L=open(p).read().splitlines(True)
open(p,'w').writelines([l for l in L if 'CWE-90 | line 9' not in l])"
run M5 "核對表漏記一條模型多吐的候選" 紅

# 這一列的判定是「沒指到」，而它要證的是「整份輸出裡沒有東西提到 user_id」。
# 在存檔裡塞一條真的提到 user_id 的候選，那個判定就不成立了。
python3 -c "
p='first-look/server_orders.js.txt'
open(p,'a').write('CWE-639 | line 6 | Order lookup does not check user_id ownership.\n')"
run M6 "存檔裡多一條真的講到 user_id 的候選" 紅

python3 -c "
p='POSITIONING.md';s=open(p).read();open(p,'w').write(s.replace('指出三個','指出四個'))"
run M7a "聲明把命中數寫多一個" 紅

python3 -c "
p='POSITIONING.md';s=open(p).read();open(p,'w').write(s.replace('33.1 秒','34.2 秒'))"
run M7b "聲明的秒數改成規格裡那個沒有來源的數字" 紅

# 讓 innerHTML 那列的實際行號等於模型寫的 4，也就是「它其實指對了」。
python3 -c "
p='verdict.tsv';L=open(p).read().splitlines()
o=[]
for l in L:
    c=l.split('\t')
    if len(c)>8 and c[1]=='src/render.js' and c[6]=='4': c[7]='4'; l='\t'.join(c)
    o.append(l)
open(p,'w').write('\n'.join(o)+'\n')"
run M8 "多一條行號其實指對了，聲明沒跟著改" 紅

python3 -c "
p='POSITIONING.md';s=open(p).read();open(p,'w').write(s.replace('## 所以我怎麼用它','## 雜項'))"
run M9a "聲明少一節「所以我怎麼用它」" 紅

# 這一條要真的重跑，所以不設 SKIP_RERUN。改的是存檔內容，重跑出來就對不上。
python3 -c "
p='first-look/server_tools.js.txt';s=open(p).read();open(p,'w').write(s.replace('CWE-83','CWE-78'))"
SKIP_RERUN_THIS=0 run M9b "把存檔裡的編號改成對的那個" 紅

# 反向對照兩條。第二條問的是「跳過會不會被算成通過」。
run M0a "什麼都不改，第 10 條跳過" 沒有結論
SKIP_RERUN_THIS=0 run M0b "什麼都不改，第 10 條真的跑" 綠

printf '\n通過 %s、沒咬到 %s\n' "$P" "$F"
[ "$F" = 0 ] || exit 1
