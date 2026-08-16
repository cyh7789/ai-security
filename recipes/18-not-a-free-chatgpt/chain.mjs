// 一整條鏈跑一次：每一句過前三道閘，過得了的送模型，收回來的拼起來過第四道。
//
//   node chain.mjs --arm split     # 五句分次問
//   node chain.mjs --arm direct    # 同一個目標，一句話直接要求（反向控制）
//
// 印三樣：問了哪幾句、輸入側逐關的判決、輸出側的判決與理由。
// 組合後的全文不印、不落檔，只在記憶體裡走到第四道那顆分類器面前。
// 讀者要學的是「逐句都放行、合起來才是那個東西」這個落差，不是那封信長怎樣。
import { readFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { GATES, resetRate } from "./gates.mjs";
import { classify } from "./classify.mjs";

const ORDER = ["rate", "length", "scenario"]; // 便宜的先擋，貴的後面
const SYSTEM = readFileSync(new URL("./prompts/system.txt", import.meta.url), "utf8").trim();

function loadArm(arm) {
  const txt = readFileSync(new URL(`./prompts/${arm}.tsv`, import.meta.url), "utf8");
  return txt
    .split("\n")
    .filter((l) => l.trim() && !l.startsWith("#"))
    .map((l) => {
      const [id, text] = l.split("\t");
      return { id, text };
    });
}

function ask(text, cmd) {
  return new Promise((resolve, reject) => {
    const p = spawn("bash", ["-c", cmd], { stdio: ["pipe", "pipe", "inherit"] });
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.on("error", reject);
    p.on("close", (c) => (c === 0 ? resolve(out.trim()) : reject(new Error(`模型離開碼 ${c}`))));
    p.stdin.end(`${SYSTEM}\n\n使用者：${text}`);
  });
}

const arm = process.argv[process.argv.indexOf("--arm") + 1] ?? "split";
const user = process.env.CHAIN_USER ?? "u1";
const cmd = process.env.MODEL_CMD ?? "bash stub-model.sh";
const ccmd = process.env.CLASSIFY_CMD ?? cmd; // 第四道那顆，預設跟客服助理同一支（罐頭用）

resetRate();
const rows = loadArm(arm);
const pieces = [];
let blocked = 0;
const err = (s) => process.stderr.write(`${s}\n`);

err(`\n  ── 輸入側三道閘（${arm}，共 ${rows.length} 句）`);
for (const { id, text } of rows) {
  let denial = null;
  for (const g of ORDER) {
    const r = GATES[g](g === "rate" ? user : text);
    if (!r.allow) {
      denial = { gate: g, reason: r.reason };
      break;
    }
  }
  if (denial) {
    blocked += 1;
    err(`  ${id}  deny   ${denial.gate}：${denial.reason}`);
    err(`        「${text}」`);
    continue;
  }
  err(`  ${id}  allow  三道全過`);
  err(`        「${text}」`);
  pieces.push(await ask(text, cmd));
}

let verdict = "n/a";
let reason = "輸入側全擋，沒有東西送到第四道";
if (pieces.length > 0) {
  // 只有這裡碰得到組合後的全文，而它到此為止：不印、不寫檔。
  ({ verdict, reason } = await classify(pieces.join("\n\n"), ccmd));
}

err(`\n  ── 輸出側第四道`);
err(`  ${verdict}\t${reason}\n`);

process.stdout.write(`${arm}\t${rows.length}\t${blocked}\t${pieces.length}\t${verdict}\t${reason}\n`);
