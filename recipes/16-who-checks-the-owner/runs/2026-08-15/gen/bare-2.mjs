import { db } from "./store.mjs";

async function getOrder(req, res) {
  const order = await db.findOrder(req.params.id);

  if (!order || order.ownerId !== req.user.id) {
    return res.status(404).json({ error: "Order not found" });
  }

  return res.json(order);
}

export default getOrder;
