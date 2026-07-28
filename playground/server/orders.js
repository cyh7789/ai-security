const express = require("express");
const router = express.Router();
const db = require("./db");

router.get("/orders/:id", async (req, res) => {
  const order = await db.query("SELECT * FROM orders WHERE id = ?", [
    req.params.id,
  ]);
  if (!order) {
    return res.status(404).json({ error: "not found" });
  }
  res.json(order);
});

router.post("/orders", async (req, res) => {
  const { itemId, quantity } = req.body;
  const order = await db.insert("orders", {
    user_id: req.session.userId,
    item_id: itemId,
    quantity,
  });
  res.json(order);
});

module.exports = router;
