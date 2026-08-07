#!/usr/bin/env bash
# 故障注入：把腳本弄壞，看 verify.sh 會不會發現。
#
# 一支自己說「我分得出沒有跟沒問到」的腳本，最需要證明的就是這句話。
# 證明的方法只有一個：故意讓它分不出來，看驗證會不會紅。不會紅的那條檢查沒有價值。
#
# 這支不會動到你的檔案：每一種突變都複製到 mktemp -d 裡改，跑完刪掉。
#
#   bash mutations.sh      全部
#   bash mutations.sh 3    只跑第 3 種

set -u
ONLY="${1:-}"
HERE=$(cd "$(dirname "$0")" && pwd)
PASS=0; FAIL=0; N=0

# run_case <說明> <節> <要改哪個檔> <perl 運算式>...
run_case() {
  N=$((N+1))
  desc=$1; sect=$2; file=$3; shift 3
  if [ -n "${ONLY}" ] && [ "${ONLY}" != "${N}" ]; then return 0; fi
  WS=$(mktemp -d)
  cp "${HERE}"/*.sh "${WS}"/ 2>/dev/null
  for e in "$@"; do
    perl -0pi -e "${e}" "${WS}/${file}" || {
      printf '  第 %s 種：突變寫不進去\n' "${N}"; rm -rf "${WS}"; FAIL=$((FAIL+1)); return; }
  done
  if cmp -s "${HERE}/${file}" "${WS}/${file}"; then
    printf '  [無效] %-40s 突變沒改到任何一個字，這一條沒測到東西\n' "${desc}"
    rm -rf "${WS}"; FAIL=$((FAIL+1)); return
  fi
  OUT=$(cd "${WS}" && bash verify.sh "${sect}" 2>&1)
  REDS=$(printf '%s' "${OUT}" | grep -c '\[FAIL\]')
  if [ "${REDS}" -gt 0 ]; then
    printf '  [抓到] %-40s 第 %s 節 %s 個紅燈\n' "${desc}" "${sect}" "${REDS}"
    PASS=$((PASS+1))
  else
    printf '  [漏掉] %-40s 第 %s 節 全綠，這是假綠燈\n' "${desc}" "${sect}"
    printf '%s\n' "${OUT}" | sed 's/^/         /'
    FAIL=$((FAIL+1))
  fi
  rm -rf "${WS}"
}

DROP_CTRL='s{^if \[ "\$\{CTRL_YES\}".*?\nfi$}{}ms'

printf '\n每一種都應該被抓到。有一個「漏掉」或「無效」就代表那條檢查沒有鑑別力。\n\n'

# 對照組是整個 recipe 的地基，先打它
run_case '整組對照拿掉，連不到也照答' 1 check-pkgs.sh "${DROP_CTRL}"
run_case '連不到的時候改口說「沒有」'   1 check-pkgs.sh "${DROP_CTRL}" \
  's{printf .錯誤 }{printf q{沒有 }}'
run_case '把 404 判成「查到」'          1 check-pkgs.sh \
  's{^(  case "\$\{code\}" in)$}{  [ "\$\{code\}" = 404 ] && code=200\n$1}m'

# 輸入路徑
run_case '-f 不剝註解行'                2 check-pkgs.sh \
  's{local l=\$\{1%%#\*\}}{local l=\$1}'
run_case '剪貼簿路徑吃掉第一行'          2 check-pkgs.sh \
  's{^(elif \[ "\$\{1:-\}" = "-" \]; then\n)}{$1  IFS= read -r _drop\n}m'

# 下載數那一節
run_case '下載數一律回報成「?」'         3 check-pkgs.sh \
  's{^  dl=\$\{dl:-\?\}$}{  dl="?"}m'

# lockfile 對照
run_case '兩邊都用浮動版本，對照消失'    4 lockfile-demo.sh \
  's{"pinned:4\.19\.2"}{"pinned:^4.19.2"}'
run_case 'lockfile 套件數印成 1'        4 lockfile-demo.sh \
  's{\$\(deps "\$\{d\}"\)}{1}'

printf '\n════════ 抓到 %s 種 / 漏掉 %s 種 ════════\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = 0 ]
