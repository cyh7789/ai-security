// 有洞的原版。形狀取自我自己的 daemon：一個外部來的字串被拼進 shell 指令，
// 而且加了雙引號 —— 那對分號有效，對 $( ) 和反引號無效。
//
// 真實世界的同型：CVE-2025-59834（adb-mcp 的 inspect_ui），差別只在
// 那邊的字串是 LLM 填進工具參數的，而且那個參數有 Zod 型別驗證，驗證也通過了。
import { execFileSync } from "node:child_process";

/** 回傳 dump 那一行。device 由呼叫端提供，可能是模型填的。 */
export function inspectDevice(device) {
  return execFileSync("echo", [`dump ${device}`], { encoding: "utf8" }).trim();
}
