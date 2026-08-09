// 修好的版本。差別只有一件事：quantity 的規則有了一個落點，
// 兩支端點都去問同一個地方，而不是各自帶一份自己的。
import http from "node:http";
import fs from "node:fs";
import { QUANTITY_MIN, QUANTITY_MAX, checkQuantity } from "./rules.mjs";

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
    // 表單的上下界也來問同一份規則，所以它跟端點不可能走散。
    const html = fs.readFileSync(new URL("../form.html", import.meta.url), "utf8")
      .replace("__MIN__", String(QUANTITY_MIN)).replace("__MAX__", String(QUANTITY_MAX));
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
    const bad = checkQuantity(body.quantity);
    if (bad) return json(res, 400, { error: bad });
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
    if (body.quantity !== undefined) {
      const bad = checkQuantity(body.quantity);
      if (bad) return json(res, 400, { error: bad });
      order.quantity = body.quantity;
    }
    return json(res, 200, order);
  }

  return json(res, 405, { error: "method not allowed" });
});

server.listen(0, "127.0.0.1", () => {
  process.stdout.write(`PORT=${server.address().port}\n`);
});
