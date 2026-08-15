import { db } from "./store.mjs";

async function getOrder(req, res) {
  const orderId = Number(req.params.id);

  if (!Number.isSafeInteger(orderId) || orderId < 1) {
    return res.status(400).json({ error: "Invalid order ID" });
  }

  const order = await db.findOrder(orderId);

  if (!order || order.ownerId !== req.user.id) {
    return res.status(404).json({ error: "Order not found" });
  }

  return res.json(order);
}

export default getOrder;
