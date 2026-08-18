#!/usr/bin/env bash
# 不花錢的假模型，讓你先確認整條流程跑得動：吃 stdin、吐一個修好的檔案。
# 它吐的是黑名單清字元那種修法 —— 讀起來像修好了，probe 會告訴你沒有。
set -u
cat > /dev/null
cat <<'EOF'
import { execSync } from "node:child_process";

export function inspectDevice(device) {
  const safe = String(device).replace(/[;&|`]/g, "");
  return execSync(`echo "dump ${safe}"`, { encoding: "utf8" }).trim();
}
EOF
