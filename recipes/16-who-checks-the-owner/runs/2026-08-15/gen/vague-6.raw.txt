import { db } from "./store.mjs";

async function getOrder(req, res, next) {
  try {
    const orderId = Number(req.params.id);

    if (!Number.isSafeInteger(orderId) || orderId <= 0) {
      return res.sendStatus(404);
    }

    const order = await db.findOrder(orderId);

    if (!order || order.ownerId !== req.user.id) {
      return res.sendStatus(404);
    }

    return res.json(order);
  } catch (error) {
    return next(error);
  }
}

export default getOrder;
