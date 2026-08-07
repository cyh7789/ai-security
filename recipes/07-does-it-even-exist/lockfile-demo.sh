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
# 只寫暫存目錄，不動你的專案。用 --package-lock-only，不會真的下載套件。

set -u
command -v npm >/dev/null 2>&1 || { echo "沒有 npm，這支跑不了"; exit 2; }

WS=$(mktemp -d)
trap 'rm -rf "${WS}"' EXIT

count() {  # count <目錄> <版本範圍字串>
  local d="${WS}/$1"
  mkdir -p "${d}"
  printf '{"name":"demo","version":"1.0.0","dependencies":{"express":"%s"}}\n' "$2" > "${d}/package.json"
  ( cd "${d}" && npm install --package-lock-only --silent >/dev/null 2>&1 )
  [ -f "${d}/package-lock.json" ] || { echo "ERR"; return; }
  ( cd "${d}" && npm audit --json 2>/dev/null ) \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{
        const m=JSON.parse(s).metadata.vulnerabilities;
        console.log([m.total,m.critical,m.high,m.moderate,m.low].join(" "));
      }catch(e){console.log("ERR")}})'
}

resolved() { node -e 'const j=require(process.argv[1]);console.log(j.packages["node_modules/express"].version)' "${WS}/$1/package-lock.json" 2>/dev/null || echo '?'; }
deps()     { node -e 'const j=require(process.argv[1]);console.log(Object.keys(j.packages).filter(k=>k).length)' "${WS}/$1/package-lock.json" 2>/dev/null || echo '?'; }

echo "跑的日子：$(date +%F)  npm $(npm -v)"
echo

for pair in "float:^4.19.2" "pinned:4.19.2"; do
  d=${pair%%:*}; range=${pair#*:}
  out=$(count "${d}" "${range}")
  set -- ${out}
  if [ "${1:-ERR}" = "ERR" ]; then
    printf 'express "%s"  audit 跑不起來（沒網路？）\n' "${range}"
    continue
  fi
  printf 'express "%-8s" → 實際鎖到 %-8s lockfile 裡 %s 個套件  弱點 %s 則（critical %s / high %s / moderate %s / low %s）\n' \
    "${range}" "$(resolved "${d}")" "$(deps "${d}")" "$1" "$2" "$3" "$4" "$5"
done

cat <<'EOT'

看兩件事：
1. 你宣告了 1 個相依，lockfile 裡的套件數遠不只 1 個。那些你沒選過。
2. 兩邊的弱點數不同，而 package.json 只差一個 ^。
   audit 掃的是 lockfile 的實際解析結果，不是你的意圖。
EOT
