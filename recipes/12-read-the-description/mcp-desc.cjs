// 問一台 MCP server 有哪些工具，把每個工具的描述原樣印出來，不截斷。
//
//   node mcp-desc.cjs --stdio -- npx -y @playwright/mcp@latest
//   node mcp-desc.cjs --http https://example.com/mcp [Header:值 ...]
//
// tools/list 會分頁（規格：This operation supports pagination），所以兩路都要
// 跟著 nextCursor 一直問到沒有為止。只問第一頁然後回 0，就是這一份在罵的那種假通過。
//
// 判斷「還有沒有下一頁」要看那個欄位在不在，不能看它是不是真值。
// schema 對 nextCursor 的原話是 "If present, there may be more results available."，
// 而 cursor 是一個 opaque token，空字串是合法的值。用 `while (cursor)` 的話，
// 回空字串的 server 會被當成問完了，然後回 0。第二版就是這樣，也是外審抓到的。
//
// 為什麼要有 --http、結束碼為什麼分兩種：README。
// 一句話版本：0 是問到了，2 是沒問到，而「沒問到」不是「它沒有工具」。

const { spawn } = require("child_process");
const https = require("https");
const http = require("http");
const { URL } = require("url");

const TIMEOUT = Number(process.env.MCP_TIMEOUT || 60000);
const INIT = {
  protocolVersion: "2025-06-18",
  capabilities: {},
  clientInfo: { name: "read-the-description", version: "0" },
};

const fail = (msg) => {
  process.stdout.write(msg + "\n這不是「它沒有工具」，是我沒問到。結束碼 2。\n");
  process.exit(2);
};

// ── 印描述 ────────────────────────────────────────────────
// 原樣印、不截斷。這支存在的理由就是「UI 上那個名字不是模型收到的東西」，
// 截斷等於把要給讀者看的證據刪掉，而植入的句子通常在後半段。
function report(where, tools, pages) {
  let total = 0;
  process.stdout.write("問的是這台：" + where + "\n");
  process.stdout.write("下面每一段都是它自己回報的描述，原樣，沒有截斷。\n");
  tools.forEach((t, i) => {
    const desc = typeof t.description === "string" ? t.description : "";
    const chars = [...desc].length;
    total += chars;
    process.stdout.write("\n── 第 " + (i + 1) + " 個工具（共 " + tools.length + " 個）：" +
      t.name + "，描述 " + chars + " 字元 ──\n" + desc + "\n");
  });
  process.stdout.write("\n════════ " + tools.length + " 個工具，描述合計 " + total + " 字元" +
    (pages > 1 ? "，分 " + pages + " 頁問完" : "") + " ════════\n");
  // 零個工具是一個合法的答案，但它跟「我沒問到」在畫面上長得一樣，要講開。
  if (!tools.length) {
    process.stdout.write("initialize 跟 tools/list 都答了，它就是沒宣告工具。\n");
  }
  process.stdout.write("TOTAL\t" + tools.length + "\t" + total + "\t" + pages + "\n");
}

// ── stdio ────────────────────────────────────────────────
function viaStdio(cmd) {
  const child = spawn(cmd[0], cmd.slice(1), { stdio: ["pipe", "pipe", "pipe"] });
  let out = "", err = "", done = false;
  const pending = new Map();

  const timer = setTimeout(() => {
    if (done) return;
    done = true;
    try { child.kill("SIGKILL"); } catch (e) { /* 已經死了 */ }
    fail("等了 " + TIMEOUT + " 毫秒沒有回應。它的 stderr 最後幾行：\n" + err.split("\n").slice(-5).join("\n"));
  }, TIMEOUT);

  child.on("error", (e) => { if (!done) { done = true; clearTimeout(timer); fail("起不了 " + cmd[0] + "：" + e.message); } });
  child.stderr.on("data", (d) => { err += d; });
  // server 先死掉的話請求永遠不會有答案，逾時之前畫面上什麼都不會發生。
  child.on("exit", (code) => {
    if (done || pending.size === 0) return;
    done = true; clearTimeout(timer);
    fail("server 在回答之前就結束了（exit=" + code + "）。它的 stderr 最後幾行：\n" +
      err.split("\n").slice(-5).join("\n"));
  });
  child.stdout.on("data", (d) => {
    out += d;
    let n;
    while ((n = out.indexOf("\n")) >= 0) {
      const line = out.slice(0, n).trim();
      out = out.slice(n + 1);
      if (!line) continue;
      let msg;
      // 有些 server 前面會吐 banner，解不開的行跳過就好。
      try { msg = JSON.parse(line); } catch (e) { continue; }
      if (msg.id !== undefined && pending.has(msg.id)) {
        const res = pending.get(msg.id);
        pending.delete(msg.id);
        res(msg);
      }
    }
  });

  const send = (o) => child.stdin.write(JSON.stringify(o) + "\n");
  const req = (id, method, params) => new Promise((res) => {
    pending.set(id, res);
    send({ jsonrpc: "2.0", id, method, params });
  });

  return (async () => {
    const init = await req(1, "initialize", INIT);
    if (init.error) fail("initialize 被拒絕：" + JSON.stringify(init.error));
    // 這則是通知不是請求，少了它有些 server 會拒接後面的呼叫。
    send({ jsonrpc: "2.0", method: "notifications/initialized" });
    const all = [];
    let cursor, more = false, pages = 0, id = 2;
    do {
      const r = await req(id++, "tools/list", more ? { cursor } : {});
      if (r.error) fail("tools/list 被拒絕：" + JSON.stringify(r.error));
      const res = r.result || {};
      all.push(...(res.tools || []));
      more = Object.prototype.hasOwnProperty.call(res, "nextCursor");
      cursor = res.nextCursor;
      pages += 1;
      // 分頁不收斂的話會一直問下去，那是 server 壞了，不是我沒問完。
      if (pages > 50) fail("問了 50 頁還有 nextCursor，這台的分頁沒有收斂");
    } while (more);
    done = true;
    clearTimeout(timer);
    report(cmd.join(" "), all, pages);
    // 不用 process.exit：stdout 接到管線時是非同步寫入，會把還沒排出去的內容丟掉。
    try { child.stdin.end(); } catch (e) { /* 管線已關 */ }
    try { child.kill("SIGTERM"); } catch (e) { /* 已經死了 */ }
  })();
}

