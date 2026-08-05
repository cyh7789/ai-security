// 修好的版本。answer 是資料，不是標記。
// 代價：模型回的 markdown 與程式碼區塊會變成純文字顯示。
// 要渲染就得接一個成熟的 sanitizer，然後依你允許的標籤、屬性與 URL scheme
// 訂出政策再測它。只列一張標籤白名單不夠，見 README「修法的代價，以及一條回頭路」。
import { ask } from "./api.js";

const output = document.getElementById("answer");
const form = document.getElementById("ask-form");

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  const question = form.querySelector("input[name=q]").value;
  output.textContent = "思考中…";
  const answer = await ask(question);
  const box = document.createElement("div");
  box.className = "answer";
  box.textContent = answer;
  output.replaceChildren(box);
});
