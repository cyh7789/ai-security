// 有洞的版本：建立那半驗了 quantity，編輯那半沒有。
// 這個形狀是從一個真實專案量出來的：六個資源，六次都是建立那半檢查欄位內容、
// 編輯那半只檢查「你要改哪一筆」。這裡縮成一個欄位方便打。
import http from "node:http";
import fs from "node:fs";

const orders = new Map([[1, { id: 1, itemId: "sku-1", quantity: 2 }]]);

function json(res, code, body) {
  const s = JSON.stringify(body);
  res.writeHead(code, { "content-type": "application/json" });
  res.end(s);
}

function readBody(req) {
  return new Promise((resolve) => {
    let raw = "";
    req.on("data", (c) => (raw += c));
    req.on("end", () => {
      try {
        resolve(JSON.parse(raw || "{}"));
      } catch {
        resolve(null);
      }
    });
  });
}

const server = http.createServer(async (req, res) => {
  // 表單要供得出來，讀者才驗得到「瀏覽器會擋」那一段。
  // 只 grep form.html 有沒有那兩個屬性，證明的是檔案裡有那兩串字，不是瀏覽器會擋。
  if (req.method === "GET" && (req.url === "/" || req.url === "/form.html")) {
    // 表單的上下界在這裡又寫了一次。跟下面 POST 那段的 1 與 10 是兩份，
    // 改一邊不會動到另一邊，這就是文章講的「兩份會分岔」。
    const html = fs.readFileSync(new URL("../form.html", import.meta.url), "utf8")
      .replace("__MIN__", "1").replace("__MAX__", "10");
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    return res.end(html);
  }

  const m = req.url.match(/^\/orders(?:\/(\d+))?$/);
  if (!m) return json(res, 404, { error: "not found" });
  const id = m[1] ? Number(m[1]) : null;

  if (req.method === "GET" && id !== null) {
    const order = orders.get(id);
    return order ? json(res, 200, order) : json(res, 404, { error: "not found" });
  }

  if (req.method === "POST" && id === null) {
    const body = await readBody(req);
    if (!body) return json(res, 400, { error: "invalid json" });
    // 這是「加一支建立訂單的 API，記得驗證」拿回來的那種樣子：值域、型別、訊息都在。
    if (!Number.isInteger(body.quantity) || body.quantity < 1 || body.quantity > 10) {
      return json(res, 400, { error: "quantity must be an integer between 1 and 10" });
    }
    const newId = orders.size + 1;
    const order = { id: newId, itemId: String(body.itemId ?? ""), quantity: body.quantity };
    orders.set(newId, order);
    return json(res, 201, order);
  }

  if (req.method === "PATCH" && id !== null) {
    const body = await readBody(req);
    if (!body) return json(res, 400, { error: "invalid json" });
    const order = orders.get(id);
    if (!order) return json(res, 404, { error: "not found" });
    // 這是後來單獨要一支「可以改數量的」拿回來的那種樣子：能跑，驗證沒有跟過來。
    if (body.quantity !== undefined) order.quantity = body.quantity;
    return json(res, 200, order);
  }

  return json(res, 405, { error: "method not allowed" });
});

server.listen(0, "127.0.0.1", () => {
  process.stdout.write(`PORT=${server.address().port}\n`);
});
