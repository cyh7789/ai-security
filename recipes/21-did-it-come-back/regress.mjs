// 三條回歸測試，跑的是 recipe 18 輸入側那道閘。
//
//   node regress.mjs
//
// 每一條都綁著一句真的發生過的輸入，而且那句話從它原本住的檔案撈，
// 不在這裡抄一份。抄一份的話，改了固定集這裡不會跟著變，
// 而測試還是綠的——那時候它守的是我抄的那句，不是防線面對的那句。
//
// 斷言只有一種形狀：把那句話送進閘，看它放行還是擋下。
// 不斷言 reason_code、不斷言黑名單裡有沒有哪個字。
// 理由是 shape-vs-behavior.sh 會實際跑給你看：只做一半的修補，
// 「黑名單裡沒有『騙』」那種斷言已經綠了，而 B4 照樣被擋。
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { scenarioGate } from "../18-not-a-free-chatgpt/gates.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

// 三個來源各長不一樣，所以撈法也不一樣。這不是雜訊，是這件事的真實成本：
// 回歸測試綁真實輸入，就得去那些輸入原本住的地方撈。
function fromBenign(id) {
  const rows = readFileSync(join(HERE, "../14-same-attacks-every-time/benign.jsonl"), "utf8")
    .trim()
    .split("\n")
    .map((l) => JSON.parse(l));
  const r = rows.find((x) => x.id === id);
  if (!r) throw new Error(`benign.jsonl 裡找不到 ${id}，測試綁的輸入不見了`);
  return r.question;
}

function fromPrompts(file, id) {
  const rows = readFileSync(join(HERE, "../18-not-a-free-chatgpt/prompts/", file), "utf8")
    .split("\n")
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => l.split("\t"));
  const r = rows.find((c) => c[0] === id);
  if (!r) throw new Error(`${file} 裡找不到 ${id}，測試綁的輸入不見了`);
  return r[1];
}

const CASES = [
  {
    id: "B4",
    from: "14/benign.jsonl",
    text: fromBenign("B4"),
    expect: true,
    why: "Day 20 那條誤擋：一句防詐宣導被自己的閘擋死。修好了它就該過",
  },
  {
    id: "d1",
    from: "18/prompts/direct.tsv",
    text: fromPrompts("direct.tsv", "d1"),
    expect: false,
    why: "放寬判準的另一半：原本擋得住的釣魚信，不能跟著鬆掉",
  },
  {
    id: "b1",
    from: "18/prompts/probe-bait.tsv",
    text: fromPrompts("probe-bait.tsv", "b1"),
    expect: true,
    why: "這條釘的是缺口，不是防線。拿掉「騙」之後它會過輸入側，"
      + "現在擋著它的是模型自己不寫（8/20 量過）。哪天有人把「騙」加回去，這條會紅，"
      + "那時候要重新決定的是誤擋跟這個缺口哪個貴",
  },
];

let fail = 0;
console.log("id\t來源\t期望\t實際\t結果");
for (const c of CASES) {
  const r = scenarioGate(c.text);
  const got = r.allow ? "allow" : "deny";
  const want = c.expect ? "allow" : "deny";
  const pass = r.allow === c.expect;
  if (!pass) fail += 1;
  console.log(`${c.id}\t${c.from}\t${want}\t${got}\t${pass ? "綠" : "紅"}`);
  if (!pass) console.log(`\t\t\t\t${r.reason}`);
}

console.log("");
for (const c of CASES) console.log(`${c.id}\t${c.why}`);
console.log("");
console.log(fail === 0 ? `${CASES.length} 綠 0 紅` : `${CASES.length - fail} 綠 ${fail} 紅`);
process.exit(fail === 0 ? 0 : 1);
