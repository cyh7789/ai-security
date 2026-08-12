#!/usr/bin/env node
// 把知識庫按「這段是哪來的」分組數一次。
//
//   node kb-sources.cjs demo/kb.jsonl
//   node kb-sources.cjs demo/kb.jsonl --prefix :     # 只看冒號前面那一截
//   your-export-command | node kb-sources.cjs -
//
// 吃的是一行一個 JSON 物件（JSONL），至少要有 text 跟 source 兩個欄位。
// 多數向量庫都匯得出這個形狀，metadata 裡的 source 也認。
//
// 結束碼跟 Day 8 那條規矩一樣，三種，因為「沒有問題」跟「我沒看到」不能混：
//   0  每一段都有來源
//   2  有段落沒有來源欄，或有行讀不出來
//
// 為什麼是非 0：一段答不出「你哪來的」的內容，跟一段來源乾淨的內容，
// 在檢索的時候待遇完全一樣。它不是雜訊，它是你清單上填不了的那一列。

const fs = require("fs");

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith("--")) || "";
const prefixAt = args.indexOf("--prefix");
const SEP = prefixAt === -1 ? null : args[prefixAt + 1];

function fail(msg) {
  console.error(msg);
  process.exit(2);
}

if (!file) fail("用法：node kb-sources.cjs <匯出檔.jsonl|-> [--prefix <分隔字元>]");

let raw;
try {
  raw = fs.readFileSync(file === "-" ? 0 : file, "utf8");
} catch (e) {
  fail(`讀不到 ${file}：${e.message}`);
}

const lines = raw.split("\n").filter((l) => l.trim() !== "");
const groups = new Map();
let noSource = 0;
let unreadable = 0;
let chars = 0;

for (const line of lines) {
  let rec;
  try {
    rec = JSON.parse(line);
  } catch {
    unreadable += 1;
    continue;
  }
  chars += String(rec.text ?? "").length;
  const src = rec.source ?? (rec.metadata && rec.metadata.source);
  if (typeof src !== "string" || src.trim() === "") {
    noSource += 1;
    continue;
  }
  // --prefix 是給「來源長得像 kind:檔名」那種用的：一份檔案一個來源的話，
  // 不切前綴會列出幾百列各自為 1，看不出它們其實是同一個入口。
  const key = SEP && src.includes(SEP) ? src.slice(0, src.indexOf(SEP)) : src;
  groups.set(key, (groups.get(key) || 0) + 1);
}

const sorted = [...groups.entries()].sort((a, b) => b[1] - a[1]);
const width = Math.max(0, ...sorted.map(([k]) => k.length));

const parsed = lines.length - unreadable;
console.log(
  unreadable
    ? `════ ${parsed} 段（讀了 ${lines.length} 行），${groups.size} 個來源 ════`
    : `════ ${parsed} 段，${groups.size} 個來源 ════`,
);
for (const [k, n] of sorted) {
  console.log(`${k.padEnd(width)}  ${String(n).padStart(5)}`);
}
console.log(`合計 ${chars} 字元。`);

if (noSource || unreadable) {
  if (noSource) console.log(`\n沒有來源欄的：${noSource} 段。這幾段你答不出它們是誰放的。`);
  if (unreadable) console.log(`讀不出來的行：${unreadable} 行。`);
  console.log("（結束碼 2）");
  process.exit(2);
}

console.log("\n每一段都有來源欄。");
console.log("那只代表欄位填了，不代表那個來源有人看過。填了什麼跟誰能寫，是下一張表的事。");
console.log("（結束碼 0）");
