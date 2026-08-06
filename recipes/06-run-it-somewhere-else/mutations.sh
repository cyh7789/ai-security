#!/usr/bin/env bash
# 故障注入：把隔離弄壞，看 verify.sh 會不會發現。
#
# 一份講「假綠燈」的驗證腳本，自己也可能發假綠燈。分辨的方法只有一個：
# **故意把要驗的東西弄壞，看它會不會紅。** 不會紅的那一條檢查沒有價值。
#
# 這支不會動到你的檔案：每一種突變都複製到 mktemp -d 裡改，跑完刪掉。
#
# 用法：
#   bash mutations.sh          全部
#   bash mutations.sh 3        只跑第 3 種
#
# 下面十三種都是真的發生過的假綠燈。前七種是第一版就有的，
# 後六種是外部審查打回來才補的，其中 10 與 11 只是把 8 換一個掛載點的名字。

set -u
ONLY="${1:-}"
HERE=$(cd "$(dirname "$0")" && pwd)
PASS=0; FAIL=0; N=0

# 每一種：<說明> <要改哪個檔> <perl 運算式> <跑哪一節>
run_case() {
  N=$((N+1))
  [ -n "$ONLY" ] && [ "$ONLY" != "$N" ] && return 0
  desc=$1; file=$2; expr=$3; sect=$4
  WS=$(mktemp -d)
  cp "$HERE"/*.sh "$HERE"/Dockerfile "$WS"/ 2>/dev/null
  perl -0pi -e "$expr" "$WS/$file" || { printf '  第 %s 種：突變寫不進去\n' "$N"; rm -rf "$WS"; return 1; }
  OUT=$(cd "$WS" && bash verify.sh "$sect" 2>&1)
  REDS=$(printf '%s' "$OUT" | grep -c '\[FAIL\]')
  if [ "$REDS" -gt 0 ]; then
    printf '  [抓到] %-38s 第 %s 節 %s 個紅燈\n' "$desc" "$sect" "$REDS"
    PASS=$((PASS+1))
  else
    printf '  [漏掉] %-38s 第 %s 節 全綠，這是假綠燈\n' "$desc" "$sect"
    printf '%s\n' "$OUT" | sed 's/^/         /'
    FAIL=$((FAIL+1))
  fi
  rm -rf "$WS"
}

printf '\n每一種都應該被抓到。有一個「漏掉」就代表那條檢查沒有鑑別力。\n\n'

run_case '拿掉 --network none'            flags.sh   's{^  --network none.*$}{  # 拿掉了}m'      2
run_case '拿掉 --read-only'               flags.sh   's{^  --read-only.*$}{  # 拿掉了}m'         3
run_case '拿掉 --cap-drop ALL'            flags.sh   's{^  --cap-drop ALL.*$}{  # 拿掉了}m'      3
run_case '拿掉 no-new-privileges'         flags.sh   's{^  --security-opt no-new.*$}{  # 拿掉了}m' 3
run_case '換成 --privileged'              flags.sh   's{^  --network none.*$}{  --privileged}m'  3
run_case '整個 /work 掛載不見'             verify.sh  's{-v "\$HERE:/work:ro" -w /work\)}{-w /work)}' 3
run_case '容器裡的腳本路徑不存在'           verify.sh  's{"\$IMAGE" /suspect\.sh 2>&1\); BOX_RC}{"\$IMAGE" /nope.sh 2>&1); BOX_RC}' 2
run_case '家目錄多掛一份到 /host2'          verify.sh  's{MOUNTS=\(-v "\$HERE/suspect\.sh}{MOUNTS=(-v "\$HOME:/host2:ro" -v "\$HERE/suspect.sh}' 2
run_case '整個根目錄掛到 /hostroot'         verify.sh  's{MOUNTS=\(-v "\$HERE/suspect\.sh}{MOUNTS=(-v "/:/hostroot:ro" -v "\$HERE/suspect.sh}' 2
run_case '掛到 /devdata（前綴長得像 /dev）' verify.sh  's{MOUNTS=\(-v "\$HERE/suspect\.sh}{MOUNTS=(-v "\$HOME:/devdata:ro" -v "\$HERE/suspect.sh}' 2
run_case '掛到 /etc/hostroot'             verify.sh  's{MOUNTS=\(-v "\$HERE/suspect\.sh}{MOUNTS=(-v "\$HOME:/etc/hostroot:ro" -v "\$HERE/suspect.sh}' 2
run_case '第 4 節不掛家目錄'                verify.sh  's{-v "\$HOME:/host:ro" }{}g'                4
run_case '偽造的 suspect.sh（印字樣就 exit 0）' suspect.sh 's{\A.*\z}{#!/bin/sh\necho "── 它同時做得到的事 ──"\necho "連不出去"\nexit 0\n}s' 2

printf '\n════════ 抓到 %s 種 / 漏掉 %s 種 ════════\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
