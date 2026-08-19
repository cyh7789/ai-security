// 有了紀錄之後怎麼看。這支交的是程序，不是結論。
//
//   node triage.mjs [journal.tsv]
//
// 順序只有一個答案，因為每一步都在替下一步縮小範圍：
//
//   一、先按判斷點與判準版本切片。跨版本加總是把兩把不同的尺量出來的數字相加，
//       那個總和不對應任何東西。這支腳本遇到多版本會分開列、不加總。
//   二、切片裡面用 reason_code 計數。它是判斷點自己吐出來的短碼，
//       同一個分支永遠是同一個字串，數得動。
//   三、**有 code 不等於這一筆不用看。** code 只說得出它走到哪個程式分支，
//       說不出那個決定對不對。這支的第一版把「有 code」當成「已知情境」，
//       於是有 code 的全部不進人工佇列，而 Day 20 自己找到的那條誤擋
//       （防詐宣導，code 是 SCOPE_BLOCK，看起來再正常不過）就永遠不會被撈出來。
//       用這個 recipe 教的方法找不到這個 recipe 自己找到的東西，那方法就是錯的
//       （8/19 外審抓到）。
//       所以：沒有 code 的全部進候選；有 code 的照樣要抽樣覆核，
//       而且量大的那幾個 code 要在同一個 code 裡面再看有沒有次分類。
//   四、分群的結果是候選，不是判決。哪一筆算誤擋、哪一筆算漏網由人定，
//       判準是 Day 14 自己寫下的成功條件。交給模型判等於讓防線自己打自己的成績。
//
// 第三步是這個 recipe 最想講的一句。把全部理由丟給 AI 分群，看起來很像在做事，
// 實際上你會拿到一堆「模型換了措辭的同一句話」堆成的群；而只看有沒有 code
// 就決定要不要覆核，你會漏掉那些「分支對、判斷錯」的整類問題。
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { readJournal } from "./journal.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
// 標注清單是人寫的那一份，triage 只讀不寫。它存在的意義就是回答
// 「這個決定對不對」，那件事 reason_code 答不出來。
const labels = readFileSync(process.env.TRIAGE_LABELS || join(HERE, "labels.tsv"), "utf8")
  .split("\n")
  .filter((l) => l && !l.startsWith("#") && !l.startsWith("id\t"))
  .map((l) => {
    const c = l.split("\t");
    // 人工標注本身也有版本。判準改了，舊版本的「誤擋」不能自動繼承到新版本，
    // 所以比對的鑰匙要帶上判斷點、判準版本與當時的判決，不能只有輸入指紋
    // （8/19 外審抓到：只比 digest 的話，同一句話在新判準下被正確放行，
    // 舊版那個「誤擋」標籤照樣會黏上去）。
    return { id: c[0], digest: c[1], point: c[2], policy_version: c[3], decision: c[4], verdict: c[5] };
  });

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

  // 有 code 的那些也要有人看。這裡只挑出「該去看」的兩種，不做判斷：
  // 量最大的那個 code（誤擋通常藏在量大的分支裡，因為它是規則寫得太寬），
  // 以及已經被人標注過的那些（標注清單裡的 verdict 是人給的，不是 code 給的）。
  // 命中要用這把鑰匙，取值也要用同一把。8/19 外審抓到第一版只有命中改對了，
  // 取 verdict 的時候退回去比 digest，於是同一句話在新版被正確放行，
  // 印出來的還是舊版那個「誤擋」。改了一半比沒改更難發現。
  const keyOf = (x) => `${x.point}|${x.policy_version}|${x.digest}|${x.decision}`;
  const labelByKey = new Map(labels.map((l) => [keyOf(l), l]));
  const hit = rs.filter((r) => labelByKey.has(keyOf(r)));
  if (hit.length) {
    console.log(`  這一片裡有 ${hit.length} 筆在標注清單上，逐筆列出來（它們都有 code）：`);
    for (const r of hit) {
      const l = labelByKey.get(keyOf(r));
      console.log(`        ${r.trace_id}\t${r.reason_code}\t人判：${l.verdict}`);
    }
  }
  // 有 code 的也要抽樣，而且抽法要是決定性的：按指紋排序取前幾筆，
  // 同一批紀錄每次抽到同樣那幾筆，覆核結果才對得起來。
  const SAMPLE = Number(process.env.TRIAGE_SAMPLE ?? 2);
  const byCode = new Map();
  for (const r of rs) {
    if (!r.reason_code || r.reason_code === "-") continue;
    if (!byCode.has(r.reason_code)) byCode.set(r.reason_code, []);
    byCode.get(r.reason_code).push(r);
  }
  const ordered = [...byCode.entries()].sort((a, b) => b[1].length - a[1].length);
  if (ordered.length) {
    console.log(`  有 code 的抽樣覆核（每個 code 取 ${SAMPLE} 筆，按指紋排序，量大的排前面）：`);
    for (const [code, list] of ordered) {
      for (const r of [...list].sort((a, b) => a.digest.localeCompare(b.digest)).slice(0, SAMPLE)) {
        console.log(`        ${code}\t${r.trace_id}\t${r.digest}`);
      }
    }
  }

  if (needCluster.length) {
    console.log(`  ${String(needCluster.length).padStart(4)}　沒有 reason_code，要人看（分群只跑這一格）`);
    for (const r of needCluster.slice(0, 5)) console.log(`        ${r.digest}\t${r.reason_text}`);
  } else {
    console.log("  沒有缺 reason_code 的紀錄，這一片不需要分群。");
  }
}
