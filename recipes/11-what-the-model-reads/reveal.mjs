// 看見那些看不見的字。吃 stdin，印出不佔位置的碼點以及它們拼出來的東西。
//
//   node page-cli.mjs invisible | node extract.mjs --show human | node reveal.mjs
//   node page-cli.mjs invisible | node extract.mjs --show visible | node reveal.mjs
//
// 兩行的差別就是這一天要看的：人眼那一層乾淨，抽取程式那一層不乾淨，
// 而它們在畫面上逐字相同。

const TAG_BASE = 0xe0000;
const isGhost = (p) => p >= TAG_BASE && p <= TAG_BASE + 0x7f;

let s = "";
process.stdin.on("data", (c) => (s += c));
process.stdin.on("end", () => {
  const cps = [...s].map((c) => c.codePointAt(0));
  const ghosts = cps.filter(isGhost);
  console.log(`收到 ${cps.length} 個碼點，畫面上看得到的 ${cps.length - ghosts.length} 個。`);
  if (!ghosts.length) {
    console.log("沒有不佔位置的碼點。");
    return;
  }
  console.log(`不佔位置的 ${ghosts.length} 個，第一個是 U+${ghosts[0].toString(16).toUpperCase()}。`);
  console.log("把它們照 Unicode Tags 的對應換回 ASCII：");
  console.log(`  ${ghosts.map((p) => String.fromCharCode(p - TAG_BASE)).join("")}`);
});
