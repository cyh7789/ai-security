// 修好的版本。answer 是資料，不是標記。
// 代價：模型回的 markdown 與程式碼區塊會變成純文字顯示。
// 要渲染就得走白名單，只放行你自己列出來的標籤，那是另一件工程。
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
