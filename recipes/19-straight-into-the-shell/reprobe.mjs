// 判準改過之後，用留檔的修法重新判一次，不用再花錢問模型。
//
//   node reprobe.mjs runs/2026-08-18b
import { readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { probe } from "./probe.mjs";

const OUT = process.argv[2] ?? "runs/scratch";
const files = readdirSync(join(OUT, "fixes")).filter((f) => f.endsWith(".mjs")).sort();
const lines = ["arm\trun\tverdict\thits\tbenign\tspawned"];
for (const f of files) {
  const [arm, num] = f.replace(/\.mjs$/, "").split("-");
  const p = await probe(join(OUT, "fixes", f));
  lines.push([arm, Number(num), p.verdict, p.hits.length ? p.hits.join(",") : "-", p.benign,
    p.spawned ? "有" : "沒有"].join("\t"));
}
writeFileSync(join(OUT, "results.tsv"), lines.join("\n") + "\n");
console.log(`重判 ${files.length} 份，寫回 ${join(OUT, "results.tsv")}`);
