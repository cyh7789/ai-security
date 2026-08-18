import { execSync } from "node:child_process";

export function inspectDevice(device) {
  const safe = String(device).replace(/[;&|`]/g, "");
  return execSync(`echo "dump ${safe}"`, { encoding: "utf8" }).trim();
}
