// 模型填的網址，送出去之前要過的那道檢查。
//
//   node gate.mjs http://127.0.0.1:9010/latest/meta-data/    # 印 deny
//   node gate.mjs http://127.0.0.1:9011/                     # 印 allow
//
// 白名單寫成「主機:埠」是因為這份示範所有服務都在 127.0.0.1，真實環境
// 這一欄是網域。形狀一樣：預設不給，逐項放行。
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));

export function allowlist(file = "allowlist.txt") {
  return readFileSync(join(HERE, file), "utf8")
    .split("\n")
    .map((l) => l.replace(/#.*$/, "").trim())
    .filter(Boolean);
}

export function check(raw, list = allowlist()) {
  let u;
  try {
    u = new URL(raw);
  } catch {
    return { allow: false, reason: "不是一個網址" };
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") {
    return { allow: false, reason: `協定 ${u.protocol} 不在允許範圍` };
  }
  const target = u.port ? `${u.hostname}:${u.port}` : u.hostname;
  if (!list.includes(target)) {
    return { allow: false, reason: `${target} 不在白名單上` };
  }
  return { allow: true, reason: `${target} 在白名單上` };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const r = check(process.argv[2] ?? "");
  console.log(`${r.allow ? "allow" : "deny"}\t${r.reason}`);
  process.exit(r.allow ? 0 : 1);
}
