#!/usr/bin/env bash
# 模型指了 server/tools.js 出來。這支做的是模型做不到的那一步：真的打一次。
#
#   bash confirm.sh
#
# 離開碼照 Day 22 那份公約：0 兩邊都如預期、1 有一邊不如預期、2 環境不到位沒有結論。
#
# 打的是 tools.js 的複本，在 mktemp -d 裡跑，不碰你的檔案也不連網。
# payload 只有 echo，沒有別的動作。
set -u
cd "$(dirname "$0")" || exit 2

command -v node >/dev/null 2>&1 || { echo "沒有 node，沒有結論"; exit 2; }
# dig 與 convert 一定要在。它們不在的時候，execFile 那半會因為 ENOENT 而
# 什麼都不做，於是「標記檔沒生出來」這個綠燈根本不是消毒的功勞（外審實測：
# 把 PATH 換成沒有這兩支的版本，整支照樣綠）。沒有就沒有結論，不給綠。
MISSING=""
for c in dig convert; do command -v "$c" >/dev/null 2>&1 || MISSING="${MISSING} ${c}"; done
[ -z "$MISSING" ] || { echo "缺${MISSING}，execFile 那半驗不掉，沒有結論"; exit 2; }
# 預設打 playground 現在那份。ANTARES_TOOLS_JS 可以指到別的複本，
# 突變測試靠它驗「這支真的在打那份原始碼」，不必就地改教材靶標。
SRC=${ANTARES_TOOLS_JS:-$(cd ../.. && pwd)/playground/server/tools.js}
[ -r "$SRC" ] || { echo "讀不到 $SRC，沒有結論"; exit 2; }

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT
cp "$SRC" "$WORK/vuln.js"

# 修好的版本：不進 shell。execFile 把參數當成一個陣列交出去，
# 分號、反引號、$() 在那裡面只是普通字元。
cat > "$WORK/fixed.js" <<'JS'
const { execFile } = require("child_process");
const util = require("util");
const execFileAsync = util.promisify(execFile);

async function lookupDomain(domain) {
  const { stdout } = await execFileAsync("dig", ["+short", domain]);
  return stdout.trim();
}

async function makeThumbnail(filename) {
  const { stdout } = await execFileAsync("convert", [
    `uploads/${filename}`, "-resize", "200x200", `thumbs/${filename}`,
  ]);
  return stdout;
}

module.exports = { lookupDomain, makeThumbnail };
JS

cat > "$WORK/attack.js" <<'JS'
// 兩個入口各打一次。第一個是模型看到的那條，第二個是打開檔案才會看到的第二處。
//
// 判準看的是「有沒有生出一個檔案」，不是輸出裡有沒有出現 payload 那串字。
// 第一版寫成比對字串，結果修好的版本也判成打進去了：dig 解不出那個網域的時候，
// 會把整串參數原樣印回錯誤訊息裡，而那串裡面就有 payload 的文字。
// 文字出現代表它被當成參數傳過去了，跟它有沒有被當成指令執行是相反的兩件事。
const fs = require("fs");
const path = require("path");
const mod = require(process.argv[2]);
const dir = process.argv[3];
const cases = [
  ["lookupDomain", `example.com; touch ${path.join(dir, "hit_dns")}`, "hit_dns"],
  ["makeThumbnail", `a.png; touch ${path.join(dir, "hit_thumb")} #`, "hit_thumb"],
];
(async () => {
  for (const [fn, payload, marker] of cases) {
    // 先用良性參數打一次。這一發是正對照，證明這條路徑真的把指令送出去了。
    // 少了它，「沒打進去」有三種可能都長一樣：消毒成功、指令不存在、
    // 模組壓根沒跑。三者不可分辨的話，修好那半的綠燈不代表任何事。
    let ran = false;
    try {
      await mod[fn](fn === "lookupDomain" ? "example.com" : "a.png");
      ran = true;                       // 有回傳值，指令跑完了
    } catch (err) {
      // 這裡要的是「指令真的被執行過」的正面證據，不是「沒看到 ENOENT」。
      // 第一版寫成後者，結果模組整個 throw 也被判成跑過（突變 M9b 咬到的）。
      // 那跟本檔上面那個 dig 的錯是同一型：拿否定當證據。
      //
      // 子行程真的起來過而失敗時，Node 會給一個數字的離開碼，並帶回 stderr。
      // 指令不存在（ENOENT）與純粹的 JS 例外都沒有這兩樣。
      ran = typeof err.code === "number" || typeof err.stderr === "string";
    }
    if (!ran) {
      console.log(`${fn}\t沒有結論`);
      continue;
    }
    try { await mod[fn](payload); } catch { /* 看檔案，不看錯誤 */ }
    const hit = fs.existsSync(path.join(dir, marker));
    console.log(`${fn}\t${hit ? "打進去了" : "沒打進去"}`);
  }
})();
JS

echo "=== 有洞的那份（playground/server/tools.js 現在的樣子）==="
mkdir -p "$WORK/marks-v"
V=$(node "$WORK/attack.js" "$WORK/vuln.js" "$WORK/marks-v" 2>/dev/null)
printf '%s\n' "$V"
echo
echo "=== 換成 execFile 之後 ==="
mkdir -p "$WORK/marks-f"
F=$(node "$WORK/attack.js" "$WORK/fixed.js" "$WORK/marks-f" 2>/dev/null)
printf '%s\n' "$F"
echo

VH=$(printf '%s\n' "$V" | grep -c '打進去了')
FH=$(printf '%s\n' "$F" | grep -c '打進去了')
# 「沒有結論」代表那個入口的正對照沒過，也就是這一發根本沒送出指令。
# 它不能被當成「沒打進去」，那正是這一輪要分開的兩件事。
NC=$(printf '%s\n%s\n' "$V" "$F" | grep -c '沒有結論')
[ "$NC" = 0 ] || { echo "有 ${NC} 個入口連良性參數都沒送出去，驗不掉，沒有結論"; exit 2; }
BAD=0
[ "$VH" = 2 ] || { echo "紅：有洞那份應該兩個入口都打得進去，實際 $VH 個"; BAD=1; }
[ "$FH" = 0 ] || { echo "紅：修好那份不該有任何一個打得進去，實際 $FH 個"; BAD=1; }
[ "$BAD" = 0 ] && echo "綠：有洞那份 2 個入口都打進去，換成 execFile 之後 0 個"
exit "$BAD"
