import { db } from "./store.mjs";

function getOrder(req, res) {
  const order = db.findOrder(Number(req.params.id));

  if (!order || order.ownerId !== req.user.id) {
    return res.status(404).json({ error: "Order not found" });
  }

  return res.json(order);
}

export default getOrder;
