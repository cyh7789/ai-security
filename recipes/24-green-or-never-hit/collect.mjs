// 把 cases.tsv 收成 attacks-project.jsonl，並跟 recipe 23 的攻擊面清單對帳。
//
//   node collect.mjs            # 印到 stdout
//   node collect.mjs --write    # 寫進 attacks-project.jsonl
//   node collect.mjs --check    # 跟現有的比，不一樣就退出碼 1
//
// 為什麼另開一份而不是併進 recipe 14 的 attacks.jsonl：那一份是送進模型的
// prompt 語料，run-suite.sh 拿它去 grep 模型的回覆（14/run-suite.sh 那段
// `printf '%s' "$reply" | grep -qF -- "$mark"`），而且 carrier 不在
// build-prompt.mjs 的 HEAD 裡的整條會被過濾掉不跑。這一份的判準是程式狀態
// （那筆訂單還在不在、標記有沒有被抓回來、ownerId 是誰），跑法是 run.sh。
// 硬塞進去的話，這十二條會躺在一個它的 harness 從來不會跑到的檔案裡。
//
// 兩份各自對各自的來源。這一份的來源是 recipe 23 的 surface.tsv 加 cases.tsv。
import { readFileSync, existsSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const die = (m) => { console.error(m); process.exit(2); };

function tsv(path, why) {
  if (!existsSync(path)) die(`找不到 ${path}（${why}）`);
  const lines = readFileSync(path, "utf8").split("\n").filter((l) => l.trim() && !l.startsWith("#"));
  if (lines.length < 2) die(`${path} 只有表頭或空的`);
  const head = lines[0].split("\t");
  return lines.slice(1).map((l) => {
    const c = l.split("\t");
    // 欄數對不上多半是內文裡打了 tab。靜靜收下的話，判準那一欄會讀成備註，
    // 而整份清單看起來一切正常。
    if (c.length !== head.length) die(`${path} 有一列 ${c.length} 欄，表頭是 ${head.length} 欄：${c[0]}`);
    return Object.fromEntries(head.map((h, i) => [h, c[i]]));
  });
}

const SURFACE = join(HERE, "..", "23-what-can-actually-reach-it", "surface.tsv");
const surface = tsv(SURFACE, "recipe 23 的攻擊面清單，這一份的來源");
const cases = tsv(join(HERE, "cases.tsv"), "成功條件正本，人填的那一份");
const open = tsv(join(HERE, "open-questions.tsv"), "定不出判準的那些");

// ── 對帳一：cases.tsv 每一列的 path 要嘛在清單上，要嘛是明著新增的入口 ──
const known = new Set(surface.map((r) => r.id));
const NEW_ENTRIES = new Set(["KB-W"]); // 知識庫寫入口。規格的【接點】點名要配案例，而清單上只有檢索段落那一列
for (const c of cases) {
  if (!known.has(c.path) && !NEW_ENTRIES.has(c.path)) {
    die(`${c.case} 指到 ${c.path}，那不在 surface.tsv 上，也不在明著新增的入口裡`);
  }
}

// ── 對帳二：清單上標「是．」的每一列，都要配到案例或掛在 open-questions 上 ──
// 這條是這支存在的主要理由。少了它，一條路徑可以無聲無息地從清單掉出去：
// surface.tsv 上寫著「是．本日主線」，而今天的攻擊集裡一條都沒有。
// path 那一欄是明著填的，不從散文撈。第一版拿 /R\d+/ 去 match 來源欄，
// R11 那一列的來源寫的是「24/retrieve.mjs」，撈不到，於是 R11 靜靜地
// 從涵蓋清單掉出去（這支第一次跑就咬到了，所以那一格不是裝飾）。
const covered = new Set([...cases.map((c) => c.path), ...open.map((q) => q.path)]);
const missing = surface.filter((r) => r.Day24出案例?.startsWith("是") && !covered.has(r.id)).map((r) => r.id);
if (missing.length) die(`清單上標「是」卻一條案例都沒有：${missing.join("、")}`);

// ── 對帳三：至少一條已知會被打穿的基線案例（規格的硬性要求）──
const baseline = cases.filter((c) => c.期望 === "擋" && c.現在 === "沒擋");
if (!baseline.length) die("一條基線案例都沒有。一份全綠的攻擊集分不出防得住跟沒打到。");

// ── 對帳四：「期望」只有兩個值 ──
// 加第三個值的那一天，就是這份清單開始收留「永遠不紅也不綠」的列的那一天。
for (const c of cases) {
  if (!["擋", "可接受"].includes(c.期望)) die(`${c.case} 的期望是「${c.期望}」，只有「擋」與「可接受」`);
  if (!["擋住", "沒擋"].includes(c.現在)) die(`${c.case} 的現在是「${c.現在}」，只有「擋住」與「沒擋」`);
}

const rows = cases.map((c) => ({
  id: c.case,
  path: c.path,
  one: c.一句話,
  expect: c.期望,
  oracle: c["判準看哪個可觀察的東西"],
  now: c.現在,
  baseline: c.期望 === "擋" && c.現在 === "沒擋",
  note: c.備註,
}));

const out = rows.map((r) => JSON.stringify(r)).join("\n") + "\n";
const target = join(HERE, "attacks-project.jsonl");

if (process.argv.includes("--write")) {
  writeFileSync(target, out);
  console.error(`寫了 ${rows.length} 條到 attacks-project.jsonl，其中 ${baseline.length} 條是基線案例`);
} else if (process.argv.includes("--check")) {
  const cur = existsSync(target) ? readFileSync(target, "utf8") : "";
  if (cur === out) {
    console.log(`attacks-project.jsonl 跟來源一致，${rows.length} 條，基線 ${baseline.length} 條`);
  } else {
    console.error("attacks-project.jsonl 跟來源分岔了。跑 node collect.mjs --write 重收。");
    process.exit(1);
  }
} else {
  process.stdout.write(out);
}
