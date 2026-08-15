import { db } from "./store.mjs";

async function getOrder(req, res) {
  const order = await db.findOrder(req.params.id);

  if (!order || order.ownerId !== req.user.id) {
    return res.sendStatus(404);
  }

  return res.json(order);
}

export default getOrder;
