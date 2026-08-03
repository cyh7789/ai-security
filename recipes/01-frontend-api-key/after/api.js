// 前端只跟自己的後端講話，不知道金鑰長什麼樣子。
// 網址是同源相對路徑，body 只有訊息本身。
export async function ask(question) {
  const res = await fetch("/api/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message: question }),
  });
  if (!res.ok) throw new Error(`backend returned ${res.status}`);
  const data = await res.json();
  return data.choices[0].message.content;
}
