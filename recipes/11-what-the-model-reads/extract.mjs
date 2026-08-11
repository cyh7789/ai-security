// 把同一份內容的四種讀法印出來，看那句指令在哪幾層還在。
//
//   node page-cli.mjs comment   | node extract.mjs
//   node page-cli.mjs invisible | node extract.mjs --show human
//
// 四層的定義與限制寫在 layers.mjs。
import { NAMES, LABEL, layers, decodeInvisible, isGhost } from "./layers.mjs";

// 對齊用一般空白，不要用全形空白填。全形空白是隱形字元，
// 而這一天在講的就是隱形字元，示範輸出自己夾帶一個說不過去。
const width = (s) => [...s].reduce((n, c) => n + (c.codePointAt(0) > 0x2e80 ? 2 : 1), 0);
const pad = (s, w) => s + " ".repeat(Math.max(0, w - width(s)));

let html = "";
process.stdin.on("data", (c) => (html += c));
process.stdin.on("end", () => {
  const L = layers(html);
  const show = process.argv.indexOf("--show");
  if (show > -1) {
    const which = process.argv[show + 1];
    if (!NAMES.includes(which)) {
      console.error(`--show 只吃 ${NAMES.join("／")}`);
      process.exit(2);
    }
    process.stdout.write(L[which]);
    return;
  }
  // 標記可能以隱形碼點的形式存在，所以要解過一次才找得到。
  const mark = (decodeInvisible(html).match(/RS-\d{4}/) || [])[0];
  const carries = (s) =>
    s.includes(mark) ? "在" : decodeInvisible(s).includes(mark) ? "在（隱形）" : "沒了";
  console.log("──── 同一份內容，四種讀法 ────");
  for (const n of NAMES) {
    const has = mark ? carries(L[n]) : "（這一頁沒有標記）";
    // 數碼點不數 UTF-16 單位：隱形碼點在補充平面，一個算兩單位，數錯會少報一半。
    const cps = [...L[n]].length;
    console.log(`${pad(LABEL[n], 18)}${String(cps).padStart(5)} 碼點   ${mark ?? ""} ${has}`);
  }
  const ghosts = [...L.visible].filter((c) => isGhost(c.codePointAt(0))).length;
  console.log("");
  console.log(
    ghosts
      ? `照樣式篩過那一層裡，有 ${ghosts} 個不佔位置的碼點。畫面上看不到它們，抽取程式也沒有拿掉。`
      : "照樣式篩過那一層裡沒有不佔位置的碼點。",
  );
});
