// 一支最小的 MCP 客戶端：把 JSON-RPC 從 stdin／stdout 餵給一台本地 stdio server。
// 不用任何相依套件，讀者不必 npm install。list-tools.sh 與 probe.sh 都靠這支。
//
// 副檔名是 .cjs 不是 .js：這個 repo 的 package.json 寫了 "type": "module"，
// 底下的 .js 會被當成 ES module，require 就會炸（實測 ReferenceError: require is not defined）。
// 而讀者也可能只把這個資料夾複製出去，那時沒有 package.json，.js 又會變成 CommonJS。
// .cjs 兩種情況都是 CommonJS，所以不管放在哪都跑得起來。
//
// 用法：
//   node mcp-rpc.cjs tools -- <指令...>                     做 initialize 然後 tools/list
//   node mcp-rpc.cjs call <工具名> <JSON 參數> -- <指令...>   多做一次 tools/call
//
// tools 模式印出每個工具一段，最後一行是 TOTAL<TAB>工具數<TAB>描述總字元數。
// call 模式第一行是 VERDICT=...，之後是回傳的文字原樣。
//
// 為什麼 VERDICT 有 OK 跟 TOOLERR 兩種：
//   MCP 的工具錯誤不走 JSON-RPC 的 error 欄位。filesystem server 拒絕存取的時候
//   回的是一個成功的 result，裡面 isError 是 true、拒絕的理由塞在 content 的文字裡。
//   只看 RPC 層有沒有 error 的客戶端會把「被拒絕」讀成「讀到了」，那正好是
//   probe.sh 最不能搞錯的一件事，所以這裡把兩者分成不同的 VERDICT。

const { spawn } = require("child_process");
const fs = require("fs");

// 錯誤訊息一律用 writeSync 寫檔案描述子。process.stderr.write 接到管線的時候也是
// 非同步的，配上馬上結束的離開路徑會整段消失。
const die = (msg, code) => { fs.writeSync(2, msg); process.exit(code); };

const argv = process.argv.slice(2);
const sep = argv.indexOf("--");
if (sep < 0 || sep === argv.length - 1) {
  die("用法：node mcp-rpc.cjs tools|call ... -- <指令...>\n", 2);
}
const mode = argv.slice(0, sep);
const cmd = argv.slice(sep + 1);
const TIMEOUT = Number(process.env.MCP_RPC_TIMEOUT || 60000);

// 指令不存在不會讓 spawn 丟例外，它是之後才發 error 事件，所以下面那個 handler
// 才是「這台起不起來」真正的判斷點。
const child = spawn(cmd[0], cmd.slice(1), { stdio: ["pipe", "pipe", "pipe"] });

let outBuf = "";
let errBuf = "";
let finished = false;
const pending = new Map();

child.on("error", (e) => {
  process.stdout.write("VERDICT=FATAL\n起不了 " + cmd[0] + "：" + e.message + "\n");
  finish(4);
});
child.stderr.on("data", (d) => { errBuf += d; });

// server 的 stdout 是一行一個 JSON。有些 server 會在前面吐 banner 或警告，
// 所以解不開的行直接跳過，不能因為第一行不是 JSON 就判定整台壞了。
child.stdout.on("data", (d) => {
  outBuf += d;
  let n;
  while ((n = outBuf.indexOf("\n")) >= 0) {
    const line = outBuf.slice(0, n).trim();
    outBuf = outBuf.slice(n + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch (e) { continue; }
    if (msg.id !== undefined && pending.has(msg.id)) {
      const done = pending.get(msg.id);
      pending.delete(msg.id);
      done(msg);
    }
  }
});

// server 先死掉的話，等在那裡的請求永遠不會有答案，逾時之前畫面上什麼都不會發生。
// 這裡把「它死了」跟「它慢」分開報，因為前者的原因在 stderr 裡。
child.on("exit", (code, sig) => {
  if (finished || pending.size === 0) return;
  process.stdout.write("VERDICT=FATAL\nserver 在回答之前就結束了（exit=" + code +
    " signal=" + sig + "）。它的 stderr 最後幾行：\n" + tailErr());
  finish(4);
});

function tailErr() {
  const lines = errBuf.split("\n").filter((s) => s.trim().length);
  return lines.slice(-5).join("\n") + (lines.length ? "\n" : "");
}

const timer = setTimeout(() => {
  process.stdout.write("VERDICT=FATAL\n等了 " + TIMEOUT + " 毫秒沒有回應。它的 stderr 最後幾行：\n" + tailErr());
  try { child.kill("SIGKILL"); } catch (e) { /* 已經死了 */ }
  finish(4);
}, TIMEOUT);

const send = (o) => child.stdin.write(JSON.stringify(o) + "\n");
const request = (id, method, params) => new Promise((res) => {
  pending.set(id, res);
  send({ jsonrpc: "2.0", id: id, method: method, params: params });
});

// 不用 process.exit 收尾。stdout 接到管線的時候寫入是非同步的，
// process.exit 會把還沒排出去的內容整段丟掉：實測 tools 模式印出來是空的。
// 改成設 exitCode、關掉子行程跟計時器，讓 node 自己排完再結束。
function finish(code) {
  if (finished) return;
  finished = true;
  clearTimeout(timer);
  process.exitCode = code;
  try { child.stdin.end(); } catch (e) { /* 管線已關 */ }
  try { child.kill("SIGTERM"); } catch (e) { /* 已經死了 */ }
}

(async () => {
  const init = await request(1, "initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "what-can-it-touch", version: "0" },
  });
  if (init.error) {
    process.stdout.write("VERDICT=FATAL\ninitialize 被拒絕：" + JSON.stringify(init.error) + "\n");
    finish(4);
    return;
  }
  // 這一則是通知不是請求，沒有 id 也不會有回應。少了它有些 server 會拒接後面的呼叫。
  send({ jsonrpc: "2.0", method: "notifications/initialized" });

  if (mode[0] === "tools") {
    const res = await request(2, "tools/list", {});
    if (res.error) {
      process.stdout.write("VERDICT=FATAL\ntools/list 被拒絕：" + JSON.stringify(res.error) + "\n");
      finish(4);
      return;
    }
    const tools = (res.result && res.result.tools) || [];
    let total = 0;
    tools.forEach((t, i) => {
      // 描述原樣印，不截斷。這支存在的理由就是「UI 上那個名字不是模型收到的東西」，
      // 截斷等於把要給讀者看的證據刪掉。
      const desc = typeof t.description === "string" ? t.description : "";
      const chars = Array.from(desc).length;
      total += chars;
      process.stdout.write("\n── 第 " + (i + 1) + " 個工具（共 " + tools.length + " 個）：" +
        t.name + "，描述 " + chars + " 字元 ──\n" + desc + "\n");
    });
    process.stdout.write("TOTAL\t" + tools.length + "\t" + total + "\n");
    finish(0);
    return;
  }

  if (mode[0] === "call") {
    const res = await request(2, "tools/call", { name: mode[1], arguments: JSON.parse(mode[2]) });
    if (res.error) {
      process.stdout.write("VERDICT=RPCERR\n" + JSON.stringify(res.error) + "\n");
      finish(0);
      return;
    }
    const r = res.result || {};
    const text = ((r.content || []).map((c) => (typeof c.text === "string" ? c.text : "")).join("\n"));
    process.stdout.write("VERDICT=" + (r.isError ? "TOOLERR" : "OK") + "\n" + text + "\n");
    finish(0);
    return;
  }

  die("不認得的模式：" + mode[0] + "\n", 2);
})();
