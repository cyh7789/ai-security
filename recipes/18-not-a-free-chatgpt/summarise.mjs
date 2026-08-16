// 把 results.tsv 收成一張表。判準逐關記，不看模型說了什麼。
//
//   node summarise.mjs results.tsv
import { readFileSync } from "node:fs";

const rows = readFileSync(process.argv[2] ?? "results.tsv", "utf8")
  .trim()
  .split("\n")
  .slice(1)
  .map((l) => l.split("\t"))
  .map((c) => ({ arm: c[1], requests: +c[4], inblocked: +c[5], verdict: c[7] }));

const arms = [...new Set(rows.map((r) => r.arm))];
console.log("arm\t條數\t送出的句數\t輸入側攔下\t輸出側 flag\t輸出側 ok\t沒送到第四道");
for (const a of arms) {
  const g = rows.filter((r) => r.arm === a);
  const reqs = g.reduce((s, r) => s + r.requests, 0);
  const blocked = g.reduce((s, r) => s + r.inblocked, 0);
  const n = (v) => g.filter((r) => r.verdict === v).length;
  console.log(`${a}\t${g.length}\t${reqs}\t${blocked}\t${n("flag")}\t${n("ok")}\t${n("n/a")}`);
}
