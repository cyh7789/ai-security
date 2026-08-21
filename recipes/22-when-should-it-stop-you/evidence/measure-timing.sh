#!/usr/bin/env bash
# Day 22 的事實基礎：每支 verify.sh 實際跑多久、需不需要金鑰。
# macOS 沒有 coreutils 的 timeout（實測 command not found），所以不設上限，自己盯。
# 分級（哪些綁 push、哪些排定時）要靠這張表，不是靠感覺。
set -u
cd ../..
OUT=./timing.tsv
printf 'recipe\t秒\t退出碼\n' > "${OUT}"
for d in */; do
  f="${d}verify.sh"
  [ -f "${f}" ] || continue
  n=$(basename "${d}")
  s=$(date +%s)
  (cd "${d}" && bash verify.sh) > "/tmp/day22-${n}.log" 2>&1
  rc=$?
  e=$(date +%s)
  printf '%s\t%s\t%s\n' "${n}" "$((e-s))" "${rc}" >> "${OUT}"
  printf '%-40s %3ss  rc=%s\n' "${n}" "$((e-s))" "${rc}"
done
echo "完成，表在 ${OUT}"
