// 修之前：AI 生的那一版。登入有做，授權沒做。
//
//   node before/server.mjs        # 印出 PORT=xxxxx
//
// 兩個問題，都留給 probe.sh 打出來，不是用讀的：
//   1. 查詢條件只有訂單編號，沒有問這張單是不是你的
//   2. 出錯的時候把後端細節原樣印出去
import { createServer } from "node:http";
import { db } from "../store.mjs";
import { appendAccess } from "../access-log.mjs";

// 登入那層。真的專案裡是 middleware，這裡簡化成一個標頭。
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
    const order = db.findOrder(m[1]);
    if (!order) throw new Error(`order ${m[1]} not in table "orders" (store.mjs:12)`);
    say(200, order, order.ownerId);
  } catch (e) {
    // 把例外原文吐給前端。訊息裡有資料表名稱跟檔案行號。
    say(500, { error: e.message });
  }
});

server.listen(0, "127.0.0.1", () => console.log(`PORT=${server.address().port}`));
