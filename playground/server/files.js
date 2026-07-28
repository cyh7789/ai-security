const express = require("express");
const fs = require("fs/promises");
const path = require("path");
const router = express.Router();

const UPLOAD_DIR = "/var/app/uploads";

router.get("/files/:name", async (req, res) => {
  const target = path.join(UPLOAD_DIR, req.params.name);
  try {
    const content = await fs.readFile(target);
    res.send(content);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
