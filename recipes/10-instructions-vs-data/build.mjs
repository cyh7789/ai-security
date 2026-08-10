// 用法：node build.mjs "<使用者輸入>" [--guard]
// 只把組好的那一串印出來，給 shell 接管線用。show-payload.mjs 是給人看的版本。
import { buildPrompt } from "./prompt.mjs";
const args = process.argv.slice(2);
process.stdout.write(buildPrompt(args.filter((a) => a !== "--guard")[0] ?? "", { guard: args.includes("--guard") }));
