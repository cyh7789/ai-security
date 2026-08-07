#!/usr/bin/env bash
# 把 AI 推薦給你的套件名餵進來，逐一到 npm 官方註冊處查。
#
# 這支只讀不寫：只打 registry.npmjs.org 與 api.npmjs.org 的唯讀 API，不裝任何東西。
#
# 用法：
#   bash check-pkgs.sh express zod                 直接給名字
#   bash check-pkgs.sh -f pkgs.txt                 一行一個
#   pbpaste | bash check-pkgs.sh -                 從剪貼簿
#
# 為什麼開頭要跑兩個對照：
#   「查不到這個套件」有兩種原因，一種是註冊處說沒有，一種是你根本沒問到註冊處
#   （網路斷了、curl 沒裝、公司代理擋掉）。兩種在畫面上長得一模一樣。
#   所以先問一個一定在的和一個一定不在的，兩邊都答對，後面的答案才有意義。

set -u

# 用私有註冊處的話覆寫這兩個。verify.sh 也靠 NPM_REGISTRY 指到一個連不到的位址，
# 驗「連不到的時候會不會把它講成不存在」。
REG=${NPM_REGISTRY:-https://registry.npmjs.org}
DL=${NPM_DOWNLOADS:-https://api.npmjs.org/downloads/point/last-week}

for t in curl node; do
  command -v "${t}" >/dev/null 2>&1 || { echo "沒有 ${t}，這支跑不了"; exit 2; }
done

# 回一行：<HTTP 狀態碼> <TAB> <內文壓成一行>。curl 自己失敗的時候狀態碼是 000
fetch() {
  curl -s -m 20 -w '\n%{http_code}' "$1" 2>/dev/null | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const i=s.lastIndexOf("\n");
  process.stdout.write((i<0?"000":s.slice(i+1).trim()||"000")+"\t"+(i<0?"":s.slice(0,i)).replace(/[\r\n]+/g," "));
})' 2>/dev/null || printf '000\t'
}

# ── 對照組 ────────────────────────────────────────────────
CTRL_YES=$(fetch "${REG}/express" | cut -f1)
CTRL_NO=$(fetch "${REG}/npm-registry-probe-$$-$(date +%s)-zzq" | cut -f1)
if [ "${CTRL_YES}" != "200" ] || [ "${CTRL_NO}" != "404" ]; then
  echo "對照組沒過：一定在的回 ${CTRL_YES}（該是 200），一定不在的回 ${CTRL_NO}（該是 404）"
  echo "現在問不到註冊處，下面查出來的任何「不存在」都不算數。先修連線再跑。"
  exit 2
fi

# ── 收集要查的名字 ────────────────────────────────────────
names=()
add() { local l=${1%%#*}; l=$(printf '%s' "${l}" | tr -d '[:space:]'); [ -n "${l}" ] && names+=("${l}"); return 0; }
if [ "${1:-}" = "-f" ]; then
  [ -r "${2:-}" ] || { echo "讀不到 ${2:-<沒給檔名>}"; exit 2; }
  while IFS= read -r line || [ -n "${line}" ]; do add "${line}"; done < "$2"
elif [ "${1:-}" = "-" ]; then
  while IFS= read -r line || [ -n "${line}" ]; do add "${line}"; done
else
  for a in "$@"; do add "${a}"; done
fi
[ ${#names[@]} -gt 0 ] || { echo "沒給任何套件名"; exit 2; }

# ── 逐一查 ────────────────────────────────────────────────
# 判定只有三種，都刻意寫成兩個字，這樣欄位在終端機裡才對得齊：
#   查到＝註冊處回了這個套件的資料 ／ 沒有＝註冊處明講沒有這個名字 ／ 錯誤＝沒問到，重跑
printf '判定     週下載  最後發布  版本 維護者 原始碼  套件\n'
NOTES=""
for p in "${names[@]}"; do
  enc=$(printf '%s' "${p}" | sed 's|/|%2f|')
  resp=$(fetch "${REG}/${enc}")
  code=${resp%%	*}

  case "${code}" in
    200) ;;
    404)
      printf '沒有 %10s %9s %5s %5s   %s   %s\n' - - - - - "${p}"
      NOTES="${NOTES}${p}｜註冊處上沒有這個名字。AI 生的名字裡最好的一種，因為它會當場裝失敗。
"
      continue ;;
    *)
      printf '錯誤 %10s %9s %5s %5s   %s   %s\n' - - - - - "${p}"
      NOTES="${NOTES}${p}｜HTTP ${code}。這不是「不存在」，是沒問到。重跑。
"
      continue ;;
  esac

  fields=$(printf '%s' "${resp#*	}" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  let j; try{ j=JSON.parse(s) }catch(e){ return console.log("?\t?\t?\t?\t?") }
  // 要的是「最後一次發版」，不是 time.modified。後者連改個 dist-tag、改個 README
  // 都會往前跳：express-rate-limiter 的 latest 發於 2015-11，time.modified 是 2022-06。
  // 拿 modified 當停更判準，會讓一個十年沒動的套件看起來像去年還在維護。
  const lat=(j["dist-tags"]||{}).latest;
  const t=(lat&&j.time&&j.time[lat])?j.time[lat].slice(0,7):"?";
  const age=(t==="?")?"?":Math.floor((Date.now()-Date.parse(t+"-01T00:00:00Z"))/2629800000);
  console.log([t,Object.keys(j.versions||{}).length,(j.maintainers||[]).length,
               (j.repository&&j.repository.url)?"有":"無",age].join("\t"));
})' 2>/dev/null)
  IFS=$'\t' read -r lastpub nver nmaint repo age <<< "${fields:-?	?	?	?	?}"

  dlresp=$(fetch "${DL}/${enc}")
  dl=$(printf '%s' "${dlresp#*	}" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const n=JSON.parse(s).downloads;console.log(Number.isInteger(n)?n:"?")}catch(e){console.log("?")}})' 2>/dev/null)
  [ "${dlresp%%	*}" = "200" ] || dl="?"
  dl=${dl:-?}

  printf '查到 %10s %9s %5s %5s   %s   %s\n' "${dl}" "${lastpub}" "${nver}" "${nmaint}" "${repo}" "${p}"

  # 註記：這幾條都不是「不安全」的判定，是「你自己去看一眼」的理由
  w=""
  [ "${age}" != "?" ] && [ "${age}" -ge 24 ] 2>/dev/null && w="${w}停更超過兩年（最後發版 ${lastpub}）；"
  [ "${nver}" != "?" ] && [ "${nver}" -lt 5 ] 2>/dev/null && w="${w}只發過 ${nver} 個版本；"
  [ "${repo}" = "無" ] && w="${w}沒填原始碼位置，你看不到它做了什麼；"
  [ "${dl}" != "?" ] && [ "${dl}" -lt 100 ] 2>/dev/null && w="${w}上週只有 ${dl} 次下載；"
  [ -n "${w}" ] && NOTES="${NOTES}${p}｜${w}
"
done

if [ -n "${NOTES}" ]; then
  printf '\n── 要你自己看一眼的 ──\n%s' "${NOTES}"
  printf '這幾條都不代表不安全，只代表沒有人在幫你看。要不要裝是你的決定。\n'
fi
