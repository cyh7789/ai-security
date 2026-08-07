#!/usr/bin/env bash
# 驗這個 recipe 的每一句話。
#
#   bash verify.sh      全部
#   bash verify.sh 3    只跑第 3 節
#
# 設計原則跟 recipe 06 同一條：每一個「找不到」都要有配對的「找得到」。
# 「查不到那個套件」在畫面上跟「網路斷了」長得一樣，所以第 1 節先證明這支腳本
# 分得出這兩者，第 2 節之後的判定才有意義。

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ONLY="${1:-}"
PASS=0; FAIL=0; SKIP=0

ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  [SKIP] %s\n' "$1"; SKIP=$((SKIP+1)); }
sect() { printf '\n── %s ──\n' "$1"; }
want() { [ -z "${ONLY}" ] || [ "${ONLY}" = "$1" ]; }

# 節號打錯的話，下面每一節都不跑，收尾算出 0 綠 0 紅 0 跳過然後離開碼 0。
# 一份講假綠燈的東西，最不能留的就是這種形狀。
case "${ONLY}" in
  ''|1|2|3|4|5) ;;
  *) printf '沒有第 %s 節。可用的是 1 到 5，或不給參數跑全部。\n' "${ONLY}"; exit 2 ;;
esac

RANDNAME="npm-registry-probe-$$-$(date +%s)-zzq"
WS=$(mktemp -d)

