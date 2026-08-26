// 兩輪之間逐條配對，回答「這一欄拿來報穩不穩」。
//
//   node pair.mjs <舊 results.tsv> <新 results.tsv> <arm> <欄名>
//
// 為什麼不看總數：8/17 那兩輪 split 的 outverdict 總數是 10 對 8，只差兩條，
// 逐條配對卻有 4/12 反過來（兩個方向各兩條）。總數的差距小可以是兩邊各翻一半
// 剛好抵銷，所以「總數穩」證明不了「同一條鏈重跑會得到同一個判決」。
// 這兩個數字重跑得出來：
//   node pair.mjs runs/2026-08-17/results.tsv runs/2026-08-17b/results.tsv split outverdict
//
// run 欄是配對鍵。兩輪的 run i 送的是同一組素材，比的是同一件事重跑兩次。

import { readFileSync } from "node:fs";

const [a, b, arm, col] = process.argv.slice(2);
if (!a || !b || !arm || !col) {
  console.error("用法：node pair.mjs <舊> <新> <arm> <欄名>");
  process.exit(2);
}

const load = (p) => {
  const lines = readFileSync(p, "utf8").trim().split("\n");
  const head = lines[0].split("\t");
  const iArm = head.indexOf("arm");
  const iRun = head.indexOf("run");
  const iCol = head.indexOf(col);
  if (iArm < 0 || iRun < 0) throw new Error(`${p} 少了 arm 或 run 欄`);
  if (iCol < 0) throw new Error(`${p} 沒有 ${col} 欄`);
  const m = new Map();
  for (const line of lines.slice(1)) {
    const c = line.split("\t");
    if (c[iArm] === arm) m.set(c[iRun], c[iCol]);
  }
  return m;
};

const A = load(a);
const B = load(b);
const runs = [...A.keys()].filter((k) => B.has(k)).sort((x, y) => x - y);
if (runs.length === 0) {
  console.error(`兩輪沒有共同的 ${arm} run，配對不了`);
  process.exit(1);
}

let flipped = 0;
console.log(`arm=${arm}  欄=${col}  配得起來 ${runs.length} 條`);
for (const r of runs) {
  const same = A.get(r) === B.get(r);
  if (!same) flipped++;
  console.log(`  run ${r.padStart(2)}  ${A.get(r)} → ${B.get(r)}  ${same ? "" : "反過來"}`);
}

// 總數那一行只對判決欄有意義（數 flag 幾條）。任意欄名都寫死數 "flag"
// 會讓非判決欄一律報 0，然後印出「總數完全一樣但逐條反過來」這種跟事實相反的結論，
// 而這支工具存在的理由正是防止總數騙人。所以其他欄改印逐值分佈。
const dist = (m) => {
  const c = new Map();
  for (const v of m.values()) c.set(v, (c.get(v) ?? 0) + 1);
  return [...c.entries()].sort().map(([k, n]) => `${k}=${n}`).join(" ");
};
if (col === "outverdict") {
  const count = (m) => [...m.values()].filter((v) => v === "flag").length;
  console.log(`\n總數：舊 ${count(A)} / ${A.size}，新 ${count(B)} / ${B.size}（差 ${Math.abs(count(A) - count(B))}）`);
} else {
  console.log(`\n分佈：舊 ${dist(A)}｜新 ${dist(B)}`);
}
console.log(`逐條：${flipped} / ${runs.length} 條反過來`);
