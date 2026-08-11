// 印一頁帶著指令的示範內容到 stdout。不寫檔，接管線給下一支。
//
//   node page-cli.mjs comment
//   node page-cli.mjs invisible | node extract.mjs
//
// 藏法不給的話印出全部六種的名字。指令不給的話用 attacks.txt 裡對應的那一條。
import { readFileSync } from "node:fs";
import { HIDING, HIDING_LABEL, buildPage } from "./page.mjs";

const how = process.argv[2];
if (!HIDING.includes(how)) {
  console.error("用法：node page-cli.mjs <藏法> [\"要藏的那句話\"]");
  for (const h of HIDING) console.error(`  ${h.padEnd(10)} ${HIDING_LABEL[h]}`);
  process.exit(2);
}

let mark = "RS-0000";
let text = process.argv[3];
if (!text) {
  const line = readFileSync(new URL("attacks.txt", import.meta.url), "utf8")
    .split("\n")
    .find((l) => l.startsWith(`${how}\t`));
  if (!line) {
    console.error(`attacks.txt 裡沒有 ${how} 這一條`);
    process.exit(2);
  }
  [, mark, text] = line.split("\t");
} else {
  mark = (text.match(/RS-\d{4}/) || ["RS-0000"])[0];
}

process.stdout.write(buildPage(how, mark, text));
