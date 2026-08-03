// 金鑰待的地方：一台你控制的機器。
// 這支只解決「供應商金鑰不進瀏覽器」，還沒有身分驗證與額度限制，
// 公開部署前要補，否則會變成免費的模型端點。
import express from "express";

const app = express();
app.use(express.json({ limit: "16kb" }));

app.post("/api/chat", async (req, res) => {
  const message = req.body?.message;
  if (typeof message !== "string" || message.length === 0 || message.length > 4000) {
    return res.status(400).json({ error: "invalid message" });
  }

  try {
    const r = await fetch("https://api.example-model.com/v1/chat", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${process.env.PROVIDER_API_KEY}`,
      },
      signal: AbortSignal.timeout(30_000),
      body: JSON.stringify({
        model: process.env.PROVIDER_MODEL ?? "example-large",
        messages: [{ role: "user", content: message }],
      }),
    });
    return res.status(r.status).json(await r.json());
  } catch {
    return res.status(502).json({ error: "provider unavailable" });
  }
});

app.listen(process.env.PORT ?? 8787);
