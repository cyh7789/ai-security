// 修之後。跟 before/server.mjs 只差兩處，都標了註解。
//
//   node after/server.mjs
import { createServer } from "node:http";
import { db } from "../store.mjs";
import { appendAccess } from "../access-log.mjs";

const login = (req) => {
  const id = Number(req.headers["x-user"]);
  return Number.isInteger(id) && id > 0 ? { id } : null;
};

const server = createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  const m = url.pathname.match(/^\/orders\/(.+)$/);
  const user = login(req);
  const say = (code, body, ownerId) => {
    appendAccess({
      session: req.headers["x-session"] || "-",
      user: user ? user.id : "-",
      owner: ownerId ?? "-",
      path: url.pathname,
      status: code,
    });
    res.writeHead(code, { "content-type": "application/json; charset=utf-8" });
    res.end(JSON.stringify(body));
  };

  if (!user) return say(401, { error: "請先登入" });
  if (!m) return say(404, { error: "no route" });

  try {
    // 改動一：查詢條件多帶一個擁有者。不是先查回來再比對，是根本查不到。
    // 先查再比對也擋得住外洩，但那張單子已經進了這個行程的記憶體，
    // 之後任何一段 log 或錯誤處理都可能再把它印出去。
    const [order] = db.findOrders({ id: m[1], ownerId: user.id });
    // 改動二：查不到就是查不到。不分「沒這張單」跟「有但不是你的」，
    // 分開回答等於免費告訴對方哪些編號存在。
    if (!order) {
      // 回應不講是誰的，紀錄要講。紀錄是給自己看的，那一欄少掉的話
      // 擋下來的越權就變成一排看不出所以然的 404，Day 20 那條規則會沒東西可認。
      const real = db.findOrder(m[1]);
      return say(404, { error: "查無此訂單" }, real ? real.ownerId : "-");
    }
    say(200, order, order.ownerId);
  } catch {
    // 例外原文不出去。要查的人去看伺服器的紀錄。
    say(500, { error: "系統忙碌，請稍後再試" });
  }
});

server.listen(0, "127.0.0.1", () => console.log(`PORT=${server.address().port}`));
