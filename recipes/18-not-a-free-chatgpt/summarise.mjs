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
const iRef = at("refused"), iGrd = at("guarded"), iPf = at("perflag");
const num = (c, i) => (i < 0 ? null : +c[i]);
const rows = lines.slice(1).map((l) => l.split("\t")).map((c) => ({
  arm: c[iArm], requests: +c[iReq], inblocked: +c[iBlk],
  refused: num(c, iRef), guarded: num(c, iGrd), perflag: num(c, iPf), verdict: c[iV],
}));

const arms = [...new Set(rows.map((r) => r.arm))];
// 分母要寫在欄名裡。「逐段判被標」是段數、「輸出側 flag」是鏈數，
// 兩欄並排而 onemsg 那列剛好兩邊都是 3（每鏈只有一段），很容易被讀成同一個口徑。
// 所以多印一欄鏈數，並在欄名標出分母。
console.log("arm\t條數\t送出的句數\t輸入側攔下\t模型不肯寫(鏈)\t自己加防呆(鏈)\t逐段判被標(段)\t逐段判被標(鏈)\t輸出側 flag(鏈)\t輸出側 ok(鏈)\t沒送到第四道");
for (const a of arms) {
  const g = rows.filter((r) => r.arm === a);
  const reqs = g.reduce((s, r) => s + r.requests, 0);
  const blocked = g.reduce((s, r) => s + r.inblocked, 0);
  const n = (v) => g.filter((r) => r.verdict === v).length;
  const tot = (k) => (g[0][k] === null ? "－" : g.reduce((s, r) => s + r[k], 0));
  const ref = tot("refused");
  const grd = tot("guarded");
  const pf = tot("perflag");
  const pfc = g[0].perflag === null ? "－" : g.filter((r) => r.perflag > 0).length;
  console.log(`${a}\t${g.length}\t${reqs}\t${blocked}\t${ref}\t${grd}\t${pf}\t${pfc}\t${n("flag")}\t${n("ok")}\t${n("n/a")}`);
}
