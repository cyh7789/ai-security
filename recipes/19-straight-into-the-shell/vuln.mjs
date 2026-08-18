import { execSync } from "node:child_process";

/** 回傳 dump 那一行。device 由呼叫端提供。 */
export function inspectDevice(device) {
  return execSync(`echo "dump ${device}"`, { encoding: "utf8" }).trim();
}