// ── http ─────────────────────────────────────────────────
function viaHttp(url, extra) {
  let session = null;
  let negotiated = null;

  const post = (body) => new Promise((res, rej) => {
    const u = new URL(url);
    const mod = u.protocol === "https:" ? https : http;
    const data = JSON.stringify(body);
    const headers = {
      "content-type": "application/json",
      // 兩種都收：規格允許 server 用 SSE 回單一則回應。
      accept: "application/json, text/event-stream",
      "content-length": Buffer.byteLength(data),
      ...extra,
    };
    if (session) headers["mcp-session-id"] = session;
    // 規格：If using HTTP, the client MUST include the MCP-Protocol-Version header
    // on all subsequent requests。initialize 之後才送，因為那一發還沒協商完。
    if (session || negotiated) headers["mcp-protocol-version"] = negotiated || INIT.protocolVersion;
    const r = mod.request({
      hostname: u.hostname, port: u.port, path: u.pathname + u.search,
      method: "POST", headers, timeout: TIMEOUT,
    }, (resp) => {
      if (resp.headers["mcp-session-id"]) session = resp.headers["mcp-session-id"];
      let buf = "";
      resp.on("data", (d) => { buf += d; });
      resp.on("end", () => res({ status: resp.statusCode, body: buf }));
    });
    r.on("timeout", () => { r.destroy(new Error("等了 " + TIMEOUT + " 毫秒沒有回應")); });
    r.on("error", rej);
    r.write(data);
    r.end();
  });

  // 回應可能是 application/json，也可能是 text/event-stream 包一層 data:。
  const parse = (raw) => {
    const t = raw.trim();
    if (!t) return null;
    if (t.startsWith("{")) { try { return JSON.parse(t); } catch (e) { return null; } }
    for (const line of t.split("\n")) {
      const m = line.match(/^data:\s*(.*)$/);
      if (m) { try { return JSON.parse(m[1]); } catch (e) { /* 下一行 */ } }
    }
    return null;
  };

  const check = (r, what) => {
    const msg = parse(r.body);
    // 401 是這一路最常見的答案，而它跟「沒有工具」差很遠，所以要原樣印出來。
    if (r.status >= 400 || !msg || msg.error) {
      fail(what + " 問不到：HTTP " + r.status + "\n" + r.body.slice(0, 400));
    }
    return msg;
  };

  return (async () => {
    const init = check(await post({ jsonrpc: "2.0", id: 1, method: "initialize", params: INIT }), "initialize");
    negotiated = (init.result && init.result.protocolVersion) || INIT.protocolVersion;
    await post({ jsonrpc: "2.0", method: "notifications/initialized" });
    const all = [];
    let cursor, more = false, pages = 0, id = 2;
    do {
      const msg = check(await post({
        jsonrpc: "2.0", id: id++, method: "tools/list",
        params: more ? { cursor } : {},
      }), "tools/list");
      const res = msg.result || {};
      all.push(...(res.tools || []));
      more = Object.prototype.hasOwnProperty.call(res, "nextCursor");
      cursor = res.nextCursor;
      pages += 1;
      if (pages > 50) fail("問了 50 頁還有 nextCursor，這台的分頁沒有收斂");
    } while (more);
    report(url, all, pages);
  })();
}

// ── 入口 ─────────────────────────────────────────────────
const argv = process.argv.slice(2);
let job;
if (argv[0] === "--stdio") {
  const sep = argv.indexOf("--");
  if (sep < 0 || sep === argv.length - 1) fail("--stdio 後面要 `-- <啟動指令...>`");
  job = viaStdio(argv.slice(sep + 1));
} else if (argv[0] === "--http") {
  if (!argv[1]) fail("--http 後面要一個網址");
  const extra = {};
  for (const a of argv.slice(2)) {
    const i = a.indexOf(":");
    if (i > 0) extra[a.slice(0, i)] = a.slice(i + 1);
  }
  job = viaHttp(argv[1], extra);
} else {
  process.stdout.write("用法：node mcp-desc.cjs --stdio -- <指令...>｜--http <網址> [Header:值 ...]\n");
  process.exit(2);
}
job.catch((e) => fail("炸了：" + e.message));
