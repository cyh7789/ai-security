// 擋住之後，回應本身還會不會洩漏「這筆存在」。
//
//   node enumerable.mjs runs/2026-08-15/gen/bare-4.mjs
//   node enumerable.mjs runs/2026-08-15/gen/*.mjs | sort | uniq -c
//
// 判準是同一支處理函式對兩種請求的回應**分不分得開**：
//   別人的（存在，但不是你的）
//   根本不存在的編號
// 兩邊回一樣 → 對方問不出東西。分得開 → 一個一個問就列得出哪些編號存在。
//
// 注意這跟「403 比 404 危險」不是同一句話。單看一個狀態碼什麼都不能說，
// 一支對兩種情況都回 403 的處理函式一樣不洩漏。會洩漏的是「兩種情況給了兩種答案」。
import { pathToFileURL } from "node:url";

function fakeRes() {
  const r = { code: 200, body: undefined, sent: false };
  const done = (b) => { if (!r.sent) { r.body = b; r.sent = true; } return r; };
  r.status = (c) => { r.code = c; return r; };
  r.sendStatus = (c) => { r.code = c; return done(""); };
  r.json = done; r.send = done; r.end = done;
  r.set = () => r; r.setHeader = () => r; r.type = () => r;
  return r;
}

// 三種資源形狀各自的「存在但不是你的」與「根本不存在」。
// 用錯形狀會問到一個它根本沒在看的參數，然後兩邊都回同一句參數錯誤，
// 看起來像「分不開」，其實是這支腳本問錯問題。
const KINDS = {
  direct: [{ id: "1002" }, { id: "9999" }],
  nested: [{ id: "5002" }, { id: "9999" }],
  list:   [{ query: { ownerId: "2" } }, { query: { ownerId: "999" } }],
};

async function ask(handler, ask_) {
  const res = fakeRes();
  try {
    await handler({ params: { id: String(ask_.id ?? "") }, user: { id: 1 }, query: ask_.query ?? {}, headers: {} }, res, () => {});
  } catch { return "throw"; }
  const body = typeof res.body === "string" ? res.body : JSON.stringify(res.body ?? "");
  // 內容也要比：兩邊都回 404 但訊息不一樣，一樣分得開。
  return `${res.code}|${body}`;
}

const args = process.argv.slice(2);
const ki = args.indexOf("--kind");
const kind = ki < 0 ? "direct" : args[ki + 1];
const files = args.filter((a, i) => !a.startsWith("--") && !(ki >= 0 && i === ki + 1));
if (!files.length || !KINDS[kind]) {
  console.error("用法：node enumerable.mjs [--kind direct|nested|list] <生成的 .mjs> [...]");
  process.exit(2);
}
for (const f of files) {
  const name = f.split("/").pop().replace(/\.mjs$/, "");
  let handler;
  try {
    handler = (await import(`${pathToFileURL(f).href}?t=${Date.now()}`)).default;
  } catch { console.log([name, "載不進來", "-", "-"].join("\t")); continue; }
  const [a, b] = KINDS[kind];
  const theirs = await ask(handler, a);   // 存在，是乙的
  const ghost = await ask(handler, b);    // 根本不存在
  console.log([name, theirs === ghost ? "分不開" : "分得開", theirs, ghost].join("\t"));
}
