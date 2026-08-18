// 數每一臂各是什麼判定，並且對「有沒有打得穿的」做一次 Fisher 精確檢定。
//
//   node summarise.mjs runs/2026-08-18/results.tsv
//
// 兩臂是各自獨立跑的，不是同一顆修法的兩種問法，所以配對檢定不適用，用 Fisher。
import { readFileSync } from "node:fs";

const file = process.argv[2] ?? "runs/scratch/results.tsv";
const rows = readFileSync(file, "utf8").trim().split("\n").slice(1)
  .map((l) => l.split("\t"))
  .map(([arm, run, verdict, hits, benign]) => ({ arm, run: Number(run), verdict, hits, benign }));

const arms = [...new Set(rows.map((r) => r.arm))].sort();
const VERDICTS = ["pass", "vuln", "noexec", "broken", "unusable"];

console.log(`來源\t${file}`);
console.log(`臂\t${VERDICTS.join("\t")}\t小計`);
for (const arm of arms) {
  const mine = rows.filter((r) => r.arm === arm);
  const counts = VERDICTS.map((v) => mine.filter((r) => r.verdict === v).length);
  console.log(`${arm}\t${counts.join("\t")}\t${mine.length}`);
}

console.log("\n打得穿的是哪一條輸入");
const hitNames = [...new Set(rows.flatMap((r) => (r.hits === "-" ? [] : r.hits.split(","))))].sort();
if (!hitNames.length) console.log("  無");
for (const name of hitNames) {
  const per = arms.map((arm) => {
    const mine = rows.filter((r) => r.arm === arm);
    return `${arm} ${mine.filter((r) => r.hits.split(",").includes(name)).length}/${mine.length}`;
  });
  console.log(`  ${name}\t${per.join("\t")}`);
}

// ── 兩臂的差異值不值得講 ────────────────────────────
const lnFact = (n) => { let s = 0; for (let i = 2; i <= n; i++) s += Math.log(i); return s; };
const hyper = (a, b, c, d) =>
  Math.exp(lnFact(a + b) + lnFact(c + d) + lnFact(a + c) + lnFact(b + d)
    - lnFact(a) - lnFact(b) - lnFact(c) - lnFact(d) - lnFact(a + b + c + d));

if (arms.length === 2) {
  const [x, y] = arms.map((arm) => {
    const mine = rows.filter((r) => r.arm === arm);
    return { bad: mine.filter((r) => r.verdict === "vuln").length, n: mine.length };
  });
  const a = x.bad, b = x.n - x.bad, c = y.bad, d = y.n - y.bad;
  const obs = hyper(a, b, c, d);
  let p = 0;
  for (let i = 0; i <= a + b; i++) {
    const j = a + b - i, k = a + c - i, l = c + d - (a + c - i);
    if (j < 0 || k < 0 || l < 0) continue;
    const t = hyper(i, j, k, l);
    if (t <= obs * (1 + 1e-9)) p += t;
  }
  console.log(`\n打得穿的比例\t${arms[0]} ${a}/${x.n}\t${arms[1]} ${c}/${y.n}`);
  // 小 p 用 toFixed(4) 會全部變成 0.0000，看不出差別也驗不了。
  console.log(`Fisher 精確檢定（雙尾）\tp = ${p < 1e-3 ? p.toExponential(2) : p.toFixed(4)}`);
  console.log("N 很小，p 大只代表這批資料分不出差別，不代表兩種問法一樣。");
}
