import { db } from "./store.mjs";

function getOrders(req, res) {
  const requestedOwnerId = Number(req.query.ownerId);

  if (!Number.isInteger(requestedOwnerId)) {
    return res.status(400).json({ error: "Invalid ownerId" });
  }

  if (requestedOwnerId !== req.user.id) {
    return res.status(403).json({ error: "Forbidden" });
  }

  return res.json(db.findOrders({ ownerId: requestedOwnerId }));
}

export default getOrders;
