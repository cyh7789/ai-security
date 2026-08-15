import { db } from "./store.mjs";

async function getInvoice(req, res) {
  const invoice = await db.findInvoice(req.params.id);

  if (!invoice) {
    return res.status(404).json({ error: "Invoice not found" });
  }

  const order = await db.findOrder(invoice.orderId);

  if (!order || order.ownerId !== req.user.id) {
    return res.status(404).json({ error: "Invoice not found" });
  }

  return res.json(invoice);
}

export default getInvoice;
