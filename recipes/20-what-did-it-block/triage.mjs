// 有了紀錄之後怎麼看。這支交的是程序，不是結論。
//
//   node triage.mjs [journal.tsv]
//
// 順序只有一個答案，因為每一步都在替下一步縮小範圍：
//
//   一、先按判斷點與判準版本切片。跨版本加總是把兩把不同的尺量出來的數字相加，
//       那個總和不對應任何東西。這支腳本遇到多版本會直接拒絕加總。
//   二、切片裡面用 reason_code 計數。它是判斷點自己吐出來的短碼，
//       同一個分支永遠是同一個字串，數得動。
//   三、只有 reason_code 是空的那一格，才需要把 reason_text 拿去分群。
//       那一格才是「你不知道要找什麼」的地方，也才是 AI 分群真正有用的位置。
//   四、分群的結果是候選，不是判決。哪一筆算誤擋、哪一筆算漏網由人定，
//       判準是 Day 14 自己寫下的成功條件。交給模型判等於讓防線自己打自己的成績。
//
// 第三步是這個 recipe 最想講的一句。把全部理由丟給 AI 分群，看起來很像在做事，
// 實際上你會拿到一堆「模型換了措辭的同一句話」堆成的群。
import { readJournal } from "./journal.mjs";

const path = process.argv[2];
const rows = path ? readJournal(path) : readJournal();

const slices = new Map();
for (const r of rows) {
  const k = `${r.point}\t${r.policy_version}`;
  if (!slices.has(k)) slices.set(k, []);
  slices.get(k).push(r);
}

const versionsPerPoint = new Map();
for (const k of slices.keys()) {
  const [point, ver] = k.split("\t");
  if (!versionsPerPoint.has(point)) versionsPerPoint.set(point, new Set());
  versionsPerPoint.get(point).add(ver);
}

for (const [point, vers] of versionsPerPoint) {
  if (vers.size > 1) {
    console.log(`注意：${point} 這個判斷點在這批紀錄裡有 ${vers.size} 個判準版本（${[...vers].join("、")}）。`);
    console.log("     底下分開列，不加總。要比的話是比版本之間的差異，不是把它們加起來。");
  }
}

for (const [k, rs] of [...slices.entries()].sort()) {
  const [point, ver] = k.split("\t");
  const allow = rs.filter((r) => r.decision === "allow").length;
  console.log("");
  console.log(`== ${point}　判準版本 ${ver}　共 ${rs.length} 筆（放行 ${allow}、擋下 ${rs.length - allow}）==`);

  const counts = new Map();
  const needCluster = [];
  for (const r of rs) {
    if (!r.reason_code || r.reason_code === "-") needCluster.push(r);
    else counts.set(r.reason_code, (counts.get(r.reason_code) ?? 0) + 1);
  }
  for (const [code, n] of [...counts.entries()].sort((a, b) => b[1] - a[1])) {
    console.log(`  ${String(n).padStart(4)}　${code}`);
  }
  if (needCluster.length) {
    console.log(`  ${String(needCluster.length).padStart(4)}　沒有 reason_code，要人看（分群只跑這一格）`);
    for (const r of needCluster.slice(0, 5)) console.log(`        ${r.digest}\t${r.reason_text}`);
  } else {
    console.log("  沒有缺 reason_code 的紀錄，這一片不需要分群。");
  }
}