# 假主機的 pid 一律登記在 ${WS}/pids，由這裡統一收。
# kill 寫在「起得來」那條分支裡是不夠的：起不來或斷言紅了就走另一條路，
# 那支 node 已經 disown，trap 只刪目錄不管行程，慢機器上會在讀者機器留一支還在聽的。
cleanup() {
  if [ -f "${WS}/pids" ]; then
    while read -r p; do [ -n "${p}" ] && kill "${p}" 2>/dev/null; done < "${WS}/pids"
  fi
  rm -rf "${WS}"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

# 假的下載數主機。有幾種回答是真的 api.npmjs.org 不會給你的，只能自己起一台。
#   ok   照實回答，數字問得到，當其他幾輪的基準線
#   one  對照那顆答得出來，其他每一顆 500（整台好好的、只有這一顆問不到）
#   yes  對任何名字都回 200 加一個數字，連不存在的名字也是（反向對照要抓的就是這種）
#   neg  對照那顆正常，其他回負數
#   junk 整台回 200，但給的是一頁 HTML 不是數字（代理插隊的樣子）
# ok、one、neg 對不存在的名字回 404，才過得了反向對照。不然驗到的會是另一條路。
# 數字寫死在這裡，這幾輪的結果才不會隨著真的 api.npmjs.org 浮動。
dlhost() {   # dlhost <mode> → 印出 port，起不來就印空的
  local mode="$1" f="${WS}/dlhost.$1" i=0
  node -e '
const http=require("http"), mode=process.argv[1];
const known={"/express":1234,"/express-rate-limiter":1863};
const s=http.createServer((q,r)=>{
  const j=n=>{ r.writeHead(200,{"content-type":"application/json"}); r.end(JSON.stringify({downloads:n})) };
  if (mode==="yes") return j(0);
  if (mode==="junk") { r.writeHead(200,{"content-type":"text/html"}); return r.end("<html><body>proxy sign-in</body></html>") }
  if (!(q.url in known)) { r.writeHead(404); return r.end(JSON.stringify({error:"not found"})) }
  if (q.url==="/express") return j(known[q.url]);
  if (mode==="ok")  return j(known[q.url]);
  if (mode==="neg") return j(-7);
  r.writeHead(500); r.end("nope");
});
s.listen(0,"127.0.0.1",()=>process.stdout.write(String(s.address().port)));' "${mode}" > "${f}" 2>/dev/null &
  echo $! >> "${WS}/pids"
  disown 2>/dev/null || true
  # sleep 0.1 不是 POSIX。沒有小數秒的 sleep 時 50 圈會瞬間跑完，
  # 明明起得來也會被判成起不來，所以退回整秒再等。
  while [ ! -s "${f}" ] && [ "${i}" -lt 50 ]; do sleep 0.1 2>/dev/null || sleep 1; i=$((i+1)); done
  cat "${f}" 2>/dev/null
}

# 「這台機器沒裝那個工具」跟「工具在、註冊處沒回應」要分開報：前者是這一節不適用，
# 後者是要驗的東西壞了。折成同一個旗標的話，沒裝 node 的機器會看到滿畫面紅燈。
miss() { local m=""; for t in "$@"; do command -v "${t}" >/dev/null 2>&1 || m="${m}${m:+、}${t}"; done; printf '%s' "${m}"; }

# check-pkgs.sh 的輸出是「說明、表格、收尾」三段。收尾有沒有出聲，靠的是位置，
# 不是收尾那句話長什麼樣，所以這裡把表格之後的部分切出來給下面比差集用。
after_table() { awk '/^(判定|查到|沒有|錯誤)[[:space:]]/ { seen=1; next } seen && $0 !~ /^[[:space:]]*$/' "$1"; }

# 把一輪輸出裡的說明拆成句子，表格那幾列不算。
# 逐行比不夠力：同一句話搬到另一種處境底下重用，只要順手接一句別的話，
# 整行就不相等了，逐行比會回報「這兩種分得開」，而讀者看到的是同一句。
sentences() {
  grep -vE '^(判定|查到|沒有|錯誤)[[:space:]]' "$1" \
    | awk '{ gsub(/。/, "\n"); print }' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort -u
}

HAVE_NET=0
if [ -z "$(miss curl)" ]; then
  [ "$(curl -s -o /dev/null -w '%{http_code}' -m 20 https://registry.npmjs.org/express 2>/dev/null)" = "200" ] && HAVE_NET=1
fi

# 下載數住在 api.npmjs.org，跟註冊處是不同主機，而且它會限流。
# check-pkgs.sh 對那台的處理是大聲降級不是停下來，所以這支不會因為它掛掉而整片紅。
# 這個探針只決定一件事：現在量得到真的下載數字嗎。
# 量得到，第 3 節那個「停更了還有人下載」才有東西可比；量不到就只有那一節跳過。
# 降級路徑本身不需要這個探針，它自己把 NPM_DOWNLOADS 指到黑洞來造情境。
HAVE_DL=0
if [ -z "$(miss curl)" ]; then
  [ "$(curl -s -o /dev/null -w '%{http_code}' -m 20 https://api.npmjs.org/downloads/point/last-week/express 2>/dev/null)" = "200" ] && HAVE_DL=1
fi

# ── 1 ────────────────────────────────────────────────────
if want 1; then
sect "1 這支腳本分得出「註冊處說沒有」跟「我沒問到註冊處」"

  # 這條不需要網路也不需要那兩個工具在：把 PATH 清空，check-pkgs.sh 該當場停下來。
  # 缺工具的機器下面整節會跳過，所以那條守衛只剩這裡在驗。
  out=$(PATH=/nonexistent-dir "${BASH:-/bin/bash}" "${HERE}/check-pkgs.sh" express 2>&1); rc=$?
  if [ "${rc}" = 2 ] && printf '%s' "${out}" | grep -q '這支跑不了'; then
    ok "工具不在的時候 check-pkgs.sh 直接停下來（exit 2），不會硬跑出一個答案"
  else
    bad "工具不在卻沒停（rc=${rc}）：${out}"
  fi

  M=$(miss curl node)
  if [ -n "${M}" ]; then
    skip "沒裝 ${M}，check-pkgs.sh 本身跑不起來，這一節整節不適用"
  elif [ "${HAVE_NET}" = 0 ]; then
    skip "curl 在，但問不到 registry.npmjs.org，這一節本身需要網路"
  else
    out=$(NPM_DOWNLOADS=off bash "${HERE}/check-pkgs.sh" express 2>&1); rc=$?
    if [ "${rc}" = 0 ] && printf '%s' "${out}" | grep -q '^查到.*express$'; then
      ok "正向對照：express 查得到"
    else
      bad "正向對照掛了（rc=${rc}）：${out}"
    fi

    out=$(NPM_DOWNLOADS=off bash "${HERE}/check-pkgs.sh" "${RANDNAME}" 2>&1); rc=$?
    if [ "${rc}" = 0 ] && printf '%s' "${out}" | grep -q "^沒有.*${RANDNAME}$"; then
      ok "反向對照：一個不可能有人註冊的名字，判定是「沒有」"
    else
      bad "反向對照掛了（rc=${rc}）：${out}"
    fi
  fi

  # 這兩條不需要網路，而且是這一節真正的重點。但還是需要那兩個工具：
  # 沒有它們的話 check-pkgs.sh 是死在「工具不在」，不是死在「問不到註冊處」，驗不到東西。
  if [ -n "${M}" ]; then
    skip "沒裝 ${M}，「連不到就停下來」這兩條驗不了"
  else
    out=$(NPM_REGISTRY=https://127.0.0.1:9 NPM_DOWNLOADS=https://127.0.0.1:9 \
          bash "${HERE}/check-pkgs.sh" express 2>&1); rc=$?
    if [ "${rc}" = 2 ] && printf '%s' "${out}" | grep -q '對照組沒過'; then
      ok "註冊處連不到的時候直接停下來（exit 2），不會把 express 講成不存在"
    else
      bad "註冊處連不到卻沒停（rc=${rc}）：${out}"
    fi
    if printf '%s' "${out}" | grep -q '^沒有'; then
      bad "註冊處連不到，卻印出了「沒有」的判定，這是假答案"
    else
      ok "連不到的那一輪沒有印出任何「沒有」"
    fi

    # ── 下載欄的每一種處境 ──────────────────────────────
    # 下載數住在另一台主機。註冊處好好的、只有那台出事的時候，週下載欄會失去意義，
    # 而「停更了還有人在下載」整個判斷站在那一欄上。對照組要蓋到兩台，
    # 不然「問不到」在那一欄上又長得像「沒人下載」。
    #
    # 這幾條需要網路：要造出「註冊處通、只有下載那台有問題」，前一半得是真的。
    # 整台機器都不通的時候註冊處那個對照會先擋下來，訊息是註冊處那句，
    # 這裡就會變成一顆假紅燈（實測撞到）。
    #
    # 每一種處境各跑一輪，都查同一顆套件，存成檔案，這樣兩輪的差別就只剩處境本身。
    # 下面的檢查比的是這幾份輸出彼此的差集，不比對任何一句寫死的話：
    #   good  那台正常，數字問得到，當其他幾輪的基準線
    #   off   你自己用 NPM_DOWNLOADS=off 關掉
    #   down  整台連不到
    #   junk  整台回 200，但給的是一頁 HTML 不是數字
    #   bogus 那台連不存在的名字都回 200，它給的數字是編的
    #   one   對照過了，只有這一顆問不到
    #   neg   對照過了，這一顆回一個負數
    if [ "${HAVE_NET}" = 0 ]; then
      skip "問不到註冊處，造不出「註冊處通、只有下載那台有問題」這幾種處境"
    elif [ -n "$(miss node)" ]; then
      skip "沒裝 node，起不了假的下載主機，下載欄那幾種處境驗不到"
    else
      DLPKG=express-rate-limiter
      P_OK=$(dlhost ok);   P_ONE=$(dlhost one); P_YES=$(dlhost yes)
      P_NEG=$(dlhost neg); P_JUNK=$(dlhost junk)
      if [ -z "${P_OK}" ] || [ -z "${P_ONE}" ] || [ -z "${P_YES}" ] \
         || [ -z "${P_NEG}" ] || [ -z "${P_JUNK}" ]; then
        bad "起不了假的下載主機（ok=${P_OK} one=${P_ONE} yes=${P_YES} neg=${P_NEG} junk=${P_JUNK}），下載欄那幾種處境沒驗到"
      else
        for spec in "good=http://127.0.0.1:${P_OK}" "off=off" "down=https://127.0.0.1:9" \
                    "junk=http://127.0.0.1:${P_JUNK}" "bogus=http://127.0.0.1:${P_YES}" \
                    "one=http://127.0.0.1:${P_ONE}" "neg=http://127.0.0.1:${P_NEG}"; do
          st=${spec%%=*}
          NPM_DOWNLOADS="${spec#*=}" bash "${HERE}/check-pkgs.sh" "${DLPKG}" > "${WS}/s.${st}" 2>&1
          printf '%s' "$?" > "${WS}/rc.${st}"
        done

        # 一、次要欄位不准綁架主功能。公司只把註冊處放進白名單的話，
        # 連「這個名字在不在」都問不到就太過頭，逃生口要真的能走。
        n=0
        for st in good off down junk bogus one neg; do
          [ "$(cat "${WS}/rc.${st}")" = 0 ] \
            || { bad "「${st}」那一輪只是下載欄出事，整支卻跟著失敗，rc=$(cat "${WS}/rc.${st}")"; n=1; }
          grep -q "^查到.*${DLPKG}$" "${WS}/s.${st}" \
            || { bad "「${st}」那一輪連名字都查不到了：$(head -3 "${WS}/s.${st}" | tr '\n' ' ')"; n=1; }
        done
        [ "${n}" = 0 ] && ok "下載欄七種處境下名字照樣查得到、離開碼都是 0"

        # 二、那一格要看得出是哪一種，不是 0、不是空白、不是一個問號帶過
        n=0
        grep -qE '^查到 +[0-9]+ ' "${WS}/s.good" \
          || { bad "那台正常的時候週下載欄沒印出數字：$(grep '^查到' "${WS}/s.good")"; n=1; }
        grep -qE '^查到 +關 ' "${WS}/s.off" \
          || { bad "關掉之後那一格沒印成「關」：$(grep '^查到' "${WS}/s.off")"; n=1; }
        for st in down junk bogus one neg; do
          grep -qE '^查到 +錯誤 ' "${WS}/s.${st}" \
            || { bad "「${st}」那一輪的週下載欄沒印成「錯誤」，那一格會被讀成真的量到的數字：$(grep '^查到' "${WS}/s.${st}")"; n=1; }
        done
        grep '^查到' "${WS}/s.neg" | grep -q -- '-7' \
          && { bad "那台回一個負的下載數，這支照樣把它印出來了：$(grep '^查到' "${WS}/s.neg")"; n=1; }
        [ "${n}" = 0 ] && ok "週下載欄：問到印數字、你關的印「關」，其餘五種（整台連不到／整台回垃圾／那台亂答／單顆問不到／負數）都印「錯誤」"

        # 三、檢查沒跑跟檢查跑完沒事，畫面上必須長得不一樣。
        # 這條不比對任何一句話，比的是位置：表格印完之後，沒量到的那幾輪要還有話講，
        # 而且是「那台正常」那一輪沒有的話。收尾整段被拿掉就會紅，因為那幾輪的說明
        # 全在表格之前，表格之後剩下的會跟量得到的那輪一模一樣。
        after_table "${WS}/s.good" > "${WS}/tail.good"
        n=0
        for st in off down junk bogus one neg; do
          after_table "${WS}/s.${st}" | grep -vxF -f "${WS}/tail.good" > "${WS}/tail.${st}"
          [ -s "${WS}/tail.${st}" ] \
            || { bad "「${st}」那一輪沒量到下載數，「下載數低不低」那條就沒跑，而表格之後印的東西跟量到的那輪一模一樣。這是靜默的另一種形態"; n=1; }
        done
        [ "${n}" = 0 ] && ok "沒量到下載數的那幾輪，表格之後都多出一段「這一項沒檢查」，跟量到的那輪長得不一樣"

        # 四、「你自己關的」「整台連不到」「那台亂答」「只有這一顆問不到」是四種處境，
        # 讀者要分得出自己在哪一種。這裡比的是四輪輸出的差集：
        # 四輪都印的行不帶處境資訊（表頭、區塊標題、收尾那句通則），先扣掉；
        # 剩下的就是每一種專屬的說明。哪一種沒有專屬的話，或者兩種撞在一起，
        # 都代表它們在畫面上分不開。
        # 寫死一句話去比對的版本兩個方向都會壞：只改措辭會假紅，
        # 用新措辭把 bug 原封不動種回去會假綠（兩個方向都實測到過）。
        # 表格那幾列不算：這幾輪的那一列除了下載欄以外一模一樣，分辨靠的是文字。
        # neg 不進這一組：它跟 one 都是「對照過了、這一顆沒量到」，共用同一句是對的。
        for st in off down bogus one junk; do sentences "${WS}/s.${st}" > "${WS}/all.${st}"; done
        grep -xF -f "${WS}/all.off" "${WS}/all.down" | grep -xF -f "${WS}/all.bogus" \
          | grep -xF -f "${WS}/all.one" > "${WS}/core"
        for st in off down bogus one; do
          grep -vxF -f "${WS}/core" "${WS}/all.${st}" > "${WS}/sig.${st}"
        done
        n=0
        for st in off down bogus one; do
          [ -s "${WS}/sig.${st}" ] \
            || { bad "「${st}」這一輪沒有一句話是它專屬的，讀者看不出自己碰到的是哪一種"; n=1; }
        done
        for pair in off:down off:bogus off:one down:bogus down:one bogus:one; do
          dup=$(grep -xF -f "${WS}/sig.${pair%%:*}" "${WS}/sig.${pair##*:}" | head -2)
          [ -z "${dup}" ] && continue
          bad "「${pair%%:*}」跟「${pair##*:}」講了同一句話，兩種處境分不開：${dup}"; n=1
        done
        [ "${n}" = 0 ] && ok "下載欄四種處境（你關的／整台連不到／那台亂答／只有這一顆問不到）各講各的話，沒有一句重疊"

        # 五、整台回 200 但給的不是數字（代理塞一頁 HTML）的時候，對照如果只看
        # HTTP 狀態碼就會過，收尾就走到逐顆點名那一條，把讀者導向去查個別套件，
        # 而實際壞掉的是整台。這條要求它講整台那一組話，不是單顆那一組。
        # 一樣不比對寫死的句子，比的是它用了誰的專屬說明。
        n=0
        grep -qxF -f "${WS}/sig.down" "${WS}/all.junk" \
          || { bad "那台整台回 200 但給的不是數字，這一輪卻沒講出「整台有問題」那一組話"; n=1; }
        hit=$(grep -xF -f "${WS}/sig.one" "${WS}/all.junk" | head -1)
        [ -z "${hit}" ] \
          || { bad "整台回的都是垃圾，收尾卻只點名個別套件，讀者會被導去查錯的東西：${hit}"; n=1; }
        [ "${n}" = 0 ] && ok "整台回 200 但給的不是數字時，講的是「整台有問題」，不是逐顆點名"

        # 六、dlcell 跟 repocell 補幾格是寫死的（全形字佔兩個顯示欄位，printf 的
        # %10s 按字元數補，會讓「錯誤」那幾列短兩欄）。沒有東西在看的話，補錯了
        # 照樣印得出一張表，只是歪的。這條量顯示寬度，不看補了幾個空白字元。
        NPM_DOWNLOADS=off bash "${HERE}/check-pkgs.sh" express "${RANDNAME}" > "${WS}/s.rows" 2>&1
        cat "${WS}/s.good" "${WS}/s.down" "${WS}/s.rows" \
          | grep -E '^(判定|查到|沒有|錯誤)[[:space:]]' | sort -u > "${WS}/rows"
        wid=$(node -e '
const rows=require("fs").readFileSync(process.argv[1],"utf8").split("\n").filter(s=>s.length);
// 這張表用到的全形字只有 CJK 跟全形符號，認這幾段就夠
const wide=/[\u1100-\u115F\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE6F\uFF00-\uFF60\uFFE0-\uFFE6]/;
const w=s=>Array.from(s).reduce((a,c)=>a+(wide.test(c)?2:1),0);
const edge=re=>{const set={};for(const r of rows){const m=r.match(re);if(m)set[w(m[1])]=1}return Object.keys(set)};
const dl=edge(/^(\S+\s+\S+)/), pkg=edge(/^(.*\s)\S+$/);
console.log((dl.length===1&&pkg.length===1?"齊":"歪")+" "+rows.length+" 列，週下載欄右緣 "+dl.join("/")+"，套件欄左緣 "+pkg.join("/"));
' "${WS}/rows")
        if [ "${wid%% *}" = "齊" ]; then
          ok "表格每一列的欄位落點都對得上（${wid#* }）"
        else
          bad "表格歪了，各列的欄位落點對不上（${wid#* }）"
        fi
      fi
    fi
  fi
fi

# ── 2 ────────────────────────────────────────────────────
if want 2; then
sect "2 三種輸入方式（參數、檔案、剪貼簿）給同一個答案"

  M=$(miss curl node)
  if [ -n "${M}" ]; then
    skip "沒裝 ${M}，check-pkgs.sh 本身跑不起來"
  elif [ "${HAVE_NET}" = 0 ]; then
    skip "curl 在，但問不到註冊處"
  else
    TD=$(mktemp -d)
    printf 'express\n# 這行是註解\n\n%s\n' "${RANDNAME}" > "${TD}/pkgs.txt"
    # 這一節比的是「三條輸入路徑解析出同一批名字」，跟下載數無關。
    # 不關掉的話 api.npmjs.org 一限流，三次呼叫裡有的拿到數字有的拿到「錯誤」，
    # 三邊就不一致了，紅燈指向輸入解析，真正的原因卻是那台在擋（8/07 實測撞到）。
    a=$(NPM_DOWNLOADS=off bash "${HERE}/check-pkgs.sh" express "${RANDNAME}" 2>&1 | grep -E '^(查到|沒有|錯誤)')
    b=$(NPM_DOWNLOADS=off bash "${HERE}/check-pkgs.sh" -f "${TD}/pkgs.txt" 2>&1 | grep -E '^(查到|沒有|錯誤)')
    c=$(printf 'express\n%s\n' "${RANDNAME}" | NPM_DOWNLOADS=off bash "${HERE}/check-pkgs.sh" - 2>&1 | grep -E '^(查到|沒有|錯誤)')
    rm -rf "${TD}"
    # 「三邊一致」單獨拿來當判準是假的：三邊都吐空字串也是一致。
    # 所以先要求它真的查了兩個套件，再比一致性。
    n=$(printf '%s\n' "${a}" | grep -c .)
    if [ "${n}" != 2 ]; then
      bad "參數路徑該查兩個套件，實際 ${n} 行：${a}"
    elif [ "${a}" = "${b}" ] && [ "${b}" = "${c}" ]; then
      ok "三條路徑各查到兩個套件而且答案一致，註解行與空行被吃掉了"
    else
      bad "三條路徑不一致：
參數：${a}
檔案：${b}
剪貼簿：${c}"
    fi

    # AI 給的那行是 `npm install express@4.19.2`，讀者會整包貼進來。
    # 不切版本號的話註冊處回 404，這支就把一個真的存在的套件講成 AI 掰的。
    out=$(NPM_DOWNLOADS=off bash "${HERE}/check-pkgs.sh" 'express@4.19.2' 2>&1)
    if printf '%s' "${out}" | grep -q '^查到.*express$'; then
      printf '%s' "${out}" | grep -q '版本 4.19.2 沒查' \
        && ok "名字後面黏著版本號照樣查得到，而且有講版本沒查" \
        || bad "版本號被切掉了卻沒告訴讀者。切掉等於改了他問的問題"
    else
      bad "express@4.19.2 沒被判成「查到」，版本號沒切：${out}"
    fi
    # scoped 套件開頭那個 @ 不是版本分隔，誤切的話會去查一個不存在的名字
    out=$(NPM_DOWNLOADS=off bash "${HERE}/check-pkgs.sh" '@anatine/zod-openapi' 2>&1)
    if printf '%s' "${out}" | grep -q '^查到.*@anatine/zod-openapi$'; then
      printf '%s' "${out}" | grep -q '沒查' \
        && bad "scoped 套件開頭的 @ 被當成版本分隔了" \
        || ok "scoped 套件開頭的 @ 沒被誤切"
    else
      bad "@anatine/zod-openapi 查不到，開頭的 @ 大概被切掉了：${out}"
    fi
  fi
fi

# ── 3 ────────────────────────────────────────────────────
if want 3; then
sect "3 停更的套件還是有人在下載，所以下載數不是活著的證明"

  M=$(miss curl node)
  if [ -n "${M}" ]; then
    skip "沒裝 ${M}，check-pkgs.sh 本身跑不起來"
  elif [ "${HAVE_NET}" = 0 ]; then
    skip "curl 在，但問不到註冊處"
  elif [ "${HAVE_DL}" = 0 ]; then
    skip "問不到 api.npmjs.org（擋掉或 429），這一節要比的是真的下載數字，沒有數字就沒得比"
  else
    # express-rate-limiter 是真的存在、2022 年後就沒動過的套件。
    # 這裡不主張它有惡意，主張的只有一件事：它的下載數不為零。
    line=$(bash "${HERE}/check-pkgs.sh" express-rate-limiter 2>&1 | grep 'express-rate-limiter$' | head -1)
    dl=$(printf '%s' "${line}" | awk '{print $2}')
    mod=$(printf '%s' "${line}" | awk '{print $3}')
    if [ -z "${dl}" ] || [ -z "${mod}" ]; then
      bad "抓不到那一行：${line}"
    elif [ "${dl}" = "錯誤" ] || [ "${dl}" = "關" ]; then
      # 開頭那個 HAVE_DL 探針是跑之前量的，而 api.npmjs.org 會限流：
      # 跑到這一節的時候它可能已經開始擋了（mutations.sh 一輪打它上百次，實測撞到）。
      # 這一格印「錯誤」的意思是沒問到，不是資料有問題。
      # 把沒問到判成紅燈，就是這一份從第一節開始在反對的那個混淆。
      skip "下載數這一格是「${dl}」，沒問到就沒得比。這不是紅燈，是這一輪沒驗到"
    elif ! printf '%s' "${dl}" | grep -qE '^[0-9]+$'; then
      bad "下載數不是數字也不是「錯誤／關」（${dl}），這一節沒驗到東西：${line}"
    elif [ "${mod}" \< "2024-08" ] && [ "${dl}" -gt 0 ]; then
      ok "最後發布 ${mod}，上週仍有 ${dl} 次下載"
    else
      bad "前提變了：最後發布 ${mod}、下載 ${dl}。文章那段要重寫"
    fi
  fi
fi

# ── 4 ────────────────────────────────────────────────────
if want 4; then
sect "4 差一個 ^ 符號，npm audit 的答案不一樣"

  M=$(miss npm node)
  if [ -n "${M}" ]; then
    skip "沒裝 ${M}，lockfile-demo.sh 用 npm 解相依、用 node 讀 lockfile"
  elif [ -n "$(miss curl)" ]; then
    skip "沒裝 curl，量不出註冊處通不通，這一節的結果不算數"
  elif [ "${HAVE_NET}" = 0 ]; then
    skip "curl 在，但問不到註冊處"
  else
    out=$(bash "${HERE}/lockfile-demo.sh" 2>&1)
    f=$(printf '%s' "${out}" | grep '\^4.19.2' | sed 's/.*弱點 \([0-9]*\) 則.*/\1/')
    p=$(printf '%s' "${out}" | grep '"4.19.2 ' | sed 's/.*弱點 \([0-9]*\) 則.*/\1/')
    if ! printf '%s' "${f}${p}" | grep -qE '^[0-9]+$'; then
      bad "兩邊的弱點數抓不到，demo 大概沒跑起來：
${out}"
    elif [ "${p}" -gt "${f}" ]; then
      ok "浮動 ^4.19.2 是 ${f} 則，釘死 4.19.2 是 ${p} 則"
    else
      bad "釘死那邊 ${p} 則沒有多於浮動那邊 ${f} 則。上游可能改了，文章那段要重算"
    fi
    n=$(printf '%s' "${out}" | grep '\^4.19.2' | sed 's/.*lockfile 裡 \([0-9]*\) 個套件.*/\1/')
    if printf '%s' "${n}" | grep -qE '^[0-9]+$' && [ "${n}" -gt 1 ]; then
      ok "宣告 1 個相依，lockfile 裡有 ${n} 個套件"
    else
      bad "套件數抓不到或不大於 1：${n}"
    fi
  fi

  # 對照跑不出來的時候，它要停而不是照樣印那段「看兩件事」的解說。
  # 這一條不需要網路（就是要它連不到），所以上面全部 skip 的機器上它照樣驗得到。
  # 沒有這條的話，那個守衛不會被任何檢查看到。這一份自己說過，不會紅的檢查沒有價值。
  # node 也要在：npm 自己就是一支 node 程式，node 不在的時候連 npm 都起不來，
  # 端出來的原因會是 `env: node: No such file or directory` 而不是 npm 的錯誤碼。
  # 那不是這條要驗的東西，跳過而不是紅（缺工具不該讓這一份印紅燈）
  M=$(miss npm node)
  if [ -n "${M}" ]; then
    skip "沒裝 ${M}，驗不到 lockfile-demo.sh 跑不出對照時會不會停"
  else
    # port 9 是 discard，定義上是「收下連線然後什麼都不回」。這台沒有人聽所以會
    # ECONNREFUSED，但別人的機器上真的有 inetd discard 開著的話會變成等逾時，
    # 而 fetch-timeout 預設 300 秒、這支跑兩次 → 最久卡十分鐘。逾時一起壓短。
    # 光給 FETCH_RETRIES=0 擋不到這個，那隻管重試次數不管單次等多久。
    # mintimeout 預設 10000，只壓 maxtimeout 會變成 minTimeout > maxTimeout，
    # npm 直接吐設定錯誤而不是連線錯誤，這條檢查就永遠紅，而且紅的理由是我的旗標，
    # 不是被測的東西。兩個一起給。
    out=$(NPM_CONFIG_REGISTRY=http://127.0.0.1:9 NPM_CONFIG_FETCH_RETRIES=0 \
          NPM_CONFIG_FETCH_TIMEOUT=5000 \
          NPM_CONFIG_FETCH_RETRY_MINTIMEOUT=1000 NPM_CONFIG_FETCH_RETRY_MAXTIMEOUT=5000 \
          bash "${HERE}/lockfile-demo.sh" 2>&1); rc=$?
    if [ "${rc}" = 0 ]; then
      bad "註冊處連不到，lockfile-demo.sh 卻回 0。它會照樣印解說，讀者以為看過對照了"
    elif [ "${rc}" != 2 ]; then
      # README 對外寫的是「離開碼一律是 2」，只判非零的話改成 exit 1 也不會紅
      bad "停下來了但離開碼是 ${rc}，README 寫的是 2"
    elif printf '%s' "${out}" | grep -q '看兩件事'; then
      bad "停下來了，但還是印了「看兩件事」那段解說，上面卻沒有東西可看"
    # npm 11 印 `npm error`，npm 9（Node 18 那條線的出廠版）印 `npm ERR!`，兩個都認。
    # 而且要咬到 code 那一行：光有 `npm error` 三個字，罐頭的「你是不是在代理後面」
    # 也算數，那正好是這條檢查最需要擋掉的東西
    elif printf '%s' "${out}" | grep -qE 'npm (error|ERR!) code'; then
      ok "對照跑不出來的時候停在離開碼 ${rc}，而且把 npm 自己講的原因（code 那行）印出來"
    else
      bad "停在離開碼 ${rc}，但沒有把 npm 的錯誤代碼端出來，讀者不知道要修什麼：
${out}"
    fi
  fi
fi

# ── 5 ────────────────────────────────────────────────────
if want 5; then
sect "5 npm ci 沒有 lockfile 會直接失敗；裝的時候不讓相依的 preinstall 跑"

  M=$(miss npm node)
  if [ -n "${M}" ]; then
    skip "沒裝 ${M}，npm ci 跑不起來"
  elif [ -n "$(miss curl)" ]; then
    skip "沒裝 curl，量不出註冊處通不通，這一節的結果不算數"
  elif [ "${HAVE_NET}" = 0 ]; then
    skip "curl 在，但問不到註冊處"
  else
    TD=$(mktemp -d)
    # 這一節是整份唯一真的把套件裝下來的地方，所以文章那句警告的現場就在這裡：
    # npm 預設會用你的身分跑相依自帶的 preinstall／postinstall，2025 年 PhantomRaven
    # 走的就是這條路。底下每一個會裝東西的指令都帶 --ignore-scripts，
    # 只有正向對照那一輪故意不帶（見下面）。
    #
    # 探針是一顆自製的本地相依，它的 preinstall 只做一件事：
    # 往 LIFECYCLE_MARK 指的絕對路徑寫一個檔。沒有這個痕跡的話，
    # 「腳本沒跑」跟「腳本跑了但什麼都沒留下」在畫面上是同一件事。
    mkdir -p "${TD}/probe-pkg" "${TD}/ctrl"
    cat > "${TD}/probe-pkg/package.json" <<'EOT'
{"name":"lifecycle-probe","version":"1.0.0","scripts":{"preinstall":"printf ran > \"$LIFECYCLE_MARK\""}}
EOT
    printf '{"name":"ci-demo","version":"1.0.0","dependencies":{"express":"^4.19.2","lifecycle-probe":"file:probe-pkg"}}\n' > "${TD}/package.json"
    printf '{"name":"ci-demo-ctrl","version":"1.0.0","dependencies":{"lifecycle-probe":"file:../probe-pkg"}}\n' > "${TD}/ctrl/package.json"
    MARK="${TD}/lifecycle-ran"
    MARK_CTRL="${TD}/lifecycle-ran-ctrl"

    out=$( cd "${TD}" && LIFECYCLE_MARK="${MARK}" npm ci --ignore-scripts 2>&1 ); rc=$?
    if [ "${rc}" != 0 ] && printf '%s' "${out}" | grep -qi 'lock'; then
      ok "沒有 lockfile 的時候 npm ci 失敗，而且訊息點名 lockfile"
    else
      bad "沒有 lockfile 的 npm ci 竟然成功了（rc=${rc}）：$(printf '%s' "${out}" | tail -3)"
    fi
    ( cd "${TD}" && LIFECYCLE_MARK="${MARK}" npm install --package-lock-only --ignore-scripts --silent >/dev/null 2>&1 )
    out=$( cd "${TD}" && LIFECYCLE_MARK="${MARK}" npm ci --ignore-scripts --silent 2>&1 ); rc=$?
    if [ "${rc}" = 0 ]; then
      ok "補上 lockfile 之後同一個指令就過了"
    else
      bad "有 lockfile 還是失敗（rc=${rc}）：$(printf '%s' "${out}" | tail -3)"
    fi

    # 正向對照：同一顆探針、同一個 npm ci，差別只有沒帶 --ignore-scripts。
    # 這一輪要看到檔出現，下面那條「檔不在」才有意義。它沒出現的話，
    # 「檔不在」證明的就只是這顆探針從頭到尾都不會寫檔，那條斷言永遠是綠的。
    # 解 lockfile 那步兩邊都帶旗標，讓兩輪之間只剩一個變因。
    ( cd "${TD}/ctrl" && LIFECYCLE_MARK="${MARK_CTRL}" npm install --package-lock-only --ignore-scripts --silent >/dev/null 2>&1 )
    outc=$( cd "${TD}/ctrl" && LIFECYCLE_MARK="${MARK_CTRL}" npm ci --silent 2>&1 ); rcc=$?
    if [ -e "${MARK_CTRL}" ]; then
      ok "正向對照：不帶 --ignore-scripts 的那一輪，相依的 preinstall 真的跑了，檔寫出來了"
    else
      bad "正向對照沒跑出痕跡（rc=${rcc}），不帶旗標那一輪也沒寫出檔，那下面那條「檔不在」永遠會綠：$(printf '%s' "${outc}" | tail -3)"
    fi

    if [ ! -e "${MARK_CTRL}" ]; then
      skip "正向對照沒跑出痕跡，「帶了旗標就沒跑」這條這一輪沒有結論"
    elif [ -e "${MARK}" ]; then
      bad "帶了 --ignore-scripts，那顆相依的 preinstall 還是跑了（檔內容是「$(cat "${MARK}")」）。這一節自己踩進了文章在警告的那件事"
    else
      ok "帶 --ignore-scripts 的那幾輪，相依的 preinstall 沒跑（同一顆探針在對照那輪寫得出檔）"
    fi

    sig=$( cd "${TD}" && npm audit signatures 2>&1 )
    if printf '%s' "${sig}" | grep -q 'verified registry signature'; then
      ok "npm audit signatures 全通過（那證明的是檔案沒被中途換掉，不是發布者可信）"
    # npm 把註冊處的公鑰釘在自己身上，舊版釘的那一把會過期。npm 9.9.4 上實測，
    # 每一顆都報「public key has expired 2025-01-29」。過期的是這台機器上那支 npm
    # 的內建鑰匙，不是被驗的東西，所以這是這台不適用，不是紅燈。
    elif printf '%s' "${sig}" | grep -q 'public key has expired'; then
      skip "這台的 npm（$(npm -v)）內建的註冊處公鑰已經過期，簽章這條驗不了。換一支新的 npm 再跑"
    else
      bad "簽章檢查沒過或訊息變了：$(printf '%s' "${sig}" | tail -3)"
    fi
    rm -rf "${TD}"
  fi
fi

# ── 收 ───────────────────────────────────────────────────
printf '\n════════ %s 綠 / %s 紅 / %s 跳過 ════════\n' "${PASS}" "${FAIL}" "${SKIP}"
if [ "${SKIP}" != 0 ]; then
  printf '有跳過的節，離開碼不會是 0。跳過不等於通過。\n'
fi
[ "${FAIL}" = 0 ] && [ "${SKIP}" = 0 ]
