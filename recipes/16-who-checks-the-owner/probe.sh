#!/usr/bin/env bash
# 對 before 或 after 打兩種流量，印出結果表，順手把存取紀錄留下來。
#
#   bash probe.sh before
#   bash probe.sh after
#
# 兩種流量：
#   正常   兩個人各讀自己的訂單
#   越權   一個 session 把訂單編號從 1001 數到 1008
#
# 判定看回傳的內容，不看狀態碼。狀態碼會騙人：500 也可能夾帶完整訂單，
# 200 也可能是空的。所以這裡比對的是「別人那張單的品名有沒有出現」。
set -u
cd "$(dirname "$0")"
DIR="${1:-before}"
[ -d "${DIR}" ] || { echo "沒有 ${DIR}/"; exit 2; }

mkdir -p logs
NORMAL="logs/${DIR}-normal.tsv"
SCAN="logs/${DIR}-scan.tsv"
rm -f "${NORMAL}" "${SCAN}"

log=$(mktemp)
ACCESS_LOG="${NORMAL}" node "${DIR}/server.mjs" > "$log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
for _ in $(seq 1 50); do grep -q '^PORT=' "$log" && break; sleep 0.1; done
PORT=$(sed -n 's/^PORT=//p' "$log" | head -1)
[ -n "${PORT:-}" ] || { echo "server 起不來"; cat "$log"; exit 2; }

get() {  # get <使用者> <session> <訂單編號>
  curl -s -H "x-user: $1" -H "x-session: $2" "http://127.0.0.1:${PORT}/orders/$3"
}

echo "=== ${DIR}：正常流量（各讀自己的） ==="
printf '  甲讀 1001：%s\n' "$(get 1 s-alice 1001)"
printf '  甲讀 1007：%s\n' "$(get 1 s-alice 1007)"
printf '  乙讀 1002：%s\n' "$(get 2 s-bob 1002)"
printf '  乙讀 1008：%s\n' "$(get 2 s-bob 1008)"
# 客服。正常流量裡本來就有人會碰到別人的訂單，這一段不是裝飾：
# 沒有它，「M 填多少」的答案會變成 1，而那條規則在真的系統上會整天叫。
printf '  客服查 1002：%s\n' "$(get 9 s-support 1002)"
printf '  客服查 1003：%s\n' "$(get 9 s-support 1003)"
printf '  客服查自己的 1009：%s\n' "$(get 9 s-support 1009)"

# 換一份紀錄檔，兩種流量分開存，偵測規則才有得對照。
kill $PID 2>/dev/null; wait $PID 2>/dev/null
ACCESS_LOG="${SCAN}" node "${DIR}/server.mjs" > "$log" 2>&1 &
PID=$!
for _ in $(seq 1 50); do grep -q '^PORT=' "$log" && break; sleep 0.1; done
PORT=$(sed -n 's/^PORT=//p' "$log" | head -1)

echo
echo "=== ${DIR}：甲把編號從 1001 數到 1008 ==="
LEAK=0
for id in $(seq 1001 1008); do
  body=$(get 1 s-scan "${id}")
  case "${body}" in
    *人體工學椅*|*螢幕支架*|*降噪耳機*|*行動電源*|*外接硬碟*|*腳踏墊*)
      verdict="拿到了別人的訂單"; LEAK=$((LEAK+1)) ;;
    *機械鍵盤*|*鍵帽組*) verdict="自己的，本來就看得到" ;;
    *) verdict="沒拿到" ;;
  esac
  printf '  /orders/%s  %-20s %s\n' "${id}" "${verdict}" "${body}"
done

echo
echo "=== ${DIR}：不存在的編號，錯誤訊息長什麼樣 ==="
printf '  /orders/9999：%s\n' "$(get 1 s-scan 9999)"

echo
printf '越權拿到 %s 張別人的訂單\n' "${LEAK}"
echo "紀錄：${NORMAL}（正常）、${SCAN}（掃描）"
