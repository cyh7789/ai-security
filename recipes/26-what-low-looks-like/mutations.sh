#!/usr/bin/env bash
# 把 verify.sh 的每一條各弄壞一次，看它會不會紅。
#
#   bash mutations.sh
#
# 一條檢查沒有被咬過，它就只是一段跑得動的程式，不是一道閘。
#
# 這一份的突變大多在改**存檔與核對表**，不是改腳本。理由是這一天要防的東西
# 就在那裡：一份核對表最容易壞的方式不是寫錯程式，是核的人憑印象填一格。
set -u
cd "$(dirname "$0")"
export LC_ALL=C

BACKUP=$(mktemp -d)
cp verdict.tsv POSITIONING.md "${BACKUP}/"
cp -R first-look "${BACKUP}/first-look"
PGNEW=../../playground/src/_mutation_probe.js
restore() { cp "${BACKUP}/verdict.tsv" "${BACKUP}/POSITIONING.md" .; rm -rf first-look; cp -R "${BACKUP}/first-look" first-look; rm -f "$PGNEW"; }
trap 'restore; rm -rf "$BACKUP"' EXIT

P=0; F=0
run() {  # $1=編號 $2=說明 $3=期望（紅／綠）
  local out rc
  out=$(SKIP_RERUN="${SKIP_RERUN_THIS:-1}" bash verify.sh 2>&1); rc=$?
  local got=綠; [ "$rc" = 0 ] || got=紅
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
open(p,'w').writelines([l for l in L if 'err.message' not in l])"
run M5 "核對表少掉一個已知問題" 紅

python3 -c "
p='POSITIONING.md';s=open(p).read();open(p,'w').write(s.replace('指出三個','指出四個'))"
run M6 "聲明把命中數寫多一個" 紅

# 讓 innerHTML 那列的實際行號等於模型寫的 4，也就是「它其實指對了」。
python3 -c "
p='verdict.tsv';L=open(p).read().splitlines()
o=[]
for l in L:
    c=l.split('\t')
    if len(c)>8 and c[1]=='src/render.js': c[7]='4'; l='\t'.join(c)
    o.append(l)
open(p,'w').write('\n'.join(o)+'\n')"
run M7 "行號其實指對了，聲明沒跟著改" 紅

python3 -c "
p='POSITIONING.md';s=open(p).read();open(p,'w').write(s.replace('## 所以我怎麼用它','## 雜項'))"
run M8 "聲明少一節「所以我怎麼用它」" 紅

# 這一條要真的重跑，所以不設 SKIP_RERUN。改的是存檔內容，重跑出來就對不上。
python3 -c "
p='first-look/server_tools.js.txt';s=open(p).read();open(p,'w').write(s.replace('CWE-83','CWE-78'))"
SKIP_RERUN_THIS=0 run M9 "把存檔裡的編號改成對的那個" 紅

run M0 "什麼都不改（反向對照）" 綠

printf '\n通過 %s、沒咬到 %s\n' "$P" "$F"
[ "$F" = 0 ] || exit 1
