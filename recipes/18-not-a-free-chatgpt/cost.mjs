// 成本軸：同樣是一次請求，達輸入上限的那筆比典型的那筆貴幾倍。
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
const worst = PREFIX + LIMITS.maxChars;   // 長度檢查只量使用者那段，所以上限之外還要加前綴
// ⚠️ 這是「一分鐘典型輸入量」，不是系統的一分鐘額度。
// 檢查真正允許的一分鐘最壞量是 worst * perMinute，兩者差很多（2396 對 41920）。
// 8/17 外部評審抓到：把 normal*perMinute 叫成「額度」，會讓下面那個比值
// 讀起來像安全上界，它其實是流量異常指標。兩個都印，名稱各自寫清楚。
const typicalMin = normal * LIMITS.perMinute;
const worstMin = worst * LIMITS.perMinute;

const SYSN = cp(SYSTEM);
console.log(`固定前綴\t${PREFIX} 字（系統提示 ${SYSN} 字，加上兩個換行與「使用者：」那個標籤）`);
console.log(`示範素材平均\t${ask.toFixed(1)} 字（${rows.length} 句實測），整筆 ${normal.toFixed(1)} 字`);
console.log(`達輸入上限的一筆\t使用者 ${LIMITS.maxChars} 字，整筆 ${worst} 字`);
console.log(`單筆比值\t${(worst / normal).toFixed(1)} 倍`);
console.log(`一分鐘典型輸入量\t${LIMITS.perMinute} 筆 × ${normal.toFixed(1)} = ${typicalMin.toFixed(0)} 字`);
console.log(`一分鐘最壞輸入量\t${LIMITS.perMinute} 筆 × ${worst} = ${worstMin} 字（這才是檢查允許的上界）`);
console.log(`達上限一筆／典型分鐘\t${(worst / typicalMin).toFixed(2)}（異常流量指標，不是安全上界）`);
console.log(`達上限一筆／最壞分鐘\t${(worst / worstMin).toFixed(2)}（必然是 1/${LIMITS.perMinute}）`);
console.log(
  `\n次數那道檢查把這兩筆算成一樣的一次，而它們差 ${(worst / normal).toFixed(1)} 倍。` +
    `\n上面那個 ${(worst / typicalMin).toFixed(2)} 是拿典型分鐘當分母，它是流量異常指標；` +
    `\n檢查真正允許的一分鐘上界是 ${worstMin} 字，要壓成本得另外限輸出長度、同時數與總花費。`,
);
