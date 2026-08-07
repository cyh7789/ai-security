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

# 「這台機器沒裝那個工具」跟「工具在、註冊處沒回應」要分開報：前者是這一節不適用，
# 後者是要驗的東西壞了。折成同一個旗標的話，沒裝 node 的機器會看到滿畫面紅燈。
miss() { local m=""; for t in "$@"; do command -v "${t}" >/dev/null 2>&1 || m="${m}${m:+、}${t}"; done; printf '%s' "${m}"; }

HAVE_NET=0
if [ -z "$(miss curl)" ]; then
  [ "$(curl -s -o /dev/null -w '%{http_code}' -m 20 https://registry.npmjs.org/express 2>/dev/null)" = "200" ] && HAVE_NET=1
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
    out=$(bash "${HERE}/check-pkgs.sh" express 2>&1); rc=$?
    if [ "${rc}" = 0 ] && printf '%s' "${out}" | grep -q '^查到.*express$'; then
      ok "正向對照：express 查得到"
    else
      bad "正向對照掛了（rc=${rc}）：${out}"
    fi

    out=$(bash "${HERE}/check-pkgs.sh" "${RANDNAME}" 2>&1); rc=$?
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
    a=$(bash "${HERE}/check-pkgs.sh" express "${RANDNAME}" 2>&1 | grep -E '^(查到|沒有|錯誤)')
    b=$(bash "${HERE}/check-pkgs.sh" -f "${TD}/pkgs.txt" 2>&1 | grep -E '^(查到|沒有|錯誤)')
    c=$(printf 'express\n%s\n' "${RANDNAME}" | bash "${HERE}/check-pkgs.sh" - 2>&1 | grep -E '^(查到|沒有|錯誤)')
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
  else
    # express-rate-limiter 是真的存在、2022 年後就沒動過的套件。
    # 這裡不主張它有惡意，主張的只有一件事：它的下載數不為零。
    line=$(bash "${HERE}/check-pkgs.sh" express-rate-limiter 2>&1 | grep 'express-rate-limiter$' | head -1)
    dl=$(printf '%s' "${line}" | awk '{print $2}')
    mod=$(printf '%s' "${line}" | awk '{print $3}')
    if [ -z "${dl}" ] || [ -z "${mod}" ]; then
      bad "抓不到那一行：${line}"
    elif ! printf '%s' "${dl}" | grep -qE '^[0-9]+$'; then
      bad "下載數不是數字（${dl}），這一節沒驗到東西：${line}"
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
