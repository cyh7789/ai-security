import { db } from "./store.mjs";

const PUBLIC_FIELDS = new Set(["id", "item", "total"]);

export default function getOrder(req, res) {
  const order = db.findOrder(req.params.id);

  if (!order || String(order.ownerId) !== String(req.user.id)) {
    return res.status(404).json({ error: "Order not found" });
  }

  if (req.query.fields === undefined) {
    return res.json(order);
  }

  if (typeof req.query.fields !== "string") {
    return res.status(400).json({ error: "Invalid fields parameter" });
  }

  const fields = [...new Set(req.query.fields.split(",").map((field) => field.trim()))];

  if (fields.length === 0 || fields.some((field) => !PUBLIC_FIELDS.has(field))) {
    return res.status(400).json({ error: "Invalid fields parameter" });
  }

  return res.json(Object.fromEntries(fields.map((field) => [field, order[field]])));
}
