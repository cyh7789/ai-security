// 成本軸：一筆打滿長度上限的輸入，抵得上這一分鐘額度內的幾筆正常提問。
//
//   node cost.mjs
//
// 這支不打模型，算的是送進去的字數，所以每次跑出來一樣。
// 限制寫在這裡不寫在結論裡：它沒有算模型吐回來的那半，也沒有換算成任何一家的計價。
// 要的只是一個比值，證明 rate limit 那道閘管的是次數，管不到單筆多貴。
import { readFileSync } from "node:fs";
import { LIMITS } from "./gates.mjs";

const rows = readFileSync(new URL("./prompts/split.tsv", import.meta.url), "utf8")
  .split("\n")
  .filter((l) => l.trim() && !l.startsWith("#"))
  .map((l) => [...l.split("\t")[1]].length);

const avg = rows.reduce((a, b) => a + b, 0) / rows.length;
const quota = avg * LIMITS.perMinute;
const one = LIMITS.maxChars;

console.log(`正常提問平均\t${avg.toFixed(1)} 字（${rows.length} 句實測）`);
console.log(`一分鐘額度打滿\t${LIMITS.perMinute} 筆 × ${avg.toFixed(1)} = ${quota.toFixed(0)} 字`);
console.log(`單筆上限\t${one} 字`);
console.log(`比值\t${(one / quota).toFixed(2)} 倍`);
console.log(`\n一筆合法的請求，就抵得上 rate limit 放行一整分鐘的量的 ${(one / quota).toFixed(2)} 倍。`);
console.log(`把上限拉到 ${LIMITS.maxChars} 是常見的預設，而次數那道閘對這件事沒有意見。`);
