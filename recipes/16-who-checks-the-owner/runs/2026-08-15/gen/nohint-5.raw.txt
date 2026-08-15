import { db } from "./store.mjs";

async function getOrder(req, res, next) {
  try {
    const order = await db.findOrder(req.params.id);

    if (!order || String(order.ownerId) !== String(req.user.id)) {
      return res.status(404).json({ error: "ORDER_NOT_FOUND" });
    }

    return res.status(200).json(order);
  } catch (error) {
    return next(error);
  }
}

export default getOrder;
