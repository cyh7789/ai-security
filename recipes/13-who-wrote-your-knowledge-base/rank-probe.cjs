#!/usr/bin/env node
// 丟一份自己造的文件進語料，看它排第幾、進不進得了送給模型的那幾段。
//
//   node rank-probe.cjs demo/corpus --ask "報帳要準備什麼" --poison demo/poison.txt
//   node rank-probe.cjs demo/corpus --ask "報帳要準備什麼" --poison demo/poison.txt --top 3
//   node rank-probe.cjs demo/corpus --ask "..." --poison ... --embed http://localhost:11434/v1/embeddings
//
// ⚠️ 預設用的是**字面相似度**（字元二元組的 TF-IDF 餘弦），不是語意。
// 換句話說：同義詞它看不出來，這支會低估。
// 它要示範的是「排序」這件事：檢索按分數排，而分數是文字算出來的，
// 文字是攻擊者寫的。這一點在字面和語意兩邊一樣成立。
// 手上有本機 embedding 端點（Ollama 那種 OpenAI 相容的）就接 --embed，那條走真的語意。

const fs = require("fs");
const path = require("path");

const argv = process.argv.slice(2);
const TAKES_VALUE = new Set(["--ask", "--poison", "--top", "--embed", "--embed-model"]);
const opts = {};
const positional = [];
for (let i = 0; i < argv.length; i++) {
  if (TAKES_VALUE.has(argv[i])) opts[argv[i]] = argv[++i];
  else if (argv[i].startsWith("--")) opts[argv[i]] = true;
  else positional.push(argv[i]);
}
const dir = positional[0];
const ASK = opts["--ask"];
const POISON = opts["--poison"];
const TOP = parseInt(opts["--top"] ?? "10", 10);
const EMBED = opts["--embed"];
const EMBED_MODEL = opts["--embed-model"] ?? "nomic-embed-text";

function fail(msg) {
  console.error(msg);
  process.exit(2);
}

if (!dir || !ASK) fail('用法：node rank-probe.cjs <語料目錄> --ask "問題" [--poison <檔>] [--top N]');
if (!Number.isInteger(TOP) || TOP < 1) fail(`--top 要是正整數，收到 ${opts["--top"]}`);

// 走訪跟著 symlink 走，而且跳過什麼要講出來。Day 12 就是栽在 Dirent.isDirectory()
// 對「指向目錄的 symlink」回 false，整棵子樹沒進去而結束碼還是 0。
const files = [];
const skipped = [];
const seen = new Set();
function walk(d) {
  let real;
  try {
    real = fs.realpathSync(d);
  } catch (e) {
    skipped.push(`${d}（${e.code}）`);
    return;
  }
  if (seen.has(real)) return; // symlink 繞圈
  seen.add(real);
  for (const name of fs.readdirSync(d)) {
    const p = path.join(d, name);
    let st;
    try {
      st = fs.statSync(p); // 不是 lstat：statSync 會跟著 symlink 看到真正的型別
    } catch (e) {
      skipped.push(`${p}（${e.code}）`);
      continue;
    }
    if (st.isDirectory()) walk(p);
    else if (/\.(md|txt)$/i.test(name)) files.push(p);
  }
}
walk(dir);
if (files.length === 0) fail(`${dir} 底下沒有 .md 或 .txt`);

const docs = files.map((f) => ({ id: path.relative(dir, f), text: fs.readFileSync(f, "utf8"), poison: false }));
if (POISON) {
  let text;
  try {
    text = fs.readFileSync(POISON, "utf8");
  } catch (e) {
    fail(`讀不到投毒檔 ${POISON}：${e.message}`);
  }
  docs.push({ id: path.basename(POISON), text, poison: true });
}

// ── 記分：預設字面，--embed 走語意 ────────────────────────────

const bigrams = (s) => {
  const t = s.toLowerCase().replace(/\s+/g, "");
  const out = [];
  for (let i = 0; i + 1 < t.length; i++) out.push(t.slice(i, i + 2));
  return out;
};

function lexicalVectors(texts) {
  const tfs = texts.map((t) => {
    const m = new Map();
    for (const g of bigrams(t)) m.set(g, (m.get(g) || 0) + 1);
    return m;
  });
  const df = new Map();
  for (const m of tfs) for (const g of m.keys()) df.set(g, (df.get(g) || 0) + 1);
  return tfs.map((m) => {
    const v = new Map();
    for (const [g, n] of m) v.set(g, (1 + Math.log(n)) * Math.log(texts.length / df.get(g)));
    return v;
  });
}

