#!/usr/bin/env bash
# 21 那支會暫時改 18 的 gates.mjs。平行跑 18/20/21 會不會讓 18、20 假紅？
# 序列跑 N 次當對照，平行跑 N 次，比兩邊的紅次數。
# 只有一邊紅才算數：兩邊都紅代表是別的原因，跟平行無關。
set -u
cd ../..
N="${1:-10}"
OUT=./parallel.tsv
printf '跑法\t輪\t18\t20\t21\n' > "${OUT}"

one() {  # $1=recipe，回傳退出碼
  (cd "$1" && bash verify.sh > "/tmp/day22-par-$1.log" 2>&1)
}

for i in $(seq 1 "${N}"); do
  one 18-not-a-free-chatgpt; a=$?
  one 20-what-did-it-block;  b=$?
  one 21-did-it-come-back;   c=$?
  printf '序列\t%s\t%s\t%s\t%s\n' "${i}" "${a}" "${b}" "${c}" >> "${OUT}"
done

for i in $(seq 1 "${N}"); do
  one 18-not-a-free-chatgpt & p1=$!
  one 20-what-did-it-block  & p2=$!
  one 21-did-it-come-back   & p3=$!
  wait ${p1}; a=$?
  wait ${p2}; b=$?
  wait ${p3}; c=$?
  printf '平行\t%s\t%s\t%s\t%s\n' "${i}" "${a}" "${b}" "${c}" >> "${OUT}"
done

echo "=== 各跑法的失敗次數（18／20／21）==="
awk -F'\t' 'NR>1{n[$1]++; f18[$1]+=($3!=0); f20[$1]+=($4!=0); f21[$1]+=($5!=0)}
  END{for(k in n) printf "%s\t%d 輪\t18 紅 %d\t20 紅 %d\t21 紅 %d\n", k, n[k], f18[k], f20[k], f21[k]}' "${OUT}"

# 跑完 gates.mjs 一定要是乾淨的，不然這支自己就留了災難。
cd "$(git rev-parse --show-toplevel)"
if git diff --quiet recipes/18-not-a-free-chatgpt/gates.mjs; then
  echo "gates.mjs 乾淨"
else
  echo "!! gates.mjs 被留在改過的狀態，這本身就是發現"
  git diff --stat recipes/18-not-a-free-chatgpt/gates.mjs
fi
