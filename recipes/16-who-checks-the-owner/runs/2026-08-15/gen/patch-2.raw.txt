import { db } from "./store.mjs";

const ORDER_FIELDS = new Set(["id", "ownerId", "item", "total"]);

export default function getOrder(req, res) {
  const order = db.findOrder(req.params.id);

  if (!order || order.ownerId !== req.user.id) {
    return res.status(404).json({ error: "Order not found" });
  }

  if (typeof req.query.fields !== "string") {
    return res.json(order);
  }

  const selectedOrder = {};
  for (const field of req.query.fields.split(",")) {
    if (ORDER_FIELDS.has(field)) selectedOrder[field] = order[field];
  }

  return res.json(selectedOrder);
}
