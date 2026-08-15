import { db } from "./store.mjs";

function getInvoice(req, res) {
  const invoice = db.findInvoice(req.params.id);
  const order = invoice && db.findOrder(invoice.orderId);

  if (!invoice || !order || order.ownerId !== req.user.id) {
    return res.status(404).json({ error: "Invoice not found" });
  }

  return res.json(invoice);
}

export default getInvoice;
