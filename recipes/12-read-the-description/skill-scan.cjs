// 把指示檔（SKILL.md 這一類）全部找出來，印出每一份的描述欄，並統計它的形狀。
//
//   node skill-scan.cjs ~/.claude/skills ~/.claude/plugins
//   node skill-scan.cjs --quiet <路徑...>     只印統計，不印每一份描述
//
// 跟 Day 8 那支 desc-scan.cjs 的兩個差別（走訪跟著 symlink、跳過了什麼要講出來），
// 以及統計那一段為什麼不是風險指標：README。

const fs = require("fs");
const path = require("path");

const MD = /\.(md|markdown|mdc)$/i;
const SKIPDIR = /^(\.git|node_modules|\.venv|dist|build)$/;

// 對模型下命令的句式。這是形狀統計用的，不是安全判準：
// 底下每一條在正常的描述裡都天天出現，命中不代表有問題。
const IMPERATIVE = [
  /\byou (must|should|will|need to)\b/i,
  /\b(do not|don'?t|never|always)\b/i,
  /\buse (this|when|it|for)\b/i,
  /\b(call|invoke|read|check|ignore) (this|the|it)\b/i,
  /\bimportant\b/i,
  /(必須|一律|務必|不要|請先|使用時|時用|才用)/,
];

function collect(targets) {
  const files = [];
  const trouble = [];
  const seen = new Set();
  let followed = 0;

  function walk(dir, depth) {
    if (depth > 8) { trouble.push(["太深，停在這裡", dir]); return; }
    // realpath 認同一個目錄，symlink 繞回自己的時候才停得下來。
    let real;
    try { real = fs.realpathSync(dir); } catch (e) { trouble.push(["讀不到", dir]); return; }
    if (seen.has(real)) { trouble.push(["繞回來過了，跳過", dir]); return; }
    seen.add(real);

    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { trouble.push(["讀不到", dir]); return; }
    for (const e of entries.sort((a, b) => (a.name < b.name ? -1 : 1))) {
      const p = path.join(dir, e.name);
      // 這裡是關鍵那一行：問檔案系統，不問 Dirent。
      // Dirent 對 symlink 回的 isDirectory() 是 false，Day 8 那支就是死在這裡。
      let st;
      try { st = fs.statSync(p); } catch (e2) { trouble.push(["讀不到", p]); continue; }
      if (e.isSymbolicLink()) followed += 1;
      if (st.isDirectory()) {
        if (!SKIPDIR.test(e.name)) walk(p, depth + 1);
      } else if (MD.test(e.name)) {
        files.push(p);
      }
    }
  }

  for (const t of targets) {
    let st;
    try { st = fs.statSync(t); } catch (e) { trouble.push(["讀不到", t]); continue; }
    if (st.isDirectory()) walk(t, 0);
    else files.push(t);
  }
  return { files, trouble, followed };
}

// frontmatter 的 description 欄。這一欄跟 MCP 的工具描述是同一種東西：
// 別人寫的、會進模型上下文、而你在畫面上只看到一個名字。
function description(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return null;
  const d = m[1].match(/(?:^|\n)description:\s*([\s\S]*?)(?=\n[A-Za-z_-]+:\s|$)/);
  if (!d) return null;
  return d[1].replace(/^[|>]-?\s*\n?/, "").split("\n").map((s) => s.trim()).join(" ").trim();
}

const quiet = process.argv[2] === "--quiet";
const targets = process.argv.slice(quiet ? 3 : 2);
if (!targets.length) {
  process.stdout.write("要給至少一個路徑。沒東西可掃就沒有掃到，結束碼 2。\n");
  process.exit(2);
}

const { files, trouble, followed } = collect(targets);
if (!files.length) {
  process.stdout.write("這幾個路徑底下找不到 markdown 指示檔：" + targets.join(" ") + "\n");
  process.stdout.write("沒東西可掃就沒有掃到，結束碼 2。這不是「乾淨」。\n");
  process.exit(2);
}

let withDesc = 0, chars = 0, imperative = 0;
for (const f of files) {
  let text;
  try { text = fs.readFileSync(f, "utf8"); } catch (e) { trouble.push(["讀不到", f]); continue; }
  const d = description(text);
  if (d === null) continue;
  withDesc += 1;
  chars += [...d].length;
  const hit = IMPERATIVE.some((re) => re.test(d));
  if (hit) imperative += 1;
  if (!quiet) {
    process.stdout.write("\n── " + f + "，描述 " + [...d].length + " 字元，" +
      (hit ? "有命令句" : "沒有命令句") + " ──\n" + d + "\n");
  }
}

process.stdout.write("\n════════ 走過 " + files.length + " 個 markdown，跟著 " + followed +
  " 個 symlink 進去過 ════════\n");
process.stdout.write("其中 " + withDesc + " 份有描述欄，合計 " + chars + " 字元。\n");
process.stdout.write("含命令句的 " + imperative + " 份。\n");
process.stdout.write("那個比例不是風險指標。它量的是這個欄位的正常長相，\n");
process.stdout.write("而正常長相就是命令句，所以語氣分不出好壞。\n");

if (trouble.length) {
  process.stdout.write("\n── 沒看到的 " + trouble.length + " 個 ──\n");
  for (const [why, where] of trouble) process.stdout.write(why + "：" + where + "\n");
  process.stdout.write("有東西沒看到就不算掃過，結束碼 2。\n");
  process.exit(2);
}
process.stdout.write("TOTAL\t" + files.length + "\t" + withDesc + "\t" + chars + "\t" + imperative + "\n");
