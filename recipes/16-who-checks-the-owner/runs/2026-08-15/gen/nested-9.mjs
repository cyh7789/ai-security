import { db } from "./store.mjs";

function getInvoice(req, res) {
  const invoice = db.findInvoice(req.params.id);

  if (!invoice) {
    return res.status(404).json({ error: "Invoice not found" });
  }

  const order = db.findOrder(invoice.orderId);

  if (!order || order.ownerId !== req.user.id) {
    return res.status(404).json({ error: "Invoice not found" });
  }

  return res.json(invoice);
}

export default getInvoice;
