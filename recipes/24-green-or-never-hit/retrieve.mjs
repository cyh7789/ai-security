// R11 的起點。recipe 23 量到這一列的時候寫的是「沒驗過」，理由是
// 「客服 bot 現在沒有接檢索，這條路徑的起點還不存在」（23/surface.tsv）。
// 沒有起點就生不出攻擊變體，所以今天先把最小的起點蓋起來。
//
//   node retrieve.mjs --q 出差報帳
//   node retrieve.mjs --q 出差報帳 --gate both     # 檢索段落也送進 length 與 scenario
//   PROMPT_FILE=/tmp/p.txt node retrieve.mjs --q 出差報帳
//
// 印一行 TSV：查詢、命中幾段、命中的來源、閘的範圍、輸入側判決、檢索段落判決、
// 有沒有到模型、輸出側判決、停在哪。
//
// 這支蓋的是「最小的檢索」，不是一個像樣的 RAG：關鍵字比對、不排序、不切塊、
// 不算相似度。那些都會改變命中哪一段，但改變不了這一列要問的事：
// 檢索回來的段落用什麼路徑進到模型眼前，以及輸入側那三道閘看不看得到它。
//
// 知識庫直接讀 recipe 13 那一份，不在這裡抄。抄一份的話，13 那邊改了這裡不會跟著變，
// 而這一列量到的東西就不再是那個知識庫（recipe 21 立的規矩，同一條）。
import { readFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { GATES, resetRate } from "../18-not-a-free-chatgpt/gates.mjs";
import { classify } from "../18-not-a-free-chatgpt/classify.mjs";

const KB = new URL("../13-who-wrote-your-knowledge-base/demo/kb.jsonl", import.meta.url);
const ORDER = ["rate", "length", "scenario"];

// 使用者打的那句話。跟 23/intake.mjs 的 TYPED 同一個性質：它本身完全正常。
// 這一列的重點是「使用者沒有貼任何東西」，內容是系統自己撈回來的。
export const TYPED = "出差報帳要準備什麼？";

const argv = process.argv.slice(2);
const arg = (k, d) => {
  const i = argv.indexOf(k);
  return i >= 0 ? argv[i + 1] : d;
};

const scope = arg("--gate", "typed");
if (!["typed", "both"].includes(scope)) {
  console.error("--gate 只有 typed 與 both");
  process.exit(2);
}
const q = arg("--q", "出差報帳");

// 一行一個 JSON 物件，要有 text 跟 source。壞掉的行不要靜靜跳過：
// 跳過的話「檢索不到」跟「知識庫壞了」在輸出上長得一模一樣。
export function retrieve(query, kbUrl = KB) {
  const hits = [];
  const lines = readFileSync(kbUrl, "utf8").split("\n");
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (!line.trim()) continue;
    let r;
    try {
      r = JSON.parse(line);
    } catch {
      console.error(`知識庫第 ${i + 1} 行不是合法 JSON。這一跑不算數。`);
      process.exit(2);
    }
    const src = r.source ?? r.metadata?.source ?? null;
    if (typeof r.text !== "string") {
      console.error(`知識庫第 ${i + 1} 行沒有 text 欄。`);
      process.exit(2);
    }
    if (r.text.includes(query)) hits.push({ id: r.id, source: src, text: r.text.trim() });
  }
  return hits;
}

export function runGates(text, user = "u1") {
  for (const g of ORDER) {
    const r = GATES[g](g === "rate" ? user : text);
    if (!r.allow) return { allow: false, gate: g, code: r.code, reason: r.reason };
  }
  return { allow: true, gate: "-", code: "PASS", reason: "三道全過" };
}

// 檢索段落怎麼進上下文：接在使用者那句話後面，一段一個標頭。
// 標頭寫得出來源是因為知識庫那一欄本來就有，不是這一支加工的。
export function buildPrompt(system, typed, hits) {
  const body = hits.map((h) => `[知識庫 ${h.source ?? "來源不明"}]\n${h.text}`).join("\n\n");
  return `${system}\n\n使用者：${typed}\n\n${body}`;
}