const cosSparse = (a, b) => {
  let dot = 0;
  const [s, l] = a.size < b.size ? [a, b] : [b, a];
  for (const [k, x] of s) if (l.has(k)) dot += x * l.get(k);
  const n = (m) => Math.sqrt([...m.values()].reduce((s2, x) => s2 + x * x, 0));
  const d = n(a) * n(b);
  return d === 0 ? 0 : dot / d;
};

const cosDense = (a, b) => {
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return dot === 0 ? 0 : dot / (Math.sqrt(na) * Math.sqrt(nb));
};

async function embedAll(texts) {
  const res = await fetch(EMBED, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ model: EMBED_MODEL, input: texts }),
  });
  if (!res.ok) fail(`embedding 端點回 HTTP ${res.status}`);
  const body = await res.json();
  const arr = (body.data || []).map((d) => d.embedding);
  // 長度對不上就停。少一筆會讓後面的分數整排錯位，而排序照樣印得出來。
  if (arr.length !== texts.length) fail(`embedding 端點回了 ${arr.length} 筆，我送了 ${texts.length} 筆`);
  // 維度也要對。長短不一的向量餘弦算得出數字（短的那截直接被忽略），
  // 非數字則一路變成 NaN，兩種都會照樣印出一份排名。
  const dim = Array.isArray(arr[0]) ? arr[0].length : -1;
  arr.forEach((v, i) => {
    if (!Array.isArray(v) || v.length !== dim || v.some((x) => typeof x !== "number" || !Number.isFinite(x))) {
      fail(`第 ${i} 筆向量不合用：長度 ${Array.isArray(v) ? v.length : "非陣列"}，第一筆是 ${dim} 維`);
    }
  });
  return arr;
}

(async () => {
  const texts = [ASK, ...docs.map((d) => d.text)];
  let scores;
  if (EMBED) {
    const vs = await embedAll(texts);
    scores = docs.map((_, i) => cosDense(vs[0], vs[i + 1]));
  } else {
    const vs = lexicalVectors(texts);
    scores = docs.map((_, i) => cosSparse(vs[0], vs[i + 1]));
  }

  const ranked = docs
    .map((d, i) => ({ ...d, score: scores[i] }))
    .sort((a, b) => b.score - a.score);

  console.log(`問題：${ASK}`);
  console.log(`語料 ${docs.length} 份${POISON ? "（含 1 份你自己造的）" : ""}，${EMBED ? `語意（${EMBED_MODEL}）` : "字面相似度，不是語意"}。`);
  if (skipped.length) console.log(`跳過 ${skipped.length} 個：${skipped.join("、")}`);
  console.log(`════ 送給模型的是前 ${TOP} 名 ════`);

  ranked.slice(0, Math.max(TOP, 1)).forEach((d, i) => {
    console.log(`${String(i + 1).padStart(2)}. ${d.score.toFixed(6)}  ${d.id}${d.poison ? "  ★你造的那份" : ""}`);
  });

  if (POISON) {
    const at = ranked.findIndex((d) => d.poison);
    const cut = ranked[TOP - 1];
    console.log("");
    if (at < TOP) {
      console.log(`你造的那份排第 ${at + 1} 名，在前 ${TOP} 裡面，會被送進 prompt。`);
    } else {
      console.log(`你造的那份排第 ${at + 1} 名，沒進前 ${TOP}。`);
      console.log(`要擠進去得贏過第 ${TOP} 名的 ${cut ? cut.score.toFixed(6) : "(不足名額)"}，不是贏過第一名。`);
    }
    console.log("名次是相對的：語料越少、問題越冷門，同一份東西的名次越前面。");
  }

  // 跳過了東西就不是一次完整的排名。Day 12 的整篇結論就是「沒走到」不能算「乾淨」，
  // 這支要是印完一份漂亮的排名再回 0，它自己就是那個例子。
  if (skipped.length) {
    console.log(`\n這次跳過了 ${skipped.length} 個路徑，所以這份排名不完整。（結束碼 2）`);
    process.exit(2);
  }
})();
