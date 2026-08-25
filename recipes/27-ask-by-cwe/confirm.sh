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
SRC=$(cd ../.. && pwd)/playground/server/tools.js
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
    // 指令本身沒裝不影響結論：注入成不成立看的是分號後面那半段有沒有跑，
    // 不是 dig 或 convert 在不在這台機器上。所以錯誤一律吞掉，只看檔案。
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
BAD=0
[ "$VH" = 2 ] || { echo "紅：有洞那份應該兩個入口都打得進去，實際 $VH 個"; BAD=1; }
[ "$FH" = 0 ] || { echo "紅：修好那份不該有任何一個打得進去，實際 $FH 個"; BAD=1; }
[ "$BAD" = 0 ] && echo "綠：有洞那份 2 個入口都打進去，換成 execFile 之後 0 個"
exit "$BAD"
