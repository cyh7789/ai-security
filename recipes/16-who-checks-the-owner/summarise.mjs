// 把 results.tsv 收成一張表，外加主比較的 p 值。
//
//   node summarise.mjs results.tsv
//
// 壞掉的那幾份（自己的單子都拿不到）不算進分母，但要印出來。
// 把它們塞進「有綁身分」那格是最容易發生的假好消息。
import { readFileSync } from "node:fs";

const file = process.argv[2] || "results.tsv";
const rows = readFileSync(file, "utf8").trim().split("\n").slice(1)
  .map((l) => l.split("\t"))
  .map(([order, arm, run, verdict, code, flagged, why]) =>
    ({ order, arm, run, verdict, code, flagged, why }));

const arms = [...new Set(rows.map((r) => r.arm))];
const tally = (a) => {
  const mine = rows.filter((r) => r.arm === a);
  const usable = mine.filter((r) => r.verdict !== "broken");
  return {
    bound: usable.filter((r) => r.verdict === "bound").length,
    leak: usable.filter((r) => r.verdict === "leak").length,
    n: usable.length,
    broken: mine.length - usable.length,
    flagged: mine.filter((r) => r.flagged === "yes").length,
  };
};

console.log("組\t綁了身分\t沒綁\t可用發數\t壞掉\t掃到危險呼叫");
const t = {};
for (const a of arms) {
  t[a] = tally(a);
  console.log([a, t[a].bound, t[a].leak, t[a].n, t[a].broken, t[a].flagged].join("\t"));
}

// 主比較是動筆前就鎖定的 bare 對 owned。第三組只印上面那張表，不進這裡。
if (t.bare && t.owned) {
  const p = fisher(t.owned.bound, t.owned.n - t.owned.bound, t.bare.bound, t.bare.n - t.bare.bound);
  console.log(
    `\n主比較（動筆前鎖定）：owned ${t.owned.bound}/${t.owned.n} 對 bare ${t.bare.bound}/${t.bare.n}` +
    `，Fisher 精確檢定雙尾 p=${p.toFixed(4)}`,
  );
}

// 擋下來的時候回什麼碼。這一欄比「有沒有擋住」更會分岔，所以逐組印。
// 403 跟 404 的差別不是風格：403 等於承認那筆資料存在。
const codes = {};
for (const r of rows.filter((x) => x.verdict === "bound")) codes[r.code] = (codes[r.code] || 0) + 1;
if (Object.keys(codes).length) {
  console.log("\n擋下來那幾份回的狀態碼：" +
    Object.entries(codes).sort((a, b) => b[1] - a[1]).map(([c, n]) => `${c} 共 ${n} 份`).join("、"));
  console.log("\n組\t403\t404\t其他");
  for (const a of arms) {
    const mine = rows.filter((r) => r.arm === a && r.verdict === "bound");
    const n = (c) => mine.filter((r) => r.code === c).length;
    console.log([a, n("403"), n("404"), mine.length - n("403") - n("404")].join("\t"));
  }
}

function fisher(a, b, c, d) {
  const n = a + b + c + d;
  const p = (a, b, c, d) => (C(a + b, a) * C(c + d, c)) / C(n, a + c);
  const obs = p(a, b, c, d);
  let tot = 0;
  for (let i = 0; i <= Math.min(a + b, a + c); i++) {
    const j = a + b - i, k = a + c - i, l = c + d - k;
    if (j < 0 || k < 0 || l < 0) continue;
    const q = p(i, j, k, l);
    if (q <= obs + 1e-12) tot += q;
  }
  return tot;
}
function C(n, k) {
  if (k < 0 || k > n) return 0;
  let r = 1;
  for (let i = 1; i <= k; i++) r = (r * (n - k + i)) / i;
  return Math.round(r);
}
