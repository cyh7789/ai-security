import { db } from "./store.mjs";

function getOrder(req, res) {
  const order = db
    .findOrders({ ownerId: req.user.id })
    .find(({ id }) => String(id) === String(req.params.id));

  if (!order) {
    return res.status(404).json({ error: "Order not found" });
  }

  if (req.query.fields === undefined) {
    return res.json(order);
  }

  if (typeof req.query.fields !== "string") {
    return res.status(400).json({ error: "Invalid fields" });
  }

  const allowedFields = new Set(["id", "ownerId", "item", "total"]);
  const fields = [...new Set(req.query.fields.split(",").map((field) => field.trim()))];

  if (fields.some((field) => !allowedFields.has(field))) {
    return res.status(400).json({ error: "Invalid fields" });
  }

  return res.json(
    Object.fromEntries(fields.map((field) => [field, order[field]]))
  );
}

export default getOrder;
