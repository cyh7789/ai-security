#!/usr/bin/env bash
# 驗一件事：平行跑的紅，是不是「共用同一份工作目錄」造成的。
# 做法跟 measure-parallel.sh 一樣平行跑 18／20／21，只差一件事：
# 每一支拿自己的一份 recipes 複本（模擬 CI 上一個 job 一個 checkout）。
# 預期：如果假紅的原因是共享狀態，這裡應該 10 輪全綠。
set -u
SRC=$(git rev-parse --show-toplevel)
N="${1:-10}"
OUT=./isolated.tsv
printf '跑法\t輪\t18\t20\t21\n' > "${OUT}"

one_isolated() { # $1=recipe 目錄名
  local ws; ws=$(mktemp -d)
  cp -R "${SRC}"/[a-z]* "${ws}/" 2>/dev/null
  (cd "${ws}/recipes/$1" && bash verify.sh > "/tmp/day22-iso-$1.log" 2>&1)
  local rc=$?
  rm -rf "${ws}"
  return ${rc}
}

for i in $(seq 1 "${N}"); do
  one_isolated 18-not-a-free-chatgpt & p1=$!
  one_isolated 20-what-did-it-block  & p2=$!
  one_isolated 21-did-it-come-back   & p3=$!
  wait ${p1}; a=$?
  wait ${p2}; b=$?
  wait ${p3}; c=$?
  printf '各自複本平行\t%s\t%s\t%s\t%s\n' "${i}" "${a}" "${b}" "${c}" >> "${OUT}"
done

echo "=== 失敗次數（18／20／21）==="
awk -F'\t' 'NR>1{n++; f18+=($3!=0); f20+=($4!=0); f21+=($5!=0)}
  END{printf "%d 輪\t18 紅 %d\t20 紅 %d\t21 紅 %d\n", n, f18, f20, f21}' "${OUT}"

cd "$(git rev-parse --show-toplevel)"
if git diff --quiet recipes/18-not-a-free-chatgpt/gates.mjs; then
  echo "本尊 gates.mjs 乾淨"
else
  echo "!! 本尊 gates.mjs 被動到了，隔離沒做到"
fi
