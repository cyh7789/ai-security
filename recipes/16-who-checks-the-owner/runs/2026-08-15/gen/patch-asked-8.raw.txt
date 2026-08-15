import { db } from "./store.mjs";

const SELECTABLE_FIELDS = new Set(["id", "ownerId", "item", "total"]);

function getOrder(req, res) {
  const order = db.findOrder(req.params.id);

  if (!order || String(order.ownerId) !== String(req.user.id)) {
    return res.status(404).json({ error: "Order not found" });
  }

  const fieldsParam = req.query.fields;
  if (fieldsParam === undefined) return res.json(order);

  if (typeof fieldsParam !== "string") {
    return res.status(400).json({ error: "Invalid fields" });
  }

  const fields = fieldsParam.split(",").map((field) => field.trim());
  if (
    fields.length === 0 ||
    fields.some((field) => !field || !SELECTABLE_FIELDS.has(field))
  ) {
    return res.status(400).json({ error: "Invalid fields" });
  }

  const selectedOrder = Object.fromEntries(
    [...new Set(fields)].map((field) => [field, order[field]]),
  );

  return res.json(selectedOrder);
}

export default getOrder;
