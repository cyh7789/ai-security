// 四道閘。前三道看送進來的，第四道看送出去的。
//
//   node gates.mjs rate     u1
//   node gates.mjs length   "很長很長的一段字"
//   node gates.mjs scenario "我的訂單什麼時候到"
//
// 不要照「前三道防成本、第四道防責任」那樣分（README 有完整版）：
// 一、二是資源控制，三判的是用途不對而不是量太大，四看輸出內容。
// 三跟四都不是可靠的安全邊界。差別在最壞情況：資源那兩道失守你收到一張帳單，
// 後面兩道失守是你的服務把那個東西送出去了。
//
// 第四道在 classify.mjs，因為它要呼叫模型，跟這三道不同性質。
import { fileURLToPath } from "node:url";

export const LIMITS = {
  perMinute: 20, // 一、同一使用者每分鐘幾次
  maxChars: 2000, // 二、單筆輸入的硬上限，超過就不送進模型
};

// 三、場景檢查：意圖允許清單。不在清單上一律擋。
//
// 這裡刻意不用黑名單。黑名單擋的是你想得到的壞事，而你想不到的那些才是問題；
// 允許清單擋的是「不在我產品範圍內」，那個範圍你自己說得出來。
// SPEC 要的是確定性檢查，所以是規則式，不是再問一次模型
// （再問一次模型的話，被說服的模型會說安全，那是 Day 17 那條）。
export const SCENARIO = {
  訂單查詢: ["訂單", "單號", "我買的", "訂購"],
  到貨時間: ["到貨", "出貨", "什麼時候到", "物流", "配送"],
  退換貨: ["退貨", "換貨", "退款", "瑕疵", "壞掉"],
  發票: ["發票", "統編", "報帳"],
  帳號問題: ["登入", "密碼", "帳號", "註冊"],
  客服信件: ["客服信", "回覆客戶", "通知信", "信件開頭", "結尾", "語氣"],
};

const hits = new Map(); // 使用者 → 這一分鐘打過的時間戳

export function rateGate(user, now = Date.now()) {
  const win = (hits.get(user) ?? []).filter((t) => now - t < 60_000);
  if (win.length >= LIMITS.perMinute) {
    hits.set(user, win);
    return { allow: false, code: "RATE_OVER", reason: `每分鐘上限 ${LIMITS.perMinute} 次，這是第 ${win.length + 1} 次` };
  }
  win.push(now);
  hits.set(user, win);
  return { allow: true, code: "RATE_OK", reason: `這一分鐘第 ${win.length} 次` };
}

export function resetRate() {
  hits.clear();
}

export function lengthGate(text) {
  const n = [...String(text)].length;
  return n > LIMITS.maxChars
    ? { allow: false, code: "LEN_OVER", reason: `${n} 字超過上限 ${LIMITS.maxChars}` }
    : { allow: true, code: "LEN_OK", reason: `${n} 字` };
}

// 允許清單之外還要一層擋掉「主題在範圍內、但要做的事不該由這個 bot 做」。
// 第一版只有允許清單，結果「幫我寫一封信騙客戶回覆帳號末四碼」因為命中「帳號」就過了，
// 那樣量出來的「拆開來問也全放行」不能證明任何事，因為直接問也全放行。
//
// 這一層是黑名單，而黑名單只擋得住你想得到的那些。我知道，這正是第四道存在的理由：
// 想不到的那些只有看輸出才攔得到。
//
// 反向也會出事，這條自己跑得出來：
//   node gates.mjs scenario "幫我寫一封提醒客戶不要受騙、不要相信假冒官方信件的通知"
// 現在回 deny，因為命中「騙」。一句防詐宣導被自己的閘擋掉。
// 所以這一層的定位是「便宜的明顯濫用篩選」，不是安全邊界。要不要真的攔，
// 得看誤擋率、繞過率跟它省下的模型呼叫，而這個 recipe 這三個數都沒量。
export const OUT_OF_SCOPE = ["騙", "詐", "冒充", "假冒", "偽裝成", "誘導", "套出"];

export function scenarioGate(text) {
  const t = String(text);
  const bad = OUT_OF_SCOPE.find((x) => t.includes(x));
  if (bad) return { allow: false, code: "SCOPE_BLOCK", reason: `要做的事不該由客服 bot 做（命中「${bad}」）` };
  for (const [name, words] of Object.entries(SCENARIO)) {
    const w = words.find((x) => t.includes(x));
    if (w) return { allow: true, code: "SCENARIO_OK", reason: `${name}（命中「${w}」）` };
  }
  return { allow: false, code: "SCENARIO_MISS", reason: "不在這個客服 bot 的場景清單上" };
}

export const GATES = { rate: rateGate, length: lengthGate, scenario: scenarioGate };

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [kind, arg] = process.argv.slice(2);
  const g = GATES[kind];
  if (!g) {
    console.error(`用法：node gates.mjs <${Object.keys(GATES).join("|")}> <輸入>`);
    process.exit(2);
  }
  const r = g(arg ?? "");
  console.log(`${r.allow ? "allow" : "deny"}\t${r.reason}`);
  process.exit(r.allow ? 0 : 1);
}
