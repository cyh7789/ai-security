// 三條回歸測試，跑的是 recipe 18 輸入側那道閘。
//
//   node regress.mjs
//
// 每一條都綁著一句真的發生過的輸入，而且那句話從它原本住的檔案撈，
// 不在這裡抄一份。抄一份的話，改了固定集這裡不會跟著變，
// 而測試還是綠的，那時候它守的是我抄的那句，不是防線面對的那句。
//
// 斷言只有一種形狀：把那句話送進閘，看它放行還是擋下。
//
// 不斷言黑名單裡有沒有哪個字，理由是 shape-vs-behavior.sh 會實際跑給你看：
// 只做一半的修補，那種斷言已經綠了，而 B4 照樣被擋。
//
// reason_code 是另一回事，不要跟上面那條混在一起（8/20 外審抓到）。
// 它咬得到這次的兩層修補：只修一半的時候，B4 的 code 是 SCENARIO_MISS 不是 SCENARIO_OK。
// 這裡不斷言它，只是因為這三條問的是「放行還是擋下」，不是「為什麼」。
// recipe 20 把規則閘的 code 當成穩定的統計鍵是對的，那一天沒有被今天推翻。
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
    kind: "防線",
    expect: true,
    why: "Day 20 那條誤擋：一句防詐宣導被自己的閘擋死。修好了它就該過",
  },
  {
    id: "d1",
    from: "18/prompts/direct.tsv",
    text: fromPrompts("direct.tsv", "d1"),
    kind: "防線",
    expect: false,
    why: "放寬判準的另一半：原本擋得住的釣魚信，不能跟著鬆掉",
  },
  {
    id: "b1",
    from: "18/prompts/probe-bait.tsv",
    text: fromPrompts("probe-bait.tsv", "b1"),
    kind: "缺口樁",
    expect: true,
    why: "這條釘的是缺口，不是防線。拿掉「騙」之後它會過輸入側，"
      + "擋著它的是模型那次沒有照做（紀錄在 recipe 18 的 runs/2026-08-20-probe/），"
      + "那不是我寫的防線，而且分不出是哪一層造成的。這條紅了不必然是有人做錯事："
      + "可能是有人把「騙」加回去，也可能是有人寫了更準的組合判斷，那是改善。"
      + "它只說一件事：輸入側對這句話的判決變了，回去跟 B4 一起看",
  },
];

// --only 防線 / --only 缺口樁：只跑那一類。
// 8/21 加的，因為離開碼一個人扛不了兩件事：防線跟缺口樁可以同時紅，
// 而 0／1／2 是互斥的，同時紅的時候只講得出防線那件。CI 上的缺口樁 job
// 因此在 b1 明明是紅的時候印出「都還釘在原地」然後綠掉。
const ONLY = (() => {
  const i = process.argv.indexOf("--only");
  return i === -1 ? null : process.argv[i + 1];
})();
const RUN = ONLY ? CASES.filter((c) => c.kind === ONLY) : CASES;
if (ONLY && RUN.length === 0) {
  console.error(`沒有 kind 是「${ONLY}」的案例。有的是：${[...new Set(CASES.map((c) => c.kind))].join("、")}`);
  process.exit(2);
}

// 兩種紅的正確處置相反，所以它們不能共用一個離開碼：
//   防線紅了，「改期望值」等於把防線關掉
//   缺口樁紅了，「改期望值」就是正確處置（重新做那個取捨）
// 走同一個離開碼、同一封通知，人會被訓練成「紅了就去改 expect」，
// 三週後遇到 B4 紅會用同一個手勢。2026-08-21 開 PR 實測到這件事：
// CI 上開了兩個 job，但兩個都跑整支，b1 的紅照樣污染防線那個 job。
// 分在 CI 那一層是假的分，要分在這裡。
let failLine = 0;
let failStake = 0;
console.log("id\t類\t來源\t期望\t實際\t結果");
for (const c of RUN) {
  const r = scenarioGate(c.text);
  const got = r.allow ? "allow" : "deny";
  const want = c.expect ? "allow" : "deny";
  const pass = r.allow === c.expect;
  if (!pass) (c.kind === "防線" ? failLine++ : failStake++);
  console.log(`${c.id}\t${c.kind}\t${c.from}\t${want}\t${got}\t${pass ? "綠" : "紅"}`);
  if (!pass) console.log(`\t\t\t\t\t${r.reason}`);
}
const fail = failLine + failStake;

console.log("");
for (const c of RUN) console.log(`${c.id}\t${c.why}`);
console.log("");
console.log(fail === 0 ? `${RUN.length} 綠 0 紅` : `${RUN.length - fail} 綠 ${fail} 紅（防線 ${failLine}、缺口樁 ${failStake}）`);

// 離開碼只有兩個意思，跟全 repo 的公約同一套：0 綠、1 有東西紅了。
// 不要拿 2 表示「缺口樁動了」：2 在公約裡已經是「這一跑沒有結論」，
// 借用它的話，讀這個數字的人分不出收到的是哪一件事，而那兩件的處置相反。
// （8/21 外審抓到的：我在定完公約的同一天就自己借用了它。）
//
// 那「防線紅」跟「缺口樁紅」怎麼分？靠 --only，兩個 job 各跑各的那一類。
// 擋不擋合併也不是這個數字決定的，是分支保護決定的：
// 防線那個 job 在必要檢查清單裡，缺口樁那個不在。
process.exit(fail === 0 ? 0 : 1);
