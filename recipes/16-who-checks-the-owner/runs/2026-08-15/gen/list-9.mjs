import { db } from "./store.mjs";

function getOrders(req, res) {
  const ownerId = Number(req.query.ownerId);

  if (!Number.isSafeInteger(ownerId)) {
    return res.status(400).json({ error: "ownerId 格式錯誤" });
  }

  if (ownerId !== req.user.id) {
    return res.status(403).json({ error: "無權查看此使用者的訂單" });
  }

  return res.json(db.findOrders({ ownerId: req.user.id }));
}

export default getOrders;
