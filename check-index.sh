#!/usr/bin/env bash
# 頂層 README 那張表，跟 recipes/ 底下實際有什麼，要對得上。
#
#   bash check-index.sh
#
# 為什麼需要它：那張表在 8/16 以前停在 06 停了十二天，中間補了十二份 recipe。
# 每天都有人跑 verify.sh，沒有人重讀 README，所以這件事只能靠閘。
# 每一份 recipe 的 verify.sh 最後一條會呼叫它，順便帶著它一起跑。
set -u
cd "$(dirname "$0")"

M=""
for d in recipes/*/; do
  n=$(basename "${d}")
  grep -qF "recipes/${n}/" README.md || M="${M}
  ${n} 有資料夾，README 那張表沒有它"
done

# 反向：表上指到的資料夾都要存在。改名之後留一列死連結，讀者點下去是 404。
while read -r p; do
  [ -d "${p}" ] || M="${M}
  README 指到 ${p}，但那個資料夾不存在"
done < <(grep -oE 'recipes/[0-9a-z-]+/' README.md | sort -u)

if [ -n "${M}" ]; then
  printf 'README 的 recipe 索引跟實際內容對不上：%s\n' "${M}"
  exit 1
fi
printf 'README 索引對得上，%s 份 recipe\n' "$(ls -d recipes/*/ | wc -l | tr -d ' ')"
