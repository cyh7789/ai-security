// 模型說要做某件事，跟那件事真的發生，中間的那道閘。這裡放三種。
//
//   node gate.mjs intent    '{"intent":"查一下這張單","tool":"delete_order","args":{"id":1002}}'
//   node gate.mjs external  '{"intent":"刪除訂單","tool":"delete_order","args":{"id":1002}}'  '幫我看一下 1002 這張訂單的狀況'
//   node gate.mjs allowlist '{"intent":"刪除訂單","tool":"delete_order","args":{"id":1002}}'
//
// 三種閘的差別只有一個：判斷基準是從哪裡來的。
//   intent     兩端都是模型這一輪產生的字（宣稱的意圖、填的參數）
//   external   動作還是模型提的，但准不准由模型碰不到的兩樣東西決定
//              （使用者原本打的那句話、我寫死的清單）
//   allowlist  Day 15 那道閘的形狀，看的是「這個工具、這個目標准不准碰」
import { fileURLToPath } from "node:url";

// 高風險動作預設拒絕。這一份是人寫的，模型的輸出不會改到它。
export const DENY_BY_DEFAULT = ["delete_order"];

// 工具與目標的白名單：這個客服 agent 服務的就是這三張單，刪除也在它的職權內。
// Day 15 那道閘擋的是「不該碰的目標」，而這一題裡目標完全合法。
export const TOOL_ALLOWLIST = ["get_order", "delete_order"];
export const TARGET_ALLOWLIST = [1001, 1002, 1003];

const WORDS = {
  read: ["查", "看", "確認狀況", "狀態", "明細", "查詢"],
  delete: ["刪", "刪除", "移除", "清掉", "取消這筆", "銷單"],
};

// 把一段中文歸到動作類別。同時命中就回 ambiguous，因為「查一下再刪掉」
// 這種句子歸成任何一類都會讓下面的比對失去意義。
export function classify(text) {
  const hit = Object.entries(WORDS)
    .filter(([, ws]) => ws.some((w) => text.includes(w)))
    .map(([k]) => k);
  if (hit.length === 1) return hit[0];
  return hit.length > 1 ? "ambiguous" : "unknown";
}

const TOOL_CLASS = { get_order: "read", delete_order: "delete" };

// 宣稱的那句話歸哪一類、實際要呼叫的工具歸哪一類。分開回傳是因為
// 「兩邊不一致」跟「那句話歸不了類」在紀錄上要分得開：前者是模型自己搞混，
// 後者只是它的中文寫得比我的關鍵字表花。混在一起數會高估前者。
export function intentClass(call) {
  return { said: classify(String(call.intent ?? "")), doing: TOOL_CLASS[call.tool] ?? "unknown" };
}

// 一、意圖核對閘：模型宣稱的意圖，跟它實際要呼叫的工具，是不是同一類。
export function intentGate(call) {
  const said = classify(String(call.intent ?? ""));
  const doing = TOOL_CLASS[call.tool];
  if (!doing) return { allow: false, reason: `不認得的工具 ${call.tool}` };
  if (said === "unknown" || said === "ambiguous") {
    return { allow: false, reason: `意圖歸不了類（${said}）` };
  }
  if (said !== doing) return { allow: false, reason: `宣稱 ${said}，實際 ${doing}` };
  return { allow: true, reason: `宣稱與實際都是 ${doing}` };
}

// 二、外部基準閘：高風險動作要在使用者「自己打的那句話」裡有依據。
// 它一樣讀 call.tool，所以不是「兩端都在模型外」；差別在決定准不准的那兩樣
// 模型碰不到：userRequest 是進 prompt 之前就存在的字串，DENY_BY_DEFAULT 是版控裡的一行。
// 模型這一輪宣稱了什麼，這道閘看不到。
//
// 比對規則只認關鍵字，是玩具等級：處理不了否定、同義詞、受詞，
// 也不核對原話裡的編號跟 call.args.id 是不是同一個。真要上線得換成結構化授權。
export function externalGate(call, userRequest) {
  if (!DENY_BY_DEFAULT.includes(call.tool)) {
    return { allow: true, reason: `${call.tool} 不在預設拒絕清單上` };
  }
  const asked = classify(String(userRequest ?? ""));
  if (asked !== "delete") {
    return { allow: false, reason: "使用者原始請求裡沒有這個動作，要人確認" };
  }
  return { allow: true, reason: "使用者原始請求裡就有這個動作" };
}

// 三、白名單閘：Day 15 的形狀搬過來。這道閘沒有壞，它回答的是另一個問題。
export function allowlistGate(call) {
  if (!TOOL_ALLOWLIST.includes(call.tool)) {
    return { allow: false, reason: `工具 ${call.tool} 不在清單上` };
  }
  const id = Number(call.args?.id);
  if (!TARGET_ALLOWLIST.includes(id)) return { allow: false, reason: `目標 ${id} 不在清單上` };
  return { allow: true, reason: `${call.tool} 對 ${id} 都在清單上` };
}

export const GATES = {
  none: () => ({ allow: true, reason: "沒有閘" }),
  intent: (call) => intentGate(call),
  external: (call, req) => externalGate(call, req),
  allowlist: (call) => allowlistGate(call),
};

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [kind, json, req] = process.argv.slice(2);
  const g = GATES[kind];
  if (!g) {
    console.error(`用法：node gate.mjs <${Object.keys(GATES).join("|")}> '<JSON>' [使用者請求]`);
    process.exit(2);
  }
  const r = g(JSON.parse(json), req ?? "");
  console.log(`${r.allow ? "allow" : "deny"}\t${r.reason}`);
  process.exit(r.allow ? 0 : 1);
}
