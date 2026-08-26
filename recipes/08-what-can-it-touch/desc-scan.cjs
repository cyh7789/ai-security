// 掃「別人寫的、會被送進模型上下文的字」有沒有在對模型下指令。兩個入口：
//   node desc-scan.cjs tools            讀 stdin 上 list-tools.sh 的輸出，逐行掃
//   node desc-scan.cjs files <路徑...>   掃目錄或檔案裡的 markdown 指示檔（SKILL.md 這類）
//
// 為什麼兩個入口共用一支：樣式表分兩份寫的話，補了一邊漏了另一邊，
// 而畫面上看不出來哪一邊少一類。遮蔽只寫在 mcp-config.cjs 裡是同一個理由。
//
// 副檔名是 .cjs 的理由跟 mcp-rpc.cjs 一樣，見那支的檔頭。
//
// 結束碼三種，因為「乾淨」跟「我沒掃到」不能混在一起：
//   0  掃過了，四類樣式一個都沒中
//   1  掃過了，命中，逐條點名
//   2  沒東西可掃（路徑讀不到、底下沒有 markdown、沒給路徑）。這不是乾淨。

const fs = require("fs");
const path = require("path");

// 四類樣式。分類是為了讓 verify.sh 能一類一類驗，少一類就少一個抓得到的形狀。
// 大小寫一律不敏感（旗標在下面的 RegExp 裡）。
// 撇號用 . 代掉（don.t）：來源可能打的是 U+2019 那個彎的，也可能是半形的。
const PATTERNS = [
  ["標籤", "<\\s*(important|system|critical|instruction|secret|hidden)"],
  ["路徑", "(~/\\.ssh|\\.ssh/|id_rsa|id_ed25519|\\.env\\b|mcp\\.json|\\.aws/credentials|\\.npmrc|\\.git-credentials|authorized_keys)"],
  ["隱瞞", "(do not mention|don.?t mention|without mentioning|do not tell|don.?t tell|without telling|do not inform|do not reveal|keep (this|it|that) (a )?secret)"],
  ["覆寫", "(ignore (all )?previous|ignore the above|disregard (all |the )?(previous|above)|override your (instructions|prompt)|your real instructions)"],
].map(([g, r]) => [g, new RegExp(r, "i")]);

// 一行一行掃，命中的行連同它屬於哪裡一起記下來。
// 這裡截斷的是「證據那一行」，不是被掃的內容本身：完整內容由上游負責整份印出來。
function scan(lines, where) {
  const hits = [];
  lines.forEach((line, i) => {
    for (const [g, re] of PATTERNS) {
      const found = line.match(re);
      if (!found) continue;
      const around = line.length > 100 ? line.slice(0, 100) + " […]" : line;
      hits.push([where(i), g, found[0], around]);
    }
  });
  return hits;
}

function report(hits, tailLine) {
  if (!hits.length) {
    process.stdout.write("四類樣式（標籤／路徑／隱瞞／覆寫）一個都沒中。\n");
    process.stdout.write("那代表它沒有用已經公開過的那幾種寫法，不代表它安全。\n");
    process.exitCode = 0;
    return;
  }
  process.stdout.write("\n── 命中 " + hits.length + " 條 ──\n");
  for (const [w, g, what, around] of hits) {
    process.stdout.write(w + "  [" + g + "]  抓到「" + what + "」\n");
    process.stdout.write("    " + around + "\n");
  }
  process.stdout.write("\n" + tailLine + "\n");
  process.exitCode = 1;
}

// ── tools 模式 ────────────────────────────────────────────
function fromTools() {
  const lines = fs.readFileSync(0, "utf8").split("\n");
  // list-tools.sh 的每一段開頭是這一行。工具名從這裡取，命中才點得出是哪一個工具。
  // 這一行本身也要掃：工具名字裡塞路徑的話，證據就在名字上。
  const HEAD = /^── 第 \d+ 個工具（共 \d+ 個）：(.+)，描述 \d+ 字元 ──$/;
  let tool = "(還沒進到任何工具)";
  const owner = lines.map((line) => {
    const m = line.match(HEAD);
    if (m) tool = m[1];
    return tool;
  });
  report(scan(lines, (i) => owner[i]),
    "這幾條是寫在工具描述裡的，是這台 server 備好要餵給模型的內容，而你在 UI 上只看到工具名字。");
}

// ── files 模式 ────────────────────────────────────────────
// 只吃 markdown：SKILL.md 這一類指示檔就是 markdown。直接指名一個檔的時候不篩副檔名，
// 因為那是讀者自己挑的；往目錄底下走的時候才篩，不然這支會變成一支 grep。
const MD = /\.(md|markdown|mdc)$/i;
const SKIPDIR = /^(\.git|node_modules|\.venv|dist|build)$/;

function walk(dir, out, depth) {
  if (depth > 8) return;
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (e) {
    return;
  }
  for (const e of entries.sort((a, b) => (a.name < b.name ? -1 : 1))) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (!SKIPDIR.test(e.name)) walk(p, out, depth + 1);
    } else if (MD.test(e.name)) {
      out.push(p);
    }
  }
}

function fromFiles(targets) {
  if (!targets.length) {
    process.stdout.write("--files 後面要給至少一個路徑（目錄或檔案）。\n");
    process.exitCode = 2;
    return;
  }
  const files = [];
  const missing = [];
  for (const t of targets) {
    let st;
    try {
      st = fs.statSync(t);
    } catch (e) {
      missing.push(t);
      continue;
    }
    if (st.isDirectory()) walk(t, files, 0);
    else files.push(t);
  }

  // 路徑讀不到不能算成乾淨。打錯一個字就靜靜回 0 的話，那個通過的意思是
  // 「我什麼都沒掃」，而讀者會把它讀成「這批指示檔沒問題」。
  if (missing.length) {
    process.stdout.write("讀不到這個路徑：" + missing.join(" ") + "\n");
    process.stdout.write("沒東西可掃就沒有掃到，結束碼 2。這不是「乾淨」。\n");
    process.exitCode = 2;
    return;
  }
  if (!files.length) {
    process.stdout.write("這幾個路徑底下找不到 markdown 指示檔：" + targets.join(" ") + "\n");
    process.stdout.write("沒東西可掃就沒有掃到，結束碼 2。這不是「乾淨」。\n");
    process.exitCode = 2;
    return;
  }

  const hits = [];
  for (const f of files) {
    let lines;
    try {
      lines = fs.readFileSync(f, "utf8").split("\n");
    } catch (e) {
      process.stdout.write("讀不到 " + f + "：" + e.message + "\n");
      process.exitCode = 2;
      return;
    }
    // 行號一起印：指示檔動輒幾百行，只給檔名的話讀者還要自己找。
    for (const h of scan(lines, (i) => f + ":" + (i + 1))) hits.push(h);
  }
  process.stdout.write("掃了 " + files.length + " 個 markdown 指示檔。\n");
  report(hits,
    "這幾條是寫在指示檔裡的，那個檔被載進來的時候整段都會進模型的上下文。");
}

const mode = process.argv[2];
if (mode === "tools") fromTools();
else if (mode === "files") fromFiles(process.argv.slice(3));
else {
  fs.writeSync(2, "用法：node desc-scan.cjs tools｜files <路徑...>\n");
  process.exit(2);
}
