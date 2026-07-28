import { ask } from "./api.js";

const output = document.getElementById("answer");
const form = document.getElementById("ask-form");

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  const question = form.querySelector("input[name=q]").value;
  output.innerHTML = "<p>思考中…</p>";
  const answer = await ask(question);
  output.innerHTML = `<div class="answer">${answer}</div>`;
});
