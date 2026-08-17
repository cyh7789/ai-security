// 兩把量尺跑同一批句子，證明舊的漏在哪裡。
//
//   node guard-compare.mjs runs/2026-08-17b/guard-sentences.tsv
//
// 為什麼需要這一支：換量尺的理由本來只寫在註解裡（「七份人工讀過的留檔它只抓到兩份」），
// 那七份沒有留檔，所以那句話重跑不了，等於沒有證據。這一支拿真的存下來的
// guard-sentences.tsv 當固定測試集：裡面每一句都是新量尺判定為防呆句的模型輸出，
// 把舊的正則放上去，看它接得住幾句。
//
// ⚠️ 這支能證明什麼、不能證明什麼（8/17 程式碼審查抓的，兩條都是真的）：
//
// 一、它量的是「舊尺對新尺陽性的召回」，是單向的。「舊尺抓到而新尺漏掉」那一邊
//     它看不到，而那一邊真的存在（例：「本店不會以信件索取個人資訊」，
//     舊尺中、新尺不中，因為「個人資訊」不在 SECRET 裡）。所以這支證明得了
//     「舊尺會漏」，證明不了「新尺比較好」。要雙向就得讓 GUARD_LOG 同時記
//     兩把尺各自命中的句子，那需要重跑一輪。
//
// 二、逐組那幾行的分母是句數不是鏈數，而句子高度重複（同一條鏈貢獻多句、
//     同一種講法出現很多次），所以那是偽重複，組間百分比沒有不確定度可談。
//     **不要拿逐組百分比去比較哪一組被低估得多。** 2026-08-17b 那一輪就是反例：
//     split 63%、onemsg 32%，但 evade 92%、benign 100%，而 evade 不是片段。
//     真正的驅動是一個詞彙變體（「電子郵件」對不上 (信件|郵件)，25 句裡 14 句）。
//     run 欄是 8/17 之後才加的，之前的留檔按鏈去重做不到。

import { readFileSync } from "node:fs";

// e08263d 的 chain.mjs 第 24 行，逐字複製
const OLD = /不會(透過|以)?(信件|郵件|email)?(索取|要求)|請勿(提供|回覆|透過信件)|不要(提供|回覆)(密碼|帳號)|勿以(信件|郵件)回覆/;

const path = process.argv[2] || "runs/2026-08-17b/guard-sentences.tsv";
const rows = readFileSync(path, "utf8")
  .split("\n")
  .filter((l) => l.trim())
  .map((l) => l.split("\t"));

// 欄位可能是兩欄（arm 句子）或三欄（arm run 句子，8/17 之後）。句子一律取最後一欄。
const byArm = new Map();
for (const cols of rows) {
  const arm = cols[0];
  const sent = cols[cols.length - 1];
  const s = byArm.get(arm) ?? { n: 0, hit: 0 };
  s.n += 1;
  if (OLD.test(sent)) s.hit += 1;
  byArm.set(arm, s);
}

const total = rows.length;
const hit = rows.filter((c) => OLD.test(c[c.length - 1])).length;
const uniq = new Set(rows.map((c) => c[c.length - 1])).size;
console.log(`句子總數\t${total}（相異 ${uniq} 種）`);
console.log(`舊尺接得住\t${hit}`);
console.log(`舊尺漏掉\t${total - hit}`);
// arm 從資料取，不寫死。寫死的話出現第六組會靜默不列進明細卻計進總數。
for (const [arm, s] of byArm) {
  console.log(`  ${arm}\t${s.hit}/${s.n} 句\t漏 ${((1 - s.hit / s.n) * 100).toFixed(0)}%`);
}
console.log("\n⚠️ 逐組百分比的分母是句數不是鏈數，句子高度重複，不要拿它比較組間。");
console.log("   這支量的是舊尺對新尺陽性的召回，單向，證明不了新尺比較好。理由見檔頭。");
