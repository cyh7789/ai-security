// 存取紀錄。偵測規則要吃的就是這個。
//
// 欄位裡最重要的是 owner：**被碰到的那份資源屬於誰**。
// 大多數人的存取紀錄只有「誰在什麼時候打了哪個路徑」，
// 那種紀錄看不出越權，因為越權跟正常查詢在路徑上長得一模一樣。
import { appendFileSync, existsSync, writeFileSync } from "node:fs";

export const COLUMNS = ["ts", "session", "user", "owner", "path", "status"];
const FILE = () => process.env.ACCESS_LOG || "";

export function appendAccess(row) {
  const f = FILE();
  if (!f) return;
  if (!existsSync(f)) writeFileSync(f, `${COLUMNS.join("\t")}\n`);
  appendFileSync(f, [Date.now(), row.session, row.user, row.owner, row.path, row.status].join("\t") + "\n");
}
