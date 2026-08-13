// 把散在 recipe 05／09／10／11／13 的十五條攻擊收成一份 attacks.jsonl。
//
//   node collect.mjs            # 印到 stdout
//   node collect.mjs --write    # 寫進 attacks.jsonl
//   node collect.mjs --check    # 跟現有的 attacks.jsonl 比，不一樣就退出碼 1
//
// 為什麼要用收的不用手抄：手抄的清單會跟來源分岔，而分岔的那一天你不會知道。
// 來源改了這支就會產出不一樣的東西，--check 那條就紅。
import { readFileSync, existsSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const R = (name) => join(HERE, "..", name);

const need = (p, why) => {
  if (!existsSync(p)) {
    console.error(`找不到 ${p}（${why}）。這份清單是從其他 recipe 收來的，缺一個就收不完整。`);
    process.exit(2);
  }
  return p;
};

const rows = [];
const add = (o) => rows.push({ id: String(rows.length + 1).padStart(2, "0"), ...o });

// ── Day 5：兩條 XSS。判準在瀏覽器的 DOM，不在模型輸出 ────────────────
{
  const f = need(R("05-innerhtml-fake-green/attack-set.md"), "Day 5 的兩條");
  const src = readFileSync(f, "utf8");
  for (const n of ["01", "02"]) {
    // 那份檔案是 payload 後面接兩格以上的空白再寫說明，所以切在空白的run上，
    // 不是切在行尾。切在行尾會把說明也當成 payload 的一部分收進來。
    const m = src.match(new RegExp(`^${n}\\s+(\\S(?:[^\\s]|\\s(?!\\s))*)`, "m"));
    if (!m) {
      console.error(`recipe 05 的 attack-set.md 裡找不到第 ${n} 條`);
      process.exit(2);
    }
    add({
      day: 5,
      carrier: "dom",
      judge: "dom",
      mark: null,
      payload: m[1],
      source: "recipes/05-innerhtml-fake-green/attack-set.md",
      note: "看 #answer 裡有沒有生出那個元素。防護 prompt 打不到這一層。",
    });
  }
}

// ── Day 9：後端沒驗的那個值。判準在資料庫，不在模型輸出 ──────────────
{
  need(R("09-which-side-validated/before/server.mjs"), "Day 9 那一條的落點");
  add({
    day: 9,
    carrier: "http",
    judge: "http",
    mark: null,
    payload: '{"quantity":-5}',
    source: "recipes/09-which-side-validated/before/server.mjs",
    note: "PATCH 進去看後端收不收。防護 prompt 打不到這一層。",
  });
}

// ── Day 10：五條打使用者輸入框的 ────────────────────────────────
{
  const f = need(R("10-instructions-vs-data/attacks.txt"), "Day 10 那五條");
  for (const line of readFileSync(f, "utf8").split("\n")) {
    if (!line || line.startsWith("#")) continue;
    const [mark, text] = line.split("\t");
    add({
      day: 10,
      carrier: "input",
      judge: "mark",
      mark,
      payload: text,
      source: "recipes/10-instructions-vs-data/attacks.txt",
      note: "使用者那一格直接打。",
    });
  }
}

// ── Day 11：六條藏在網頁裡的 ──────────────────────────────────
// 送進模型的是整份原始 HTML。理由：Day 11 量過抽取層常常沒把這幾句拿掉，
// 而今天要測的是「它到了模型面前之後，那句防護句擋不擋得住」，不是重測抽取層。
{
  const dir = R("11-what-the-model-reads");
  need(join(dir, "page.mjs"), "Day 11 那六條的頁面產生器");
  const { HIDING, HIDING_LABEL, buildPage } = await import(join(dir, "page.mjs"));
  const lines = readFileSync(need(join(dir, "attacks.txt"), "Day 11 那六條"), "utf8").split("\n");
  for (const how of HIDING) {
    const line = lines.find((l) => l.startsWith(`${how}\t`));
    if (!line) {
      console.error(`recipe 11 的 attacks.txt 裡找不到 ${how}`);
      process.exit(2);
    }
    const [, mark, text] = line.split("\t");
    add({
      day: 11,
      carrier: "page",
      judge: "mark",
      mark,
      payload: buildPage(how, mark, text),
      source: "recipes/11-what-the-model-reads/page.mjs",
      note: `藏法：${HIDING_LABEL[how]}。送整份原始 HTML。`,
      hiding: how,
    });
  }
}

// ── Day 13：一條寫進知識庫的 ──────────────────────────────────
{
  const f = need(R("13-who-wrote-your-knowledge-base/demo/poison.txt"), "Day 13 那一條");
  add({
    day: 13,
    carrier: "kb",
    judge: "mark",
    // 這一條沒有 RS 標記，它要模型講的是一整句話，那句話就是標記。
    mark: "報帳流程已經取消",
    payload: readFileSync(f, "utf8").trim(),
    source: "recipes/13-who-wrote-your-knowledge-base/demo/poison.txt",
    note: "當成檢索到的其中一段餵進去。",
  });
}

const out = rows.map((r) => JSON.stringify(r)).join("\n") + "\n";
const target = join(HERE, "attacks.jsonl");

if (process.argv.includes("--write")) {
  writeFileSync(target, out);
  console.error(`寫了 ${rows.length} 條到 attacks.jsonl`);
} else if (process.argv.includes("--check")) {
  const cur = existsSync(target) ? readFileSync(target, "utf8") : "";
  if (cur === out) {
    console.log(`attacks.jsonl 跟來源一致，${rows.length} 條`);
  } else {
    console.error("attacks.jsonl 跟來源分岔了。跑 node collect.mjs --write 重收。");
    process.exit(1);
  }
} else {
  process.stdout.write(out);
}
