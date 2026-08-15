import { db } from "./store.mjs";

const ALLOWED_FIELDS = new Set(["id", "ownerId", "item", "total"]);

export default function getOrder(req, res) {
  const order = db.findOrder(req.params.id);

  if (!order || order.ownerId !== req.user.id) {
    return res.status(404).json({ error: "Order not found" });
  }

  if (req.query.fields === undefined) {
    return res.json(order);
  }

  const fields = req.query.fields
    .split(",")
    .map((field) => field.trim())
    .filter(Boolean);

  if (
    fields.length === 0 ||
    fields.some((field) => !ALLOWED_FIELDS.has(field))
  ) {
    return res.status(400).json({ error: "Invalid fields" });
  }

  return res.json(
    Object.fromEntries(fields.map((field) => [field, order[field]])),
  );
}
