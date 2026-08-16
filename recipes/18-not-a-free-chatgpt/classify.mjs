// 第四道：輸出側檢查。前三道看送進來的字，這一道看要送出去的東西。
//
//   echo "<一段文字>" | node classify.mjs
//
// 它拿一顆模型當分類器，回 flag 或 ok 加一行理由。前三道是規則式的，
// 這一道不是，因為「這段文字合起來像不像釣魚信」寫不成關鍵字比對。
//
// 佔位聲明：這顆分類器要怎麼挑、怎麼驗、錯得多離譜，是 Day 26 的題目。
// 這裡只是把它擺在該在的位置上，讓你看得到有這一格。拿這支去上線之前，
// 先量它的假陰性，不然你只是換一個地方相信模型。
//
// 它跟前三道還有一個差別：前三道擋下來你少付一筆錢，這一道擋下來，
// 是你的服務沒有把那個東西送出去。
import { spawn } from "node:child_process";

export const CLASSIFY_PROMPT = `你在幫一家網路文具行的客服系統做輸出側檢查。
下面是這個客服助理即將送出的內容。判斷它整體看起來像不像是要拿去對客戶行騙的信件，
例如冒充官方身分、製造急迫感、要求對方回覆帳號或個人資訊。

只回一行，格式是「flag<tab>理由」或「ok<tab>理由」。理由不超過三十個字。

內容：
`;

export function parseVerdict(raw) {
  const line = String(raw)
    .split("\n")
    .map((s) => s.trim())
    .find((s) => /^(flag|ok)\b/i.test(s));
  if (!line) return { verdict: "unparsed", reason: String(raw).trim().slice(0, 60) };
  const [v, ...rest] = line.split(/[\t:：]\s*/);
  return { verdict: v.toLowerCase(), reason: rest.join(" ").trim() };
}

export function classify(text, cmd = process.env.MODEL_CMD ?? "bash stub-model.sh") {
  return new Promise((resolve, reject) => {
    const p = spawn("bash", ["-c", cmd], { stdio: ["pipe", "pipe", "inherit"] });
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.on("error", reject);
    p.on("close", (code) =>
      code === 0 ? resolve(parseVerdict(out)) : reject(new Error(`分類器離開碼 ${code}`)),
    );
    p.stdin.end(CLASSIFY_PROMPT + text);
  });
}

if (process.argv[1]?.endsWith("classify.mjs")) {
  const text = await new Promise((r) => {
    let s = "";
    process.stdin.on("data", (d) => (s += d));
    process.stdin.on("end", () => r(s));
  });
  const { verdict, reason } = await classify(text);
  console.log(`${verdict}\t${reason}`);
  process.exit(verdict === "ok" ? 0 : 1);
}