function ask(prompt, cmd) {
  return new Promise((resolve, reject) => {
    const p = spawn("bash", ["-c", cmd], { stdio: ["pipe", "pipe", "inherit"] });
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.on("error", reject);
    p.on("close", (c) => (c === 0 ? resolve(out.trim()) : reject(new Error(`模型離開碼 ${c}`))));
    p.stdin.end(prompt);
  });
}

async function main() {
  resetRate();
  const cmd = process.env.MODEL_CMD ?? "bash ../18-not-a-free-chatgpt/stub-model.sh";
  const ccmd = process.env.CLASSIFY_CMD ?? cmd;
  const system = readFileSync(
    new URL("../18-not-a-free-chatgpt/prompts/system.txt", import.meta.url),
    "utf8",
  ).trim();

  const hits = retrieve(q);
  // 零命中在跑閘之前就判掉。放在閘後面的話，哪天輸入側收緊到會擋掉 TYPED，
  // 這一發會印「檢索一段都沒命中」而真相是被閘擋住了，正好是這一天要分開的兩件事。
  if (hits.length === 0) {
    process.stdout.write([q, 0, "-", scope, "-", "-", "no", "n/a", "沒打到:檢索一段都沒命中"].join("\t") + "\n");
    return;
  }
  // 把量到的是哪一份知識庫印出來。抄一份到本地再改路徑的話，這一行會跟著變，
  // 而「有沒有抄」用讀原始碼是驗不出來的：程式碼裡寫著什麼跟它跑的時候讀了什麼是兩件事。
  console.error(`知識庫：${fileURLToPath(KB)}`);
  const typedVerdict = runGates(TYPED);

  // both 的時候檢索段落走同一組閘。rate 在上一行用掉了，這裡只問內容那兩道，
  // 不然同一次對話會被自己的頻率閘算成兩次（跟 23/intake.mjs 同一個理由）。
  let kbVerdict = { allow: true, gate: "-", code: "NOT_GATED", reason: "檢索段落不在閘的範圍內" };
  if (scope === "both") {
    const joined = hits.map((h) => h.text).join("\n\n");
    for (const g of ["length", "scenario"]) {
      const r = GATES[g](joined);
      kbVerdict = r.allow
        ? { allow: true, gate: "-", code: r.code, reason: r.reason }
        : { allow: false, gate: g, code: r.code, reason: r.reason };
      if (!r.allow) break;
    }
  }

  const blocked = !typedVerdict.allow || !kbVerdict.allow;
  let stopped = blocked ? `閘:${typedVerdict.allow ? kbVerdict.gate : typedVerdict.gate}` : "";
  let out = { verdict: "n/a", reason: "沒有東西送到模型" };
  const prompt = buildPrompt(system, TYPED, hits);

  if (!blocked) {
    // 這一列量到的終點是「進到模型的上下文」，所以證據是這一份 prompt 本身。
    // 後面那兩步照樣跑，是為了讓這一列跟 23/intake.mjs 印得出同一種形狀的行。
    if (process.env.PROMPT_FILE) {
      const { writeFileSync } = await import("node:fs");
      writeFileSync(process.env.PROMPT_FILE, prompt);
    }
    const reply = await ask(prompt, cmd);
    out = await classify(reply, ccmd);
    stopped = out.verdict === "ok" ? "抵達交付邊界" : "閘:classify";
  }

  process.stdout.write(
    [
      q,
      hits.length,
      hits.map((h) => h.source ?? "-").join(","),
      scope,
      typedVerdict.allow ? "allow" : `deny(${typedVerdict.code})`,
      kbVerdict.allow ? `allow(${kbVerdict.code})` : `deny(${kbVerdict.code})`,
      blocked ? "no" : "yes",
      out.verdict,
      stopped,
    ].join("\t") + "\n",
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main();
