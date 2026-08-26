#!/usr/bin/env bash
# 把功能一個一個弄壞，看 verify.sh 有沒有沒過。
#
#   bash mutations.sh
#
# 為什麼要有這支：一份全部通過的 verify.sh 證明不了任何事，因為「這條檢查會不會失敗」
# 跟「這條檢查現在通過」是兩個問題。Day 11 有六條檢查在正常路徑上會過，
# 拿掉被驗的東西之後還會過，那六條從頭到尾沒有在驗東西。
#
# 每一條都在複本上動手，原檔不碰。最後一條是**反向對照**：
# 改一個不影響行為的地方，這時候 verify.sh 應該還是全部通過。
# 沒有這一條的話，「什麼都會讓它沒過」跟「它抓得準」分不開。

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BAD=0

# 用 node 改檔，不用 sed：BSD 跟 GNU 的 sed 行為不同，而「替換沒套用卻被當成通過」
# 正好是這支要抓的那種假訊號。node 找不到目標字串的時候會直接喊。
sub() { # sub <檔> <原字串> <新字串>
  node -e '
    const fs = require("fs");
    const [f, from, to] = process.argv.slice(1);
    const s = fs.readFileSync(f, "utf8");
    if (!s.includes(from)) { process.stderr.write("找不到要換的字串：" + from + "\n"); process.exit(9); }
    fs.writeFileSync(f, s.replace(from, to));
  ' "$1" "$2" "$3"
}

try() { # try <說明> <預期會沒過的條號，空白分隔> <改法函式>
  local what="$1" expect="$2" fn="$3"
  local work; work=$(mktemp -d)/12
  mkdir -p "${work}"
  cp -R "${HERE}/." "${work}/" 2>/dev/null
  # 第 8 條要跟 Day 8 那支並排跑，複本裡沒有它的話那條會跳過，
  # 而跳過在 verify.sh 眼裡會過，突變就會看起來像沒抓到。
  [ -d "${HERE}/../08-what-can-it-touch" ] && cp -R "${HERE}/../08-what-can-it-touch" "${work}/../" 2>/dev/null
  if ! (cd "${work}" && "${fn}"); then
    printf '  [壞掉] %s：改不下去\n' "${what}"; BAD=1; rm -rf "${work}"; return
  fi
  local red=""
  for n in ${expect}; do
    if (cd "${work}" && bash verify.sh "${n}" >/dev/null 2>&1); then
      red="${red} 第${n}條沒抓到"
    fi
  done
  if [ -z "${red}" ]; then printf '  [抓到] %s → 第 %s 條沒過\n' "${what}" "${expect}"
  else printf '  [漏了] %s →%s\n' "${what}" "${red}"; BAD=1; fi
  rm -rf "${work}"
}

# 反向對照用：預期全部通過。
control() {
  local what="$1" fn="$2"
  local work; work=$(mktemp -d)/12
  mkdir -p "${work}"
  cp -R "${HERE}/." "${work}/" 2>/dev/null
  [ -d "${HERE}/../08-what-can-it-touch" ] && cp -R "${HERE}/../08-what-can-it-touch" "${work}/../" 2>/dev/null
  if ! (cd "${work}" && "${fn}"); then
    printf '  [壞掉] %s：改不下去\n' "${what}"; BAD=1; rm -rf "${work}"; return
  fi
  if (cd "${work}" && bash verify.sh >/dev/null 2>&1); then
    printf '  [對照] %s → 還是全部通過，符合預期\n' "${what}"
  else
    printf '  [壞掉] %s → 這一條不該被抓，卻被抓到了，代表 verify.sh 在抓不相干的東西\n' "${what}"; BAD=1
  fi
  rm -rf "${work}"
}

echo "════ 把功能弄壞，看 verify.sh 抓不抓得到 ════"

m1() { sub mcp-desc.cjs 'const desc = typeof t.description === "string" ? t.description : "";' \
  'const desc = (typeof t.description === "string" ? t.description : "").slice(0, 100);'; }
try "描述截斷到 100 字元" "2" m1

m2() { sub mcp-desc.cjs '  process.exit(2);
};' '  process.exit(0);
};'; }
try "問不到的時候改回結束碼 0" "4 5" m2

