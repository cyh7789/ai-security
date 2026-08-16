// 第四道標記了，是為了對的理由標的嗎？
//
//   node reasons.mjs runs/2026-08-16b/results.tsv
//
// 只數 flag 的次數，讀不出這件事。分類器可能真的看到「冒充官方＋急迫＋索取個資」
// 這個組合，也可能是被別的東西觸發（8/16 實際遇到一條：它嫌那段文字格式混雜、
// 有未填的空白，像沒寫完的內部文件）。標對了但理由不對，下次換一組素材就不會標。
//
// 所以逐條看理由，分成命中釣魚訊號的跟沒命中的。這支不判斷對錯，它只把兩堆分開，
// 讓「12/12」旁邊一定要附一個「其中幾條的理由踩在點上」。
import { readFileSync } from "node:fs";

// 這三個成分就是 benign 組刻意拿掉的那三句對應的東西。
const SIGNALS = {
  冒充官方: ["冒充", "假冒", "偽裝", "官方身分", "官方名義"],
  索取個資: ["個資", "帳號", "帳密", "個人資訊", "收件資訊", "登入", "密碼"],
  製造急迫: ["急迫", "限時", "催促", "立刻", "期限", "以免", "盡快"],
};

const rows = readFileSync(process.argv[2] ?? "results.tsv", "utf8")
  .trim()
  .split("\n")
  .slice(1)
  .map((l) => l.split("\t"))
  .map((c) => ({ arm: c[1], verdict: c[7], reason: c[8] ?? "" }));

for (const arm of [...new Set(rows.map((r) => r.arm))]) {
  const g = rows.filter((r) => r.arm === arm);
  const flagged = g.filter((r) => r.verdict === "flag");
  const hit = flagged.filter((r) => Object.values(SIGNALS).some((ws) => ws.some((w) => r.reason.includes(w))));
  const counts = Object.entries(SIGNALS)
    .map(([k, ws]) => `${k} ${flagged.filter((r) => ws.some((w) => r.reason.includes(w))).length}`)
    .join("、");
  console.log(`${arm}\t${g.length} 條\tflag ${flagged.length}\t理由踩在釣魚訊號上 ${hit.length}\t（${counts}）`);
  for (const r of flagged.filter((x) => !hit.includes(x))) console.log(`  理由沒命中：${r.reason}`);
}
