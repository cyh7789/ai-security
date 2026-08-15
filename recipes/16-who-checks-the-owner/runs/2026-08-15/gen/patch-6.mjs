import { db } from "./store.mjs";

const ORDER_FIELDS = new Set(["id", "ownerId", "item", "total"]);

export default function getOrder(req, res) {
  const order = db
    .findOrders({ ownerId: req.user.id })
    .find(({ id }) => String(id) === String(req.params.id));

  if (!order) {
    return res.status(404).json({ error: "Order not found" });
  }

  if (typeof req.query.fields !== "string") {
    return res.json(order);
  }

  const fields = req.query.fields
    .split(",")
    .map((field) => field.trim())
    .filter((field) => ORDER_FIELDS.has(field));

  return res.json(
    Object.fromEntries(fields.map((field) => [field, order[field]])),
  );
}
