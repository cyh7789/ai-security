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
WS=$(mktemp -d); trap 'rm -rf "${WS}"' EXIT

# 「這台機器沒裝那個工具」跟「工具在、註冊處沒回應」要分開報：前者是這一節不適用，
# 後者是要驗的東西壞了。折成同一個旗標的話，沒裝 node 的機器會看到滿畫面紅燈。
miss() { local m=""; for t in "$@"; do command -v "${t}" >/dev/null 2>&1 || m="${m}${m:+、}${t}"; done; printf '%s' "${m}"; }

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

    # 下載數住在另一台主機。註冊處好好的、只有那台掛掉的時候，
    # 週下載欄會變成「?」，而「停更了還有人在下載」整個判斷站在那一欄上。
    # 對照組要蓋到兩台，不然「問不到」在那一欄上又長得像「沒人下載」。
    #
    # 這一條跟上面兩條不一樣，它需要網路：要造出「註冊處通、只有下載那台不通」，
    # 前一半得是真的。整台機器都不通的時候註冊處那個對照會先擋下來，
    # 訊息是註冊處那句，這裡就會變成一顆假紅燈（實測撞到）。
    if [ "${HAVE_NET}" = 0 ]; then
      skip "問不到註冊處，造不出「只有下載那台掛掉」這個情境"
    else
      out=$(NPM_DOWNLOADS=https://127.0.0.1:9 bash "${HERE}/check-pkgs.sh" express 2>&1); rc=$?
      n=0
      # 一、次要欄位不准綁架主功能：名字照樣要查得到
      printf '%s' "${out}" | grep -q '^查到.*express$' \
        || { bad "下載那台掛掉，連名字都查不到了：${out}"; n=1; }
      [ "${rc}" = 0 ] || { bad "下載那台掛掉不該讓整支失敗，rc=${rc}"; n=1; }
      # 二、那一格要看得出是「沒問到」，不是 0、不是空白、不是一個問號帶過
      printf '%s' "${out}" | grep -qE '^查到 +錯誤 ' \
        || { bad "那一格沒印成「錯誤」，看不出是沒問到：${out}"; n=1; }
      printf '%s' "${out}" | grep -q '不是「沒人下載」，是我沒問到' \
        || { bad "沒有講明「錯誤」跟「沒人下載」的差別，那還是靜默降級"; n=1; }
      # 三、少跑的那條檢查要出聲。檢查沒跑跟檢查跑完沒事，畫面上必須長得不一樣
      printf '%s' "${out}" | grep -q '這一項我沒幫你看' \
        || { bad "下載數沒問到，「下載數低不低」那條就沒跑，而收尾完全沒提。這是靜默的另一種形態"; n=1; }
      [ "${n}" = 0 ] && ok "下載那台掛掉時大聲降級：名字照樣查得到、那格印「錯誤」、收尾講明這一項沒檢查"
    fi

    # 但那個對照不能變成「次要欄位掛掉就整支拒答」：公司只把註冊處放進白名單的話，
    # 連「這個名字在不在」都問不到就太過頭。逃生口要真的能走，而且要看得見它關了。
    # 這兩條也要註冊處通得了：它們驗的是「下載欄降級的時候名字照樣查得到」，
    # 而「名字查得到」本身就要問到註冊處。連不到的機器上造不出這個情境
    if [ "${HAVE_NET}" = 0 ]; then
      skip "問不到註冊處，驗不到「下載欄關掉／壞掉但名字照樣查得到」"
    else
    offout=$(NPM_DOWNLOADS=off bash "${HERE}/check-pkgs.sh" express 2>&1); rc=$?
    n=0
    [ "${rc}" = 0 ] || { bad "NPM_DOWNLOADS=off 應該照常跑完，rc=${rc}"; n=1; }
    printf '%s' "${offout}" | grep -q '^查到.*express$' \
      || { bad "關掉下載欄之後名字查不到了"; n=1; }
    printf '%s' "${offout}" | grep -qE '^查到 +關 ' \
      || { bad "關掉之後那一格沒印成「關」"; n=1; }
    printf '%s' "${offout}" | grep -q '你自己關掉了下載數' \
      || { bad "收尾沒講「這一項沒檢查是因為你自己關的」"; n=1; }
    # 「你關的」跟「它壞了」是兩件事，訊息不能共用。
    # 共用的話讀者分不出自己是主動放棄，還是環境有問題要去修
    printf '%s' "${offout}" | grep -q '不是「沒人下載」，是我沒問到' \
      && { bad "關掉的訊息跟壞掉的訊息長一樣，兩種狀態分不開"; n=1; }
    [ "${n}" = 0 ] && ok "NPM_DOWNLOADS=off 走得通，那格印「關」，訊息跟「問不到」分得開"

    # 整台好好的、只有這一顆問不到，也要印「錯誤」不能印 0。
    # 這走的是另一條分支：上面那條是對照就失敗，這條是對照過了、個別套件才掛。
    # 沒有這條檢查的話那條 fallback 從來沒被看過（mutations.sh 第 6 種漏掉才發現）。
    if [ -n "$(miss node)" ] || [ "${HAVE_NET}" = 0 ]; then
      skip "沒裝 node 或問不到註冊處，「單顆問不到」那條分支沒驗到"
    else
      node -e '
const http=require("http");
const s=http.createServer((q,r)=>{
  // 對照問的是 /express，讓它過；其他每一顆都失敗
  if (q.url === "/express") { r.writeHead(200,{"content-type":"application/json"}); r.end(JSON.stringify({downloads:1})); }
  else { r.writeHead(500); r.end("nope"); }
});
s.listen(0,"127.0.0.1",()=>process.stdout.write(String(s.address().port)));' > "${WS}/p1.txt" &
      echo $! > "${WS}/p1.pid"
      disown 2>/dev/null || true
      i=0; while [ ! -s "${WS}/p1.txt" ] && [ "${i}" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
      P1=$(cat "${WS}/p1.txt" 2>/dev/null)
      if [ -z "${P1}" ]; then
        bad "起不了假的下載主機，「單顆問不到」那條分支沒驗到"
      else
        one=$(NPM_DOWNLOADS="http://127.0.0.1:${P1}" bash "${HERE}/check-pkgs.sh" express-rate-limiter 2>&1)
        kill "$(cat "${WS}/p1.pid")" 2>/dev/null
        if printf '%s' "${one}" | grep -qE '^查到 +錯誤 .*express-rate-limiter$'; then
          ok "對照過了但這一顆的下載數問不到，那格印「錯誤」而不是 0"
        else
          bad "單顆問不到卻沒印「錯誤」，那一格會被讀成真的數字：$(printf '%s' "${one}" | grep 'express-rate-limiter$')"
        fi
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
sect "5 npm ci 沒有 lockfile 會直接失敗，這正是它跟 npm install 的差別"

  M=$(miss npm node)
  if [ -n "${M}" ]; then
    skip "沒裝 ${M}，npm ci 跑不起來"
  elif [ -n "$(miss curl)" ]; then
    skip "沒裝 curl，量不出註冊處通不通，這一節的結果不算數"
  elif [ "${HAVE_NET}" = 0 ]; then
    skip "curl 在，但問不到註冊處"
  else
    TD=$(mktemp -d)
    printf '{"name":"ci-demo","version":"1.0.0","dependencies":{"express":"^4.19.2"}}\n' > "${TD}/package.json"
    out=$( cd "${TD}" && npm ci 2>&1 ); rc=$?
    if [ "${rc}" != 0 ] && printf '%s' "${out}" | grep -qi 'lock'; then
      ok "沒有 lockfile 的時候 npm ci 失敗，而且訊息點名 lockfile"
    else
      bad "沒有 lockfile 的 npm ci 竟然成功了（rc=${rc}）：$(printf '%s' "${out}" | tail -3)"
    fi
    ( cd "${TD}" && npm install --package-lock-only --silent >/dev/null 2>&1 )
    out=$( cd "${TD}" && npm ci --silent 2>&1 ); rc=$?
    if [ "${rc}" = 0 ]; then
      ok "補上 lockfile 之後同一個指令就過了"
    else
      bad "有 lockfile 還是失敗（rc=${rc}）：$(printf '%s' "${out}" | tail -3)"
    fi

    sig=$( cd "${TD}" && npm audit signatures 2>&1 )
    if printf '%s' "${sig}" | grep -q 'verified registry signature'; then
      ok "npm audit signatures 全通過（那證明的是檔案沒被中途換掉，不是發布者可信）"
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
