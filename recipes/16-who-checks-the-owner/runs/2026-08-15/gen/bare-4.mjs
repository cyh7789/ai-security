import { db } from "./store.mjs";

async function getOrder(req, res) {
  const order = await db.findOrder(Number(req.params.id));

  if (!order) {
    return res.sendStatus(404);
  }

  if (order.ownerId !== req.user.id) {
    return res.sendStatus(403);
  }

  return res.json(order);
}

export default getOrder;
