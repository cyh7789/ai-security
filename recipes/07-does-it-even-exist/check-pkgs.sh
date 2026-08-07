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

# 週下載那一欄靠右對齊到 10 個顯示欄位。
# 不能直接用 printf 的 %10s：它按字元數補，而「錯誤」「關」是全形、一個字佔兩欄，
# 補出來會比數字那幾列短，整張表就歪掉（8/07 量到 16／17／18 三種起始位置）。
# 這一欄的非數字值只有兩個，所以直接寫死補幾格，不去算寬度：
# 算寬度那版第一次就寫錯了（`[!-~]` 在 shell 裡是否定不是範圍），而它錯了也還是印得出東西。
dlcell() {
  case "$1" in
    關)   printf '        關' ;;   # 2 個顯示欄位，補 8 格
    錯誤) printf '      錯誤' ;;   # 4 個顯示欄位，補 6 格
    *)    printf '%10s' "$1" ;;
  esac
}

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

# 下載數住在另一台主機（api.npmjs.org），上面兩個對照碰不到它。
# 那台掛掉的時候週下載欄會印「?」，而「停更了還有人在下載」整個判斷站在這一欄上。
# 「問不到」又一次長得像「沒人下載」，只是這次換一台主機。
#
# 但這裡不停下來。這篇要回答的是「這個名字存不存在」，那隻靠註冊處那台就夠了；
# 下載數是次要欄位，讓它綁架主功能等於公司代理只放行註冊處的人整支不能用，
# 而他本來拿得到最重要的那個答案。
# 病灶是靜默不是缺硬停，所以改成大聲降級：那一欄印「錯誤」，收尾明講問不到。
DL_STATE=ok
if [ "${DL}" = "off" ]; then
  DL_STATE=off
else
  CTRL_DL=$(fetch "${DL}/express" | cut -f1)
  [ "${CTRL_DL}" = "200" ] || DL_STATE=down
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
# 週下載欄有兩種「不是數字」的狀態，兩種要分得開：
#   關＝你自己用 NPM_DOWNLOADS=off 關掉的   錯誤＝那台問不到，不是沒人下載
case "${DL_STATE}" in
  off)  printf '下載數這欄你關掉了（NPM_DOWNLOADS=off），不查 %s，那一欄印「關」。\n' "api.npmjs.org" ;;
  down) printf '下載數那台問不到（%s/express 回 %s），那一欄印「錯誤」。\n' "${DL}" "${CTRL_DL}"
        printf '「錯誤」不是「沒人下載」，是我沒問到。名字在不在照樣查得準，那台不影響。\n' ;;
esac
printf '判定     週下載  最後發布  版本 維護者 原始碼  套件\n'
NOTES=""
DL_MISSING=""
for p in "${names[@]}"; do
  # AI 給你的那行通常是 `npm install express@4.19.2`，所以名字後面常常黏著版本號。
  # 不切的話註冊處回 404，這支就會把一個真的存在的套件講成「AI 掰的」，那是這份最不想要的答案。
  # 切掉之後一定要講，因為那等於把你問的問題改掉了：查的是名字在不在，不是那一版在不在。
  # scoped 套件開頭那個 @ 不能誤切，所以只認「第一個字元之後」的 @
  ver=""
  case "${p}" in
    @*/*@*) ver=${p##*@}; p=${p%@*} ;;   # @scope/name@1.2.3
    @*)     ;;                            # @scope/name，開頭的 @ 不是版本分隔
    *@*)    ver=${p##*@}; p=${p%@*} ;;   # name@1.2.3
  esac
  [ -n "${ver}" ] && NOTES="${NOTES}${p}｜你給的是 ${p}@${ver}，我查的是名字 ${p} 在不在，版本 ${ver} 沒查。
"
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

  case "${DL_STATE}" in
    off)  dl=關 ;;
    down) dl=錯誤 ;;   # 兩個字，跟判定欄的「查到／沒有／錯誤」同一套詞彙
    *)
      dlresp=$(fetch "${DL}/${enc}")
      dl=$(printf '%s' "${dlresp#*	}" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const n=JSON.parse(s).downloads;console.log(Number.isInteger(n)?n:"?")}catch(e){console.log("?")}})' 2>/dev/null)
      # 整台好好的但這一顆問不到（單顆 404、暫時性錯誤）也算問不到，不能印成 0
      [ "${dlresp%%	*}" = "200" ] && [ -n "${dl}" ] && [ "${dl}" != "?" ] || dl=錯誤 ;;
  esac

  printf '查到 %s %9s %5s %5s   %s   %s\n' "$(dlcell "${dl}")" "${lastpub}" "${nver}" "${nmaint}" "${repo}" "${p}"

  # 註記：這幾條都不是「不安全」的判定，是「你自己去看一眼」的理由
  w=""
  [ "${age}" != "?" ] && [ "${age}" -ge 24 ] 2>/dev/null && w="${w}停更超過兩年（最後發版 ${lastpub}）；"
  [ "${nver}" != "?" ] && [ "${nver}" -lt 5 ] 2>/dev/null && w="${w}只發過 ${nver} 個版本；"
  [ "${repo}" = "無" ] && w="${w}沒填原始碼位置，你看不到它做了什麼；"
  case "${dl}" in
    ''|關|錯誤) DL_MISSING="${DL_MISSING}${p} " ;;
    *) [ "${dl}" -lt 100 ] 2>/dev/null && w="${w}上週只有 ${dl} 次下載；" ;;
  esac
  [ -n "${w}" ] && NOTES="${NOTES}${p}｜${w}
"
done

if [ -n "${NOTES}" ]; then
  printf '\n── 要你自己看一眼的 ──\n%s' "${NOTES}"
  printf '這幾條都不代表不安全，只代表沒有人在幫你看。要不要裝是你的決定。\n'
fi

# 少了下載數，「上週只有 N 次下載」那條提醒就不會出現。
# 不講的話畫面看起來像「這幾個沒問題」，那是靜默的另一種形態：
# 檢查沒跑跟檢查跑完沒事，在畫面上必須長得不一樣。
if [ -n "${DL_MISSING}" ]; then
  case "${DL_STATE}" in
    off)  why="你自己關掉了下載數（NPM_DOWNLOADS=off）" ;;
    down) why="下載數那台問不到" ;;
    *)    why="這幾顆的下載數沒問到" ;;
  esac
  printf '\n── 這一項我沒幫你看 ──\n%s，所以「下載數低不低」這條沒跑：\n  %s\n' \
    "${why}" "${DL_MISSING% }"
  printf '那不代表它們的下載數沒問題，是這一項根本沒檢查。\n'
fi
