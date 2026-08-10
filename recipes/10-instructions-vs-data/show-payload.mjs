// 用法：node show-payload.mjs "<使用者輸入>" [--guard]
// 印出真正會送進模型的那一整串字，以及一份接縫的清點。
import { INSTRUCTION, GUARD, SEP, USER_TAG, buildPrompt, countTag } from "./prompt.mjs";

const args = process.argv.slice(2);
const guard = args.includes("--guard");
const userText = args.filter((a) => a !== "--guard")[0] ?? "這個產品有保固嗎";

const head = guard ? INSTRUCTION + "\n" + GUARD : INSTRUCTION;
const payload = buildPrompt(userText, { guard });

console.log("──── 送出去的就是這一串 ────");
console.log(payload);
console.log("──── 清點 ────");
console.log(`你寫的  ${head.length} 字`);
console.log(`外來的  ${userText.length} 字`);
console.log(`分隔    ${JSON.stringify(SEP + USER_TAG)}，${(SEP + USER_TAG).length} 個字，而且它是文字`);
console.log(`[系統] 出現 ${countTag(payload, "[系統]")} 次，你只放了 ${countTag(head, "[系統]")} 次`);
console.log("");
console.log("你這支程式知道切點在第 " + head.length + " 個字，因為是它自己接的。");
console.log("模型收到的只有上面那一串，沒有這個數字。");
