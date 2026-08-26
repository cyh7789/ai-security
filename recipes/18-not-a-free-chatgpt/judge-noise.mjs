// 逐段判與組合判對不上，有多少是「兩種判法看到不一樣的東西」，
// 有多少只是同一顆分類器對同一段文字給不同答案。
//
//   node judge-noise.mjs runs/2026-08-17b/results.tsv
//
// 關鍵在單則的那幾組：每條鏈只送一則，所以 pieces.length === 1，
// 逐段判與組合判送給分類器的是**同一段文字**。那幾組的不一致率就是量尺本身的抖動，
// 是 split 那幾條不一致的基線。沒有這個基線，4/12 對不上會被讀成「兩種判法互補」，
// 而那是 8/17 評審那輪打掉的讀法。
//
// kappa 與 McNemar 兩個數字回答不同的問題：
//   kappa   兩欄除了偶然一致之外還剩多少共同訊號（0 = 跟各自擲幣沒兩樣）
//   McNemar 不一致的那幾條有沒有方向（對稱 = 沒有方向）
// 「兩個方向各兩條」是對稱的極端，它是最沒有資訊的結果，不是發現。

import { readFileSync } from "node:fs";

const path = process.argv[2] || "runs/2026-08-17b/results.tsv";
const lines = readFileSync(path, "utf8").trim().split("\n");
const head = lines[0].split("\t");
const at = (k) => head.indexOf(k);
const [iArm, iRun, iSent, iPf, iV] = ["arm", "run", "sent", "perflag", "outverdict"].map(at);
if (iPf < 0) {
  console.error(`${path} 沒有 perflag 欄，這一輪沒量逐段判`);
  process.exit(2);
}

const rows = lines.slice(1).map((l) => l.split("\t"));
const per = (r) => (Number(r[iPf]) > 0 ? "flag" : "ok");
const byArm = new Map();
for (const r of rows) {
  if (!byArm.has(r[iArm])) byArm.set(r[iArm], []);
  byArm.get(r[iArm]).push(r);
}

// 單則 = 這一組每條鏈都只送一則，兩種判法吃的是同一段文字
// 排序固定，不然輸出順序跟著檔案裡的交錯順序跑，文章貼的區塊就對不上重跑
const sorted = [...byArm.entries()].sort(([a], [b]) => a.localeCompare(b));
const single = sorted.filter(([, g]) => g.every((r) => Number(r[iSent]) === 1));
const multi = sorted.filter(([, g]) => g.some((r) => Number(r[iSent]) > 1));

console.log("單則的三組（逐段判與組合判是同一段文字）");
let dn = 0;
let dd = 0;
for (const [arm, g] of single) {
  const d = g.filter((r) => per(r) !== r[iV]).length;
  dn += d;
  dd += g.length;
  console.log(`  ${arm.padEnd(10)} ${d}/${g.length} 條反過來`);
}
console.log(`  合計       ${dn}/${dd}`);

for (const [arm, g] of multi) {
  const n = g.length;
  const a = g.map((r) => (per(r) === "flag" ? 1 : 0));
  const b = g.map((r) => (r[iV] === "flag" ? 1 : 0));
  const agree = a.filter((x, i) => x === b[i]).length;
  const pa = a.reduce((s, x) => s + x, 0) / n;
  const pb = b.reduce((s, x) => s + x, 0) / n;
  const po = agree / n;
  const pe = pa * pb + (1 - pa) * (1 - pb);
  // 兩欄都全 0 或全 1 時 pe = 1，kappa 沒有定義。那種格子印不出資訊，直接說明。
  const kappa = pe === 1 ? null : (po - pe) / (1 - pe);
  const exp = 2 * pa * (1 - pb) * n;
  const b01 = a.filter((x, i) => x === 0 && b[i] === 1).length;
  const b10 = a.filter((x, i) => x === 1 && b[i] === 0).length;
  // McNemar 精確檢定：不一致的 m 條裡看到 b01 條偏一邊，公平硬幣的雙尾機率
  const m = b01 + b10;
  const C = (n2, k) => { let v = 1; for (let i = 0; i < k; i++) v = (v * (n2 - i)) / (i + 1); return v; };
  let p = 0;
  for (let k = 0; k <= m; k++) {
    const pk = C(m, k) / 2 ** m;
    if (pk <= C(m, b01) / 2 ** m + 1e-12) p += pk;
  }
  console.log(`\n${arm}（分五次送，兩種判法吃的文字真的不一樣）`);
  console.log(`  逐段 ${a.reduce((s, x) => s + x, 0)}/${n}  組合 ${b.reduce((s, x) => s + x, 0)}/${n}  一致 ${agree}/${n}`);
  if (kappa === null) {
    console.log("  兩欄都沒有變異，kappa 沒有定義");
    continue;
  }
  console.log(`  kappa ${kappa.toFixed(3)}（兩欄各自獨立時預期不一致 ${exp.toFixed(2)} 條，實測 ${n - agree} 條）`);
  console.log(`  ${m} 條的方向 ${b01} 對 ${b10}，McNemar 雙尾 p = ${p.toFixed(4)}`);
}
