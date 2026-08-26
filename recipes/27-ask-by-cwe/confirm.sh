#!/usr/bin/env bash
# 模型指了 server/tools.js 出來。這支做的是模型做不到的那一步：真的打一次。
#
#   bash confirm.sh
#
# 離開碼照 Day 22 那份公約：0 兩邊都如預期、1 有一邊不如預期、2 環境不到位沒有結論。
#
# 全程在 mktemp -d 裡跑，不碰你的檔案、不連網、不需要你裝 dig 或 ImageMagick：
# dig 與 convert 都換成暫存目錄裡的假版本，只把收到的參數逐行記下來、回一個固定結果。
# 假版本讓良性那半有得驗（參數原樣送到了嗎），也讓修好那半不再靠「系統剛好沒裝這兩支」
# 才通過。攻擊 payload 用的是 touch，生一個標記檔，沒有別的動作。
set -u
cd "$(dirname "$0")" || exit 2

command -v node >/dev/null 2>&1 || { echo "沒有 node，沒有結論"; exit 2; }

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

# 假的 dig 與 convert，放在 $WORK/bin，等一下用 PATH 讓子行程找到它們。
# 它們只把收到的每個參數寫一行進 log，再回一個固定的成功結果。
# dig 回一個假 IP，讓良性那半可以比對「回傳值就是它印的那個」。
mkdir -p "$WORK/bin"
cat > "$WORK/bin/dig" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$FAKE_DIG_LOG"
echo "1.2.3.4"
SH
cat > "$WORK/bin/convert" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$FAKE_CONVERT_LOG"
SH
chmod +x "$WORK/bin/dig" "$WORK/bin/convert"

cat > "$WORK/probe.js" <<'JS'
// 每個入口打兩發：
//   良性參數 → 證明這條路徑真的把指令送出去，而且良性參數原樣送到假 dig/convert
//              手上（功能還在）。少了它，「沒打進去」有消毒成功、指令不存在、
//              模組沒跑三種可能都長一樣，修好那半的通過不代表任何事。
//   攻擊參數 → 看檔案系統上有沒有多一個標記檔，證明 shell 有沒有把分號後面那段跑掉。
// 判準看的是「有沒有生出標記檔」，不是輸出裡有沒有出現 payload 那串字：
// dig 解不出網域時會把整串參數原樣印回錯誤訊息，那串裡就有 payload 的文字，
// 但文字出現代表它被當成參數傳過去了，跟它有沒有被當成指令執行是相反的兩件事。
const fs = require("fs");
const path = require("path");
const mod = require(process.argv[2]);
const dir = process.argv[3];
const digLog = process.env.FAKE_DIG_LOG;
const convLog = process.env.FAKE_CONVERT_LOG;
const args = (f) => (fs.existsSync(f) ? fs.readFileSync(f, "utf8").split("\n") : []);

const cases = [
  {
    fn: "lookupDomain", benign: "example.com",
    attack: `example.com; touch ${path.join(dir, "hit_dns")}`, marker: "hit_dns",
    // 良性通過：回傳值就是假 dig 印的那個，而且假 dig 收到的是乾淨的 example.com。
    works: (ret) => ret === "1.2.3.4" && args(digLog).includes("example.com"),
  },
  {
    fn: "makeThumbnail", benign: "a.png",
    attack: `a.png; touch ${path.join(dir, "hit_thumb")} #`, marker: "hit_thumb",
    // 良性通過：假 convert 收到 uploads/a.png 與 thumbs/a.png 兩個乾淨路徑。
    works: () => {
      const a = args(convLog);
      return a.includes("uploads/a.png") && a.includes("thumbs/a.png");
    },
  },
];

(async () => {
  for (const c of cases) {
    let ok = false;
    try { ok = c.works(await mod[c.fn](c.benign)); } catch { ok = false; }
    if (!ok) { console.log(`${c.fn}\t功能沒驗過`); continue; }
    try { await mod[c.fn](c.attack); } catch { /* 看檔案，不看錯誤 */ }
    const hit = fs.existsSync(path.join(dir, c.marker));
    console.log(`${c.fn}\t${hit ? "打進去了" : "沒打進去"}`);
  }
})();
JS

run_side() {  # $1=要跑的 js $2=這一側的暫存子目錄
  mkdir -p "$WORK/$2"
  FAKE_DIG_LOG="$WORK/$2/dig.log" FAKE_CONVERT_LOG="$WORK/$2/conv.log" \
    PATH="$WORK/bin:$PATH" \
    node "$WORK/probe.js" "$WORK/$1" "$WORK/$2" 2>/dev/null
}

echo "=== 有洞的那份（playground/server/tools.js 現在的樣子）==="
V=$(run_side vuln.js marks-v); printf '%s\n' "$V"; echo
echo "=== 換成 execFile 之後 ==="
F=$(run_side fixed.js marks-f); printf '%s\n' "$F"; echo

# 良性沒驗過代表那個入口的功能對照沒成立，攻擊結果不算數。
NC=$(printf '%s\n%s\n' "$V" "$F" | grep -c '功能沒驗過')
[ "$NC" = 0 ] || { echo "有 ${NC} 個入口的良性功能沒驗過，攻擊結果不算數，沒有結論"; exit 2; }
VH=$(printf '%s\n' "$V" | grep -c '打進去了')
FH=$(printf '%s\n' "$F" | grep -c '打進去了')
BAD=0
[ "$VH" = 2 ] || { echo "沒過：有洞那份應該兩個入口都打得進去，實際 $VH 個"; BAD=1; }
[ "$FH" = 0 ] || { echo "沒過：修好那份不該有任何一個打得進去，實際 $FH 個"; BAD=1; }
[ "$BAD" = 0 ] && echo "通過：有洞那份 2 個入口都打進去，換成 execFile 之後 0 個"
exit "$BAD"
