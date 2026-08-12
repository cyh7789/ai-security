#!/usr/bin/env bash
# 把功能一個一個弄壞，看 verify.sh 有沒有轉紅。
#
#   bash mutations.sh
#
# 為什麼要有這支：一份全綠的 verify.sh 證明不了任何事，因為「這條檢查會不會失敗」
# 跟「這條檢查現在通過」是兩個問題。
#
# 每一條都在複本上動手，原檔不碰。最後一條是**反向對照**：
# 改一個不影響行為的地方，這時候 verify.sh 應該還是全綠。
# 沒有這一條的話，「什麼都會讓它紅」跟「它咬得準」分不開。

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BAD=0

# 用 node 改檔，不用 sed：BSD 跟 GNU 的 sed 行為不同，而「替換沒套用卻被當成綠」
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

workdir() {
  local w; w=$(mktemp -d)/13
  mkdir -p "${w}"
  cp -R "${HERE}/." "${w}/" 2>/dev/null
  printf '%s' "${w}"
}

try() { # try <說明> <預期會紅的條號，空白分隔> <改法函式>
  local what="$1" expect="$2" fn="$3"
  local work; work=$(workdir)
  if ! (cd "${work}" && "${fn}"); then
    printf '  [壞掉] %s：改不下去\n' "${what}"; BAD=1; rm -rf "${work}"; return
  fi
  local red=""
  for n in ${expect}; do
    if (cd "${work}" && bash verify.sh "${n}" >/dev/null 2>&1); then red="${red} 第${n}條沒紅"; fi
  done
  if [ -z "${red}" ]; then printf '  [咬到] %s → 第 %s 條轉紅\n' "${what}" "${expect}"
  else printf '  [漏了] %s →%s\n' "${what}" "${red}"; BAD=1; fi
  rm -rf "${work}"
}

control() {
  local what="$1" fn="$2"
  local work; work=$(workdir)
  if ! (cd "${work}" && "${fn}"); then
    printf '  [壞掉] %s：改不下去\n' "${what}"; BAD=1; rm -rf "${work}"; return
  fi
  if (cd "${work}" && bash verify.sh >/dev/null 2>&1); then
    printf '  [對照] %s → 還是全綠，符合預期\n' "${what}"
  else
    printf '  [壞掉] %s → 不該紅卻紅了，代表 verify.sh 在咬不相干的東西\n' "${what}"; BAD=1
  fi
  rm -rf "${work}"
}

echo "════ 把功能弄壞，看 verify.sh 咬不咬得到 ════"

m_nosource_group() {
  sub kb-sources.cjs '    noSource += 1;
    continue;' '    // 沒有來源的當成一組叫「(未知)」，看起來清單還是完整的
    groups.set("(未知)", (groups.get("(未知)") || 0) + 1);
    continue;'
}
try "沒有來源的段落改成歸到一組「(未知)」" "3" m_nosource_group

m_always_zero() {
  sub kb-sources.cjs 'if (noSource || unreadable) {' 'if (false) {'
}
try "有段落沒來源也照樣結束碼 0" "3" m_always_zero

m_swallow_bad_line() {
  sub kb-sources.cjs '    unreadable += 1;
    continue;' '    continue; // 讀不出來的靜靜跳過'
}
try "壞掉的行靜靜跳過不數" "4" m_swallow_bad_line

m_ignore_prefix() {
  sub kb-sources.cjs 'const key = SEP && src.includes(SEP) ? src.slice(0, src.indexOf(SEP)) : src;' 'const key = src;'
}
try "--prefix 收下但不切" "1 2 5" m_ignore_prefix

m_first_page_only() {
  sub kb-sources.cjs 'const lines = raw.split("\n").filter((l) => l.trim() !== "");' 'const lines = raw.split("\n").filter((l) => l.trim() !== "").slice(0, 5);'
}
try "只讀前五行就當作讀完" "1 2" m_first_page_only

m_lstat() {
  sub rank-probe.cjs 'st = fs.statSync(p);' 'st = fs.lstatSync(p);'
}
try "走訪改用 lstatSync（Day 12 那個洞）" "11" m_lstat

m_no_cycle_guard() {
  sub rank-probe.cjs '  if (seen.has(real)) return; // symlink 繞圈' '  // 拿掉繞圈保護'
}
try "拿掉 symlink 繞圈保護" "12" m_no_cycle_guard

m_always_first() {
  sub rank-probe.cjs 'const at = ranked.findIndex((d) => d.poison);' 'const at = 0;'
}
try "投毒那份一律報第 1 名" "8" m_always_first

m_beat_the_top() {
  sub rank-probe.cjs 'const cut = ranked[TOP - 1];' 'const cut = ranked[0];'
}
try "「要贏過誰」報成第一名的分數" "10" m_beat_the_top

m_ignore_top() {
  sub rank-probe.cjs 'const TOP = parseInt(opts["--top"] ?? "10", 10);' 'const TOP = 10;'
}
try "--top 收下但一律用 10" "9" m_ignore_top

m_skip_len_check() {
  sub rank-probe.cjs 'if (arr.length !== texts.length) fail' 'if (false) fail'
}
try "不檢查 embedding 端點回了幾筆" "14" m_skip_len_check

m_embed_ignored() {
  sub rank-probe.cjs '  if (EMBED) {' '  if (false) {'
}
try "--embed 收下但還是走字面" "13" m_embed_ignored

m_skip_silently() {
  sub rank-probe.cjs '  if (skipped.length) {
    console.log(`\n這次跳過了 ${skipped.length} 個路徑，所以這份排名不完整。（結束碼 2）`);
    process.exit(2);
  }' '  // 跳過就跳過，照樣回 0'
}
try "跳過路徑照樣回 0（Day 12 那個洞）" "15" m_skip_silently

m_no_dim_check() {
  sub rank-probe.cjs '    if (!Array.isArray(v) || v.length !== dim || v.some((x) => typeof x !== "number" || !Number.isFinite(x))) {' '    if (false) {'
}
try "不檢查向量維度" "14" m_no_dim_check

m_stdin_fallback() {
  sub kb-sources.cjs 'raw = fs.readFileSync(file === "-" ? 0 : file, "utf8");' 'raw = fs.readFileSync(file === "-" ? "demo/kb.jsonl" : file, "utf8");'
}
try "stdin 壞掉之後偷偷改讀示範檔" "6" m_stdin_fallback

m_first_bad_line_only() {
  sub kb-sources.cjs '    unreadable += 1;
    continue;' '    if (unreadable === 0) unreadable = 1;
    continue;'
}
try "壞行只記第一個" "4" m_first_bad_line_only

# 反向對照：改一句不影響行為的說明文字。
m_cosmetic() {
  sub rank-probe.cjs '名次是相對的：' '名次是比出來的：'
}
control "把一句輸出的說明換個講法" m_cosmetic

echo
[ "${BAD}" = 0 ] && echo "全部咬到，而且反向對照沒有誤咬。" || echo "有漏的，上面標了。"
[ "${BAD}" = 0 ]
