// 對照組：不拼字串。指令釘死，參數走陣列，shell 從頭到尾沒有參與。
import { execFileSync } from "node:child_process";

export function inspectDevice(device) {
  return execFileSync("echo", ["dump", device], { encoding: "utf8" }).trim();
}