m3() { sub mcp-desc.cjs 'process.stdout.write("initialize 跟 tools/list 都答了，它就是沒宣告工具。\n");' \
  '/* 拿掉那句區別 */'; }
try "零個工具的時候不講它跟問不到的差別" "6" m3

# 這一條是 Day 8 那支的真實行為，也是這一份存在的理由。
m4() { sub skill-scan.cjs '      let st;
      try { st = fs.statSync(p); } catch (e2) { trouble.push(["讀不到", p]); continue; }' \
  '      let st = e;'; }
try "走訪改回問 Dirent，不跟 symlink" "7 8 11 12" m4

m5() { sub skill-scan.cjs '  process.stdout.write("有東西沒看到就不算掃過，結束碼 2。\n");
  process.exit(2);' '  process.stdout.write("有東西沒看到。\n");'; }
try "有東西沒看到卻還是回 0" "9 10" m5

m6() { sub skill-scan.cjs '.split("\n").map((s) => s.trim()).join(" ").trim()' \
  '.split("\n")[0].trim()'; }
try "多行的 description 只取第一行" "13" m6

m7() { sub skill-scan.cjs 'if (!quiet) {' 'if (true) {'; }
try "--quiet 照樣把描述全印出來" "14" m7

m8() { sub README.md 'node skill-scan.cjs --quiet demo/tree' 'node skill-scan.cjs --quiet demo/does-not-exist-at-all/x.md'; }
try "README 貼一條指到不存在路徑的指令" "15" m8

# 第 12 條驗的是「判準失效」，所以要反過來驗：
# 有人讓那兩份分開之後，文章那段判斷就不成立了，這條必須沒過。
m9() { sub skill-scan.cjs '  const hit = IMPERATIVE.some((re) => re.test(d));' \
  '  const hit = IMPERATIVE.some((re) => re.test(d)) && !/id_rsa/.test(d);'; }
try "加一條規則讓下毒那份不算命令句" "12" m9

# 這一條是第一版 mcp-desc.cjs 的真實行為，也是外審抓到的那個洞。
m10() { sub mcp-desc.cjs '      cursor = res.nextCursor;
      pages += 1;
      // 分頁不收斂的話會一直問下去，那是 server 壞了，不是我沒問完。
      if (pages > 50) fail("問了 50 頁還有 nextCursor，這台的分頁沒有收斂");' \
  '      cursor = undefined;
      pages += 1;'; }
try "只問第一頁，不跟 nextCursor" "16" m10

# 外審抓到的第二個洞：用真假值判斷有沒有下一頁，空字串 cursor 就會被當成問完了。
# stdio 與 http 各改一路，第 16 條都要沒過（那條四種組合都跑）。
m11() { sub mcp-desc.cjs '      more = Object.prototype.hasOwnProperty.call(res, "nextCursor");
      cursor = res.nextCursor;
      pages += 1;
      // 分頁不收斂的話會一直問下去，那是 server 壞了，不是我沒問完。' \
  '      cursor = res.nextCursor;
      more = !!cursor;
      pages += 1;
      // 分頁不收斂的話會一直問下去，那是 server 壞了，不是我沒問完。'; }
try "stdio 那一路改回用真假值判斷 cursor" "16" m11

m12() { sub mcp-desc.cjs '      more = Object.prototype.hasOwnProperty.call(res, "nextCursor");
      cursor = res.nextCursor;
      pages += 1;
      if (pages > 50)' \
  '      cursor = res.nextCursor;
      more = !!cursor;
      pages += 1;
      if (pages > 50)'; }
try "http 那一路改回用真假值判斷 cursor" "16" m12

echo
echo "════ 反向對照 ════"
c1() { sub skill-scan.cjs '// 以及統計那一段為什麼不是風險指標：README。' '// 以及統計那一段為什麼不是風險指標：README（改過的註解）。'; }
control "只改一行註解" c1

echo
[ "${BAD}" = 0 ] && echo "全部抓到，而且反向對照沒有誤抓。" || echo "有漏的，上面標了。"
[ "${BAD}" = 0 ]
