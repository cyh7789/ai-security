// 偵測規則。吃存取紀錄，吐可疑 session。
//
//   node detect.mjs logs/normal.tsv
//   node detect.mjs logs/scan.tsv --window 60 --owners 3
//
// 規則一句話：同一個 session 在 N 秒內，碰到 M 個以上不屬於自己的資源擁有者。
//
// N 跟 M 不是猜的，是拿自己那份正常紀錄調出來的：
// 取「在正常紀錄上零誤報」的最小 M。跑 calibrate.sh 會把那張表印出來。
// 換一個系統就要重調一次，因為它量的是你的正常流量長什麼樣，不是一條普世常數。
import { readFileSync } from "node:fs";

export function load(file) {
  const [head, ...lines] = readFileSync(file, "utf8").trim().split("\n");
  const cols = head.split("\t");
  return lines.filter(Boolean).map((l) => Object.fromEntries(l.split("\t").map((v, i) => [cols[i], v])));
}

export function detect(rows, { windowSec = 60, owners = 3 } = {}) {
  const bySession = new Map();
  for (const r of rows) {
    // 別人的資源才算。自己的訂單看幾張都不可疑。
    if (r.owner === "-" || r.owner === r.user) continue;
    if (!bySession.has(r.session)) bySession.set(r.session, []);
    bySession.get(r.session).push({ ts: Number(r.ts), owner: r.owner, path: r.path, status: r.status });
  }
  const hits = [];
  for (const [session, evs] of bySession) {
    evs.sort((a, b) => a.ts - b.ts);
    // 滑動視窗。用「這個 session 一共碰過幾個人」會把一整天的正常客服工作也算進來。
    for (let i = 0; i < evs.length; i++) {
      const win = evs.filter((e) => e.ts >= evs[i].ts && e.ts <= evs[i].ts + windowSec * 1000);
      const set = [...new Set(win.map((e) => e.owner))];
      if (set.length >= owners) {
        hits.push({
          session,
          owners: set,
          seconds: Math.round((win[win.length - 1].ts - win[0].ts) / 100) / 10,
          paths: win.length,
          statuses: [...new Set(win.map((e) => e.status))].sort(),
        });
        break;
      }
    }
  }
  return hits;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const file = args.find((a) => !a.startsWith("--"));
  const num = (flag, dft) => {
    const i = args.indexOf(flag);
    return i < 0 ? dft : Number(args[i + 1]);
  };
  if (!file) {
    console.error("用法：node detect.mjs <紀錄檔> [--window 60] [--owners 3]");
    process.exit(2);
  }
  const opt = { windowSec: num("--window", 60), owners: num("--owners", 3) };
  const hits = detect(load(file), opt);
  console.log(`規則：同一個 session 在 ${opt.windowSec} 秒內碰到 ${opt.owners} 個以上別人的資源`);
  if (!hits.length) {
    console.log(`${file}：沒有 session 命中`);
  } else {
    for (const h of hits) {
      console.log(
        `${file}：${h.session} 命中，${h.seconds} 秒內碰了 ${h.owners.length} 個人的資源` +
        `（擁有者 ${h.owners.join("、")}，共 ${h.paths} 次，回應 ${h.statuses.join("／")}）`,
      );
    }
  }
  process.exit(hits.length ? 1 : 0);
}
