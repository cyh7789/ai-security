// 前端直接拿著供應商金鑰打 API。
// VITE_ 開頭的環境變數在 build 時會被字面替換進 bundle，
// 它叫環境變數沒錯，但那個環境是使用者的瀏覽器。
const API_KEY = import.meta.env.VITE_MODEL_API_KEY;

export async function ask(question) {
  const res = await fetch("https://api.example-model.com/v1/chat", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${API_KEY}`,
    },
    body: JSON.stringify({
      model: "example-large",
      messages: [{ role: "user", content: question }],
    }),
  });
  if (!res.ok) throw new Error(`provider returned ${res.status}`);
  const data = await res.json();
  return data.choices[0].message.content;
}
