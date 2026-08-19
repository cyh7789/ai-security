// 這支不產生東西，它去讀 recipe 18 兩個禮拜留下來的紀錄，量兩件事：
//
//   node drift.mjs
//
// 一、欄位會跑。同一支腳本的七批結果，欄數從 9 長到 12，
//     而 outreason 這一欄的位置跟著往後移。任何「cat 起來、表頭讀一次、
//     之後照欄號取值」的算法，在後面幾個檔讀到的都是別的欄位。
//
// 二、理由那一欄的不重複數是假的。整批 252 列有 203 種不同的理由，
//     看起來像 203 種情境；按 armname 切開就會看到，benign 那 48 列
//     是同一組正常請求，模型寫出 48 種不同的措辭，重複率零。
//
// 為什麼這兩件事要一起量：它們是同一個病的兩面。
// 判準每天在改，紀錄的欄位跟著長，而理由是模型當場寫的自由文字。
// 兩週之後你把這批東西加總，量到的是自己的改版史加上模型的措辭抖動。
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const RUNS = join(HERE, "../18-not-a-free-chatgpt/runs");

function tsv(path) {
  const lines = readFileSync(path, "utf8").trim().split("\n").filter(Boolean);
  const head = lines[0].split("\t");
  return { head, rows: lines.slice(1).map((l) => Object.fromEntries(l.split("\t").map((v, i) => [head[i], v]))) };
}

// 每一批都有 outreason 欄的檔，全部收進來。挑法故意寫成「看表頭有沒有這一欄」
// 而不是寫死檔名，因為寫死檔名就等於自己維護一份會過期的清單。
const files = [];
for (const d of readdirSync(RUNS).sort()) {
  const dir = join(RUNS, d);
  if (!statSync(dir).isDirectory()) continue;
  for (const f of readdirSync(dir).sort()) {
    if (!f.endsWith(".tsv")) continue;
    const p = join(dir, f);
    const { head } = tsv(p);
    if (head.includes("outreason")) files.push(p);
  }
}

console.log("== 一、欄位跑掉了 ==");
console.log("批次\t欄數\toutreason 在第幾欄");
for (const p of files) {
  const { head } = tsv(p);
  console.log(`${p.split("/").slice(-2).join("/")}\t${head.length}\t${head.indexOf("outreason") + 1}`);
}
const widths = [...new Set(files.map((p) => tsv(p).head.length))];
console.log(`欄數出現過 ${widths.length} 種：${widths.join("、")}`);

console.log("");
console.log("== 二、理由的不重複數 ==");
const byArm = new Map();
// requests 欄記的是那一臂送了幾條輸入。要印它是因為「48 種理由」單獨看沒有意義，
// 得知道那 48 次判的是幾條輸入：同一條輸入 48 種理由，跟 48 條輸入 48 種理由，
// 是兩件完全不同的事，而表面上的數字一模一樣。
const inputsOf = new Map();
let total = 0;
const all = [];
for (const p of files) {
  for (const r of tsv(p).rows) {
    const reason = (r.outreason ?? "").trim();
    if (!reason) continue;
    total += 1;
    all.push(reason);
    const arm = r.armname ?? "-";
    if (!byArm.has(arm)) byArm.set(arm, []);
    byArm.get(arm).push(reason);
    if (!inputsOf.has(arm)) inputsOf.set(arm, new Set());
    inputsOf.get(arm).add(r.requests ?? "?");
  }
}
console.log("臂\t輸入\t列數\t不重複");
let sum = 0;
for (const arm of [...byArm.keys()].sort()) {
  const rs = byArm.get(arm);
  const d = new Set(rs).size;
  sum += d;
  const inp = [...inputsOf.get(arm)].join("/");
  console.log(`${arm}\t${inp}\t${rs.length}\t${d}`);
}
const totalInputs = [...inputsOf.entries()].reduce((n, [, v]) => n + Number([...v][0] || 0), 0);
console.log(`整批\t${totalInputs}\t${total}\t${new Set(all).size}`);
console.log(`各臂不重複相加 ${sum}，跟整批的 ${new Set(all).size} ${sum === new Set(all).size ? "一樣" : "不一樣"}`);

// 相加剛好等於整批，代表沒有任何一句理由跨臂重複過。
// 換句話說：模型連「同一句話」都不會在兩個不同的實驗臂裡講第二次。
const once = [...all.reduce((m, r) => m.set(r, (m.get(r) ?? 0) + 1), new Map()).values()].filter((v) => v === 1).length;
console.log(`只出現一次的理由有 ${once} 種`);
