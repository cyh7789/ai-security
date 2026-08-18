// 兩種問法各叫模型修 N 輪，每一輪都實跑攻擊輸入，結果寫進 TSV。
//
//   MODEL_CMD='bash adapter.sh' N=12 OUT=runs/2026-08-18 node run-suite.mjs
//
// 這支會執行模型交回來的程式碼。它們全部留在 <OUT>/fixes/，跑之前先看一眼。
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, appendFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { probe } from "./probe.mjs";

const MODEL_CMD = process.env.MODEL_CMD;
if (!MODEL_CMD) {
  console.error("要設 MODEL_CMD，例如 MODEL_CMD='bash adapter.sh'");
  process.exit(2);
}
const N = Number(process.env.N ?? 12);
const OUT = process.env.OUT ?? "runs/scratch";
const ARMS = (process.env.ARMS ?? "plain withtests").split(/\s+/).filter(Boolean);

const SOURCE = readFileSync("vuln.mjs", "utf8");

/** 模型很愛加程式碼圍籬，剝掉；剝不掉的留原樣讓 probe 判 unusable。 */
function unfence(text) {
  const m = text.match(/```(?:[a-zA-Z]*)\n([\s\S]*?)```/);
  return (m ? m[1] : text).trim() + "\n";
}

mkdirSync(join(OUT, "fixes"), { recursive: true });
const tsv = join(OUT, "results.tsv");
writeFileSync(tsv, "arm\trun\tverdict\thits\tbenign\tspawned\n");

for (const arm of ARMS) {
  const prompt = readFileSync(join("prompts", `${arm}.txt`), "utf8") + SOURCE;
  for (let run = 1; run <= N; run++) {
    const r = spawnSync("bash", ["-c", MODEL_CMD], { input: prompt, encoding: "utf8", maxBuffer: 1 << 24 });
    const file = join(OUT, "fixes", `${arm}-${String(run).padStart(2, "0")}.mjs`);
    writeFileSync(file, unfence(r.stdout ?? ""));
    const p = await probe(file);
    const row = [arm, run, p.verdict, p.hits.length ? p.hits.join(",") : "-", p.benign,
      p.spawned ? "有" : "沒有"].join("\t");
    appendFileSync(tsv, row + "\n");
    console.error(`  ${row}`);
  }
}
console.error(`\n寫進 ${tsv}`);
