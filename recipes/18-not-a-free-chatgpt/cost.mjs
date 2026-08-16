// 成本軸：同樣是一次請求，最貴的那筆比正常的那筆貴幾倍。
//
//   node cost.mjs
//
// 這支不打模型，算的是送進去的字數，所以每次跑出來一樣。
//
// 8/16 第一版把系統提示漏掉了，只數使用者打的那幾個字，算出 4.20 倍並且寫成
// 「一筆抵得上一整分鐘的量」。那是錯的，而且方向是反的：固定前綴每一次請求都送，
// 對「二十筆」的影響是對「一筆」的二十倍，補回去之後那個比值是 0.87。
// 現在兩邊都含前綴，主結論改成單筆對單筆，那才是「rate limit 管不到單筆多貴」要的東西。
//
// 還沒算的：模型吐回來的那半，以及任何一家的計價與 token 化。所以這是字數比不是帳單比。
import { readFileSync } from "node:fs";
import { LIMITS } from "./gates.mjs";

const R = (n) => new URL(`./prompts/${n}`, import.meta.url);
const cp = (s) => [...s].length;

// chain.mjs 每一次請求送的是 `${SYSTEM}\n\n使用者：${text}`，所以前綴是固定成本。
const SYSTEM = readFileSync(R("system.txt"), "utf8").trim();
const PREFIX = cp(`${SYSTEM}\n\n使用者：`);

const rows = readFileSync(R("split.tsv"), "utf8")
  .split("\n")
  .filter((l) => l.trim() && !l.startsWith("#"))
  .map((l) => cp(l.split("\t")[1]));

const ask = rows.reduce((a, b) => a + b, 0) / rows.length;
const normal = PREFIX + ask;              // 一筆正常請求實際送出去的字
const worst = PREFIX + LIMITS.maxChars;   // 長度閘只量使用者那段，所以上限之外還要加前綴
const quota = normal * LIMITS.perMinute;  // 一分鐘額度打滿

console.log(`固定前綴\t${PREFIX} 字（系統提示，每一次請求都送）`);
console.log(`正常提問平均\t${ask.toFixed(1)} 字（${rows.length} 句實測），整筆 ${normal.toFixed(1)} 字`);
console.log(`最貴的一筆\t使用者 ${LIMITS.maxChars} 字，整筆 ${worst} 字`);
console.log(`單筆比值\t${(worst / normal).toFixed(1)} 倍`);
console.log(`一分鐘額度\t${LIMITS.perMinute} 筆 × ${normal.toFixed(1)} = ${quota.toFixed(0)} 字`);
console.log(`最貴那筆佔一分鐘\t${(worst / quota).toFixed(2)}`);
console.log(
  `\n次數那道閘把這兩筆算成一樣的一次，而它們差 ${(worst / normal).toFixed(1)} 倍。` +
    `\n這兩個設定是綁在一起的：以現在的 ${LIMITS.perMinute} 次與 ${LIMITS.maxChars} 字，` +
    `最貴的一筆是一整分鐘額度的 ${(worst / quota).toFixed(2)}，` +
    `\n所以「每分鐘 ${LIMITS.perMinute} 次」給你的那個上限，實際值由長度上限決定。`,
);
