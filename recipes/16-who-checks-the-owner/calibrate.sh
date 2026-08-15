#!/usr/bin/env bash
# M 填多少，是量出來的。
#
#   bash calibrate.sh                       # 用 after 那組紀錄
#   bash calibrate.sh logs/before-normal.tsv logs/before-scan.tsv
#
# 做法：拿自己的正常紀錄當底，把 M 從 1 往上掃，
# 找「正常紀錄零誤報、而且掃描紀錄還抓得到」的最小 M。
#
# 為什麼不能直接抄一個數字：M 量的是你的正常流量裡，
# 一個 session 合理會碰到幾個別人的資源。有客服、有對帳、有後台的系統，
# 那個數字天生就比較大。抄來的門檻只會讓你整天收到通知，然後把規則關掉。
set -u
cd "$(dirname "$0")"
NORMAL="${1:-logs/after-normal.tsv}"
SCAN="${2:-logs/after-scan.tsv}"
WINDOW="${WINDOW:-60}"
for f in "${NORMAL}" "${SCAN}"; do
  [ -f "$f" ] || { echo "沒有 $f，先跑 bash probe.sh after"; exit 2; }
done

printf '視窗 %s 秒\n\n' "${WINDOW}"
printf '%-4s %-14s %-14s %s\n' "M" "正常紀錄" "掃描紀錄" "能不能用"
PICK=""
for m in 1 2 3 4 5 6; do
  # 「沒有 session 命中」這一行裡面也有「命中」兩個字，數它就全都算命中。
  # 所以數的是命中那一行的形狀，不是關鍵字。
  fp=$(node detect.mjs "${NORMAL}" --window "${WINDOW}" --owners "$m" | grep -c '命中，' || true)
  tp=$(node detect.mjs "${SCAN}"   --window "${WINDOW}" --owners "$m" | grep -c '命中，' || true)
  if [ "${fp}" = 0 ] && [ "${tp}" != 0 ]; then
    verdict="可以"; [ -z "${PICK}" ] && PICK="$m"
  elif [ "${fp}" != 0 ]; then verdict="會誤報"
  else verdict="抓不到"
  fi
  printf '%-4s 誤報 %-9s 命中 %-9s %s\n' "$m" "${fp}" "${tp}" "${verdict}"
done

echo
if [ -n "${PICK}" ]; then
  printf '最小可用的 M 是 %s（視窗 %s 秒）。這是這份紀錄算出來的，換系統要重算。\n' "${PICK}" "${WINDOW}"
else
  echo "沒有一個 M 同時做到零誤報跟抓得到。要嘛換視窗，要嘛這條規則不適合你的流量。"
  exit 1
fi
