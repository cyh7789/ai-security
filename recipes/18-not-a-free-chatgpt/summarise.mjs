// 把 results.tsv 收成一張表。判準逐關記，不看模型說了什麼。
//
//   node summarise.mjs results.tsv
import { readFileSync } from "node:fs";

// 欄位取名字不取位置，理由同 reasons.mjs：加過欄之後舊檔會安靜地讀到別欄。
// 舊檔沒有的欄（refused／guarded）當 0，並在表上留白，不要假裝量過。
const lines = readFileSync(process.argv[2] ?? "results.tsv", "utf8").trim().split("\n");
const head = lines[0].split("\t");
const at = (name) => head.indexOf(name);
const req = (name) => {
  const i = at(name);
  if (i < 0) { console.error(`少了「${name}」欄，表頭：${head.join(" ")}`); process.exit(2); }
  return i;
};
const [iArm, iReq, iBlk, iV] = [req("arm"), req("requests"), req("inblocked"), req("outverdict")];
const iRef = at("refused"), iGrd = at("guarded");
const num = (c, i) => (i < 0 ? null : +c[i]);
const rows = lines.slice(1).map((l) => l.split("\t")).map((c) => ({
  arm: c[iArm], requests: +c[iReq], inblocked: +c[iBlk],
  refused: num(c, iRef), guarded: num(c, iGrd), verdict: c[iV],
}));

const arms = [...new Set(rows.map((r) => r.arm))];
console.log("arm\t條數\t送出的句數\t輸入側攔下\t模型不肯寫\t自己加防呆\t輸出側 flag\t輸出側 ok\t沒送到第四道");
for (const a of arms) {
  const g = rows.filter((r) => r.arm === a);
  const reqs = g.reduce((s, r) => s + r.requests, 0);
  const blocked = g.reduce((s, r) => s + r.inblocked, 0);
  const n = (v) => g.filter((r) => r.verdict === v).length;
  const tot = (k) => (g[0][k] === null ? "－" : g.reduce((s, r) => s + r[k], 0));
  const ref = tot("refused");
  const grd = tot("guarded");
  console.log(`${a}\t${g.length}\t${reqs}\t${blocked}\t${ref}\t${grd}\t${n("flag")}\t${n("ok")}\t${n("n/a")}`);
}
