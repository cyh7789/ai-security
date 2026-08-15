// 陽性對照：一份已知不綁身分的處理函式。
//
// 96 發全綠的時候，你沒辦法從結果本身分辨「模型都寫對了」跟「我的判準壞了」。
// 這一份的用途只有一個：證明 judge.mjs 抓得到不綁身分的程式碼。
import { db } from "../store.mjs";

export default function handler(req, res) {
  const order = db.findOrder(req.params.id);
  if (!order) return res.status(404).json({ error: "not found" });
  res.json(order);
}
