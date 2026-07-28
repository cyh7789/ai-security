const express = require("express");
const router = express.Router();

const startedAt = Date.now();

router.get("/health", (req, res) => {
  res.json({
    status: "ok",
    uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000),
    version: process.env.APP_VERSION || "dev",
  });
});

module.exports = router;
