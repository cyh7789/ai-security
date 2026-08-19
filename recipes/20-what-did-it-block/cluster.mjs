// 缺 reason_code 的那一格才輪到分群。這支就跑在那一格上。
//
//   node cluster.mjs [門檻]        預設 0.5
//
// recipe 18 那 252 列理由沒有任何 code，是純自由文字，正好是這篇說的
// 「你不知道要找什麼」的位置。把它們照相似度堆起來，看會堆成幾堆。
//
// 相似度用字元 bigram 的 Jaccard，不叫模型。三個理由：
// 一、讀者不必有金鑰就跑得動；二、同樣的輸入永遠給同樣的群，
// 三、它比 embedding 粗糙得多，所以「連它都看得出這些是同一件事」比較有力。
// 真的要上線做這件事會用 embedding 或直接叫模型，那時候記得那一次歸類本身也會抖。
//
// 這支自己帶一個可以證偽的預測，寫在下面 EXPECT：
// 分群如果有效，benign 那臂（五條輸入）應該堆出大約五堆，
// evade 那臂（一條輸入）應該堆出很少堆。堆數跟輸入條數對不起來，
// 就是這個方法沒用，而不是資料有問題。
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const RUNS = join(HERE, "../18-not-a-free-chatgpt/runs");
const TH = Number(process.argv[2] ?? 0.5);

function tsv(path) {
  const lines = readFileSync(path, "utf8").trim().split("\n").filter(Boolean);
  const head = lines[0].split("\t");
  return { head, rows: lines.slice(1).map((l) => Object.fromEntries(l.split("\t").map((v, i) => [head[i], v]))) };
}

const byArm = new Map();
const inputs = new Map();
for (const d of readdirSync(RUNS).sort()) {
  const dir = join(RUNS, d);
  if (!statSync(dir).isDirectory()) continue;
  for (const f of readdirSync(dir).sort()) {
    if (!f.endsWith(".tsv")) continue;
    const { head, rows } = tsv(join(dir, f));
    if (!head.includes("outreason")) continue;
    for (const r of rows) {
      const reason = (r.outreason ?? "").trim();
      if (!reason) continue;
      const arm = r.armname ?? "-";
      if (!byArm.has(arm)) byArm.set(arm, new Set());
      byArm.get(arm).add(reason);
      if (!inputs.has(arm)) inputs.set(arm, r.requests ?? "?");
    }
  }
}

// 字元 bigram 的 Jaccard。中文沒有空白可以切詞，bigram 是最省事又夠用的做法。
function grams(s) {
  const t = s.replace(/[，。、；：（）「」\s]/g, "");
  const g = new Set();
  for (let i = 0; i + 1 < t.length; i += 1) g.add(t.slice(i, i + 2));
  return g;
}
function jaccard(a, b) {
  let hit = 0;
  for (const x of a) if (b.has(x)) hit += 1;
  return hit / (a.size + b.size - hit);
}

// 單連結聚合，走 union-find。
//
// 第一版不是這樣寫的，它逐筆掃、找到第一個有成員夠像的群就塞進去然後 break。
// 那個寫法有兩個問題：A 接 B、B 接 C 而 A 不接 C 的時候三者不會併成一群，
// 而且結果會隨輸入順序改變。名字叫單連結、行為不是，那比沒做還糟，
// 因為報出來的堆數看起來像實驗結果（8/19 外審抓到，數字全部重跑過）。
//
// 挑單連結是因為它最容易把東西併在一起，也就是最容易讓「這些是同一件事」成立。
// 用一個偏向自己結論的方法，是為了讓「連它都分不出來」這句話說得比較保守。
function cluster(items, th) {
  const gs = items.map(grams);
  const parent = items.map((_, i) => i);
  const find = (x) => {
    while (parent[x] !== x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  };
  const union = (a, b) => {
    const ra = find(a);
    const rb = find(b);
    if (ra !== rb) parent[rb] = ra;
  };
  for (let i = 0; i < items.length; i += 1) {
    for (let j = i + 1; j < items.length; j += 1) {
      if (jaccard(gs[i], gs[j]) >= th) union(i, j);
    }
  }
  const byRoot = new Map();
  for (let i = 0; i < items.length; i += 1) {
    const r = find(i);
    if (!byRoot.has(r)) byRoot.set(r, []);
    byRoot.get(r).push(i);
  }
  return [...byRoot.values()];
}

console.log(`門檻 ${TH}（字元 bigram 的 Jaccard，單連結）`);
console.log("臂\t輸入\t不同理由\t堆數");
const rows = [];
for (const arm of [...byArm.keys()].sort()) {
  const items = [...byArm.get(arm)];
  const g = cluster(items, TH);
  rows.push([arm, inputs.get(arm), items.length, g.length]);
  console.log(`${arm}\t${inputs.get(arm)}\t${items.length}\t${g.length}`);
}

console.log("");
console.log("== 預測對不對 ==");
const b = rows.find((r) => r[0] === "benign");
const e = rows.find((r) => r[0] === "evade");
console.log(`benign：${b[1]} 條輸入、${b[2]} 種理由，堆成 ${b[3]} 堆`);
console.log(`evade ：${e[1]} 條輸入、${e[2]} 種理由，堆成 ${e[3]} 堆`);
const ok = Number(b[3]) >= 2 && Number(b[3]) <= 12 && Number(e[3]) <= Number(b[3]);
console.log(ok
  ? "堆數跟輸入條數的方向對得上：多條輸入堆得多、單條輸入堆得少。"
  : "堆數跟輸入條數對不起來，這個分群方法在這批資料上沒有用，不要拿它的結論去講事情。");
