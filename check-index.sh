#!/usr/bin/env bash
# 頂層 README 那張表，跟 recipes/ 底下實際有什麼，要對得上。
#
#   bash check-index.sh
#
# 為什麼需要它：那張表在 8/16 以前停在 06 停了十二天，中間補了十二份 recipe。
# 每天都有人跑 verify.sh，沒有人重讀 README，所以這件事只能靠一道機械檢查。
# 8/21 查到的實際狀況：全 repo 只有 18-not-a-free-chatgpt/verify.sh:371 呼叫它，
# 這道檢查等於掛在那一支身上，18 一沒跑它就不見了。CI 改成單獨跑這支。
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
