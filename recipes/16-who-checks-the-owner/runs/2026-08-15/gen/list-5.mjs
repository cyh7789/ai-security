import { db } from "./store.mjs";

function getOrders(req, res) {
  const { ownerId } = req.query;

  if (typeof ownerId !== "string" || ownerId !== String(req.user.id)) {
    return res.status(403).json({ error: "Forbidden" });
  }

  return res.json(db.findOrders({ ownerId: req.user.id }));
}

export default getOrders;
