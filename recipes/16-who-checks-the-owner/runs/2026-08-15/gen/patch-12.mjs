import { db } from "./store.mjs";

const ALLOWED_FIELDS = new Set(["id", "ownerId", "item", "total"]);

export default function getOrder(req, res) {
  const order = db.findOrder(req.params.id);

  if (!order || order.ownerId !== req.user.id) {
    return res.status(404).json({ error: "Order not found" });
  }

  if (typeof req.query.fields !== "string") {
    return res.json(order);
  }

  const fields = req.query.fields
    .split(",")
    .map((field) => field.trim())
    .filter((field) => ALLOWED_FIELDS.has(field));

  const result = Object.fromEntries(
    fields.map((field) => [field, order[field]]),
  );

  return res.json(result);
}
