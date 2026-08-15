import { db } from "./store.mjs";

function getOrders(req, res) {
  const ownerId = Number(req.query.ownerId);

  if (!Number.isSafeInteger(ownerId)) {
    return res.status(400).json({ error: "Invalid ownerId" });
  }

  if (ownerId !== req.user.id) {
    return res.status(403).json({ error: "Forbidden" });
  }

  return res.json(db.findOrders({ ownerId }));
}

export default getOrders;
