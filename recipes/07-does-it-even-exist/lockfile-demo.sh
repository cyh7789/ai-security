#!/usr/bin/env bash
# 同一個相依，差一個 ^ 符號，npm audit 的答案不一樣。
#
# 兩邊都宣告 express 4.19.2：
#   浮動：^4.19.2  → 允許裝 4.x 的最新版，實際會裝到已經修過的那版
#   釘死： 4.19.2  → 就是那一版，2024 年 3 月發的
#
# 跑完你會看到浮動那邊 0 個弱點、釘死那邊一串。這不代表釘版本比較危險，
# 只代表 audit 報的是「你鎖住的那份 lockfile 現在對得上幾則公告」。
# 浮動那邊的 0 是「今天沒有」，明天同一份 package.json 可能就不是 0 了。
#
# 不動你的專案。用 --package-lock-only，不會下載套件本體，但註冊處的中繼資料還是會
# 進 ~/.npm/_cacache（實測寫了一百多個檔），另外 npm 自己會留 debug log。

set -u
command -v npm >/dev/null 2>&1 || { echo "沒有 npm，這支跑不了"; exit 2; }

WS=$(mktemp -d)
trap 'rm -rf "${WS}"' EXIT

count() {  # count <目錄> <版本範圍字串>
  local d="${WS}/$1"
  mkdir -p "${d}"
  printf '{"name":"demo","version":"1.0.0","dependencies":{"express":"%s"}}\n' "$2" > "${d}/package.json"
  # npm 的 stderr 留著不丟。跑不起來的原因不只「沒網路」一種（快取目錄不可寫、
  # npm 設定壞掉都會長一樣），而這份 recipe 的主張就是分得出「沒有」跟「沒問到」。
  # 把原因吞掉，收尾就只能猜一個最常見的講給讀者聽，那正是這裡在反對的事。
  # 用 --loglevel=error 不用 --silent：--silent 連 stderr 都關掉，npm.err 會是空的，
  # 收尾就沒有原因可以端給讀者。stdout 本來就丟掉了，進度條不會吵到人。
  ( cd "${d}" && npm install --package-lock-only --loglevel=error >/dev/null 2>"${d}/npm.err" )
  [ -f "${d}/package-lock.json" ] || { echo "ERR"; return; }
  ( cd "${d}" && npm audit --json 2>>"${d}/npm.err" ) \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{
        const m=JSON.parse(s).metadata.vulnerabilities;
        console.log([m.total,m.critical,m.high,m.moderate,m.low].join(" "));
      }catch(e){console.log("ERR")}})'
}

resolved() { node -e 'const j=require(process.argv[1]);console.log(j.packages["node_modules/express"].version)' "${WS}/$1/package-lock.json" 2>/dev/null || echo '?'; }
deps()     { node -e 'const j=require(process.argv[1]);console.log(Object.keys(j.packages).filter(k=>k).length)' "${WS}/$1/package-lock.json" 2>/dev/null || echo '?'; }

echo "跑的日子：$(date +%F)  npm $(npm -v)"
echo

ROWS=0
for pair in "float:^4.19.2" "pinned:4.19.2"; do
  d=${pair%%:*}; range=${pair#*:}
  out=$(count "${d}" "${range}")
  set -- ${out}
  if [ "${1:-ERR}" = "ERR" ]; then
    # 不在這裡猜「沒網路？」。原因等一下由收尾把 npm 的原話端出來
    printf 'express "%s"  audit 跑不起來\n' "${range}"
    continue
  fi
  printf 'express "%-8s" → 實際鎖到 %-8s lockfile 裡 %s 個套件  弱點 %s 則（critical %s / high %s / moderate %s / low %s）\n' \
    "${range}" "$(resolved "${d}")" "$(deps "${d}")" "$1" "$2" "$3" "$4" "$5"
  ROWS=$((ROWS + 1))
done

# 把 npm 自己講的原因端出來，不替讀者猜。
# 取前三行不是後三行：npm 的錯誤訊息是「原因在前、罐頭建議在後」，
# 連不到註冊處那次總共 22 行，後三行全是「你是不是在代理後面」這種通用建議，
# 真正分得出情境的 code/syscall/errno 都在最前面。取後三行等於把原因丟掉，
# 兩種完全不同的故障會印出一模一樣的建議，那正是這一份在反對的事。
dump_npm_err() {  # dump_npm_err <float|pinned>...
  local d said=0
  for d in "$@"; do
    if [ -s "${WS}/${d}/npm.err" ]; then
      grep -v '^[[:space:]]*$' "${WS}/${d}/npm.err" | head -3 | sed "s|^|  ${d} │ |" >&2
      said=1
    fi
  done
  [ "${said}" = 0 ] && printf '  npm 一句話都沒說，先確認 npm 本身跑得起來（npm -v）。\n' >&2
  return 0
}

# 兩邊都沒跑出來的話，這支的整個重點（兩邊對照）就沒發生。
# 下面那段解說會照樣印，讀者看到「看兩件事」卻沒有東西可看，而離開碼還是 0。
if [ "${ROWS}" = 0 ]; then
  printf '\n兩邊都沒跑出結果，沒有東西可以對照。\n' >&2
  dump_npm_err float pinned
  exit 2
fi
# 只出來一邊也不是對照。這種情況更需要知道差在哪，所以掛掉那邊的原因照印
if [ "${ROWS}" = 1 ]; then
  printf '\n只跑出一邊，對照不成立。上面那行不能單獨拿來下結論。\n' >&2
  dump_npm_err float pinned
  exit 2
fi

cat <<'EOT'

看兩件事：
1. 你宣告了 1 個相依，lockfile 裡的套件數遠不只 1 個。那些你沒選過。
2. 兩邊的弱點數不同，而 package.json 只差一個 ^。
   audit 掃的是 lockfile 的實際解析結果，不是你的意圖。
EOT
