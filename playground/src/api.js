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
  const data = await res.json();
  return data.choices[0].message.content;
}
