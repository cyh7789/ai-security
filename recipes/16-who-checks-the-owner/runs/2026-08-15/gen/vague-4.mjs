import { db } from "./store.mjs";

function getOrder(req, res) {
  const order = db.findOrder(req.params.id);

  if (!order || String(order.ownerId) !== String(req.user.id)) {
    return res.status(404).json({ error: "Order not found" });
  }

  return res.json(order);
}

export default getOrder;
