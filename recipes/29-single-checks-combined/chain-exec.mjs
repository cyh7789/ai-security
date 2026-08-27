// 把 render.js 那條 sink 放進真的 HTML 引擎裡打一次。
//
//   npm install jsdom && node chain-exec.mjs
//
// 為什麼要 jsdom 不用字串比對：字串裡出現 `<img onerror=...>` 只證明那串字被印出來了，
// 證不出瀏覽器會把它當成節點、也證不出那段 JS 會跑。這兩件事要分開，
// 而分不開的判準正是 Day 27 那支確認腳本第一版踩過的坑。
//
// 離開碼：0 兩邊都如預期（有洞版執行、修好版擋下）、1 有一邊不如預期。
import { JSDOM } from "jsdom";

// 被汙染的「模型回答」。這串字不是使用者打的，是模型讀了某個外部內容之後吐出來的
// （Day 11 那條路）。onerror 一跑，真實攻擊裡就是把 cookie 送出去。
const MODEL_ANSWER = `<img src=x onerror="window.__xss=(window.__xss||0)+1">`;

// playground/src/render.js 現在那一行，逐字。
const renderNow = (a) => `<div class="answer">${a}</div>`;

// Day 5 教過的修法：不要把它當標記解析。這裡用逃逸表達同一件事，
// 因為 textContent 沒辦法只用字串示範。
const renderFixed = (a) =>
  `<div class="answer">${String(a).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))}</div>`;

function run(label, render) {
  const dom = new JSDOM(`<!DOCTYPE html><div id="answer"></div>`, {
    url: "https://victim.example/",
    runScripts: "dangerously",
  });
  const { window } = dom;
  window.document.getElementById("answer").innerHTML = render(MODEL_ANSWER);
  const img = window.document.querySelector("#answer img");
  if (!img) {
    console.log(`${label}\t沒造出可執行節點（只當文字顯示，擋下）`);
    dom.window.close();
    return false;
  }
  // 派發 error，看 onerror 那段是不是真的可執行的 JS，而不只是一個屬性字串。
  img.dispatchEvent(new window.Event("error"));
  const fired = Boolean(window.__xss);
  console.log(
    `${label}\t造出 <img onerror>，派發 error 後 JS ${fired ? "真的執行了（XSS 成立）" : "沒跑"}`
  );
  dom.window.close();
  return fired;
}

const vulnFired = run("有洞版 render.js 現況", renderNow);
const fixedFired = run("修好版（逃逸）", renderFixed);

// 兩邊都要如預期才算數。只驗有洞版會中，修好版沒驗的話，
// 這支腳本沒辦法分辨「修法有效」跟「這一輪根本沒打進去」。
if (vulnFired && !fixedFired) {
  console.log("\n這條鏈走得通，而且修法擋得下來。");
  process.exit(0);
}
console.log(
  `\n不如預期：有洞版 ${vulnFired ? "中了" : "沒中"}、修好版 ${fixedFired ? "也中了" : "沒中"}`
);
process.exit(1);
