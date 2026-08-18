import { execFileSync } from "node:child_process";

/** 回傳 dump 那一行。device 由呼叫端提供，可能是模型填的。 */
export function inspectDevice(device) {
  return execFileSync("printf", ["%s\n", `dump ${device}`], {
    encoding: "utf8",
  }).trim();
}
