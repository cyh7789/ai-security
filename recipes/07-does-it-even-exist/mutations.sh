#!/usr/bin/env bash
# 故障注入：把腳本弄壞，看 verify.sh 會不會發現。
#
# 一支自己說「我分得出沒有跟沒問到」的腳本，最需要證明的就是這句話。
# 證明的方法只有一個：故意讓它分不出來，看驗證會不會判沒過。不會的那條檢查沒有價值。
#
# 這支不會動到你的檔案：每一種突變都複製到 mktemp -d 裡改，跑完刪掉。
#
#   bash mutations.sh      全部
#   bash mutations.sh 3    只跑第 3 種

set -u
ONLY="${1:-}"
HERE=$(cd "$(dirname "$0")" && pwd)
PASS=0; FAIL=0; UNTESTED=0; N=0; RAN=0

# 編號打錯的話，每一種突變都被 run_case 跳過，收尾算出「抓到 0 種 / 漏掉 0 種」
# 然後離開碼 0。一份專門用來證明「這裡沒有假通過」的工具，自己就不能有這種形狀。
# 不在這裡對照可用的種類數，因為那個數字會隨著突變增加而過期；改成收尾的時候
# 檢查到底跑了幾種（見檔尾）。這裡只擋非數字。
case "${ONLY}" in
  '') ;;
  *[!0-9]*) printf '種類編號要是數字，收到的是「%s」。\n' "${ONLY}" >&2; exit 2 ;;
esac

# run_case <說明> <節> <要改哪個檔> <perl 運算式>...
run_case() {
  N=$((N+1))
  desc=$1; sect=$2; file=$3; shift 3
  if [ -n "${ONLY}" ] && [ "${ONLY}" != "${N}" ]; then return 0; fi
  RAN=$((RAN+1))
  WS=$(mktemp -d)
  cp "${HERE}"/*.sh "${WS}"/ 2>/dev/null
  for e in "$@"; do
    perl -0pi -e "${e}" "${WS}/${file}" || {
      printf '  第 %s 種：突變寫不進去\n' "${N}"; rm -rf "${WS}"; FAIL=$((FAIL+1)); return; }
  done
  if cmp -s "${HERE}/${file}" "${WS}/${file}"; then
    printf '  [無效] %-40s 突變沒改到任何一個字，這一條什麼都沒驗到\n' "${desc}"
    rm -rf "${WS}"; FAIL=$((FAIL+1)); return
  fi
  OUT=$(cd "${WS}" && bash verify.sh "${sect}" 2>&1)
  REDS=$(printf '%s' "${OUT}" | grep -c '^  沒過')
  SKIPS=$(printf '%s' "${OUT}" | grep -c '^  沒有結論')
  if [ "${REDS}" -gt 0 ]; then
    printf '  [抓到] %-40s 第 %s 節 %s 個沒過\n' "${desc}" "${sect}" "${REDS}"
    PASS=$((PASS+1))
  elif [ "${SKIPS}" -gt 0 ]; then
    # 那一節整節被跳過（沒網路、api.npmjs.org 回 429），沒有一條沒過，不代表突變沒被抓到。
    # 算成漏掉會冤枉它，算成抓到就是這支自己在造假通過。兩個都不對，所以單獨報。
    printf '  [沒有結論] %-36s 第 %s 節整節跳過：%s\n' "${desc}" "${sect}" \
      "$(printf '%s' "${OUT}" | grep -m1 '^  沒有結論' | sed 's/^ *沒有結論 *//')"
    UNTESTED=$((UNTESTED+1))
  else
    printf '  [漏掉] %-40s 第 %s 節 全部通過，這是假通過\n' "${desc}" "${sect}"
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

# lockfile 對照
run_case '兩邊都用浮動版本，對照消失'    4 lockfile-demo.sh \
  's{"pinned:4\.19\.2"}{"pinned:^4.19.2"}'
run_case 'lockfile 套件數印成 1'        4 lockfile-demo.sh \
  's{\$\(deps "\$\{d\}"\)}{1}'
run_case '對照跑不出來也照樣往下印'      4 lockfile-demo.sh \
  's{^if \[ "\$\{ROWS\}" = 0 \]; then\n.*?\n  exit 2\nfi$}{}ms'

# 兩台主機、名字後面黏版本號
run_case '那台掛了卻不告訴你（印問號）'  1 check-pkgs.sh \
  's{    down\|bogus\) dl=錯誤 ;;.*\n}{    down|bogus) dl="?" ;;\n}'
run_case '那台掛了，收尾不出聲'          1 check-pkgs.sh \
  's{^if \[ -n "\$\{DL_MISSING\}" \]; then\n.*?\nfi$}{}ms'
run_case '那台掛了就整支拒答'            1 check-pkgs.sh \
  's{^    DL_STATE=down$}{    exit 2}m'
run_case '單顆問不到就印成 0'            1 check-pkgs.sh \
  's{\|\| dl=錯誤 ;;}{|| dl=0 ;;}'
run_case '名字後面的版本號不切'          2 check-pkgs.sh \
  's{^  case "\$\{p\}" in\n.*?\n  esac$}{}ms'
run_case '連 scoped 開頭的 @ 也切掉'     2 check-pkgs.sh \
  's{    \@\*\)     ;;.*\n}{}'
run_case '逃生口失效，off 也照樣去問'    1 check-pkgs.sh \
  's{if \[ "\$\{DL\}" = "off" \]; then}{if false; then}'
run_case '關掉跟壞掉共用同一句訊息'      1 check-pkgs.sh \
  's{\Qoff)  printf \E.*?\Q"api.npmjs.org" ;;\E}{off)  printf %s "「錯誤」不是「沒人下載」，是我沒問到。\\n" ;;}s'

# 週下載那一欄的四條路：問到數字、拿到負數、整台回垃圾、只有這一顆問不到。
# 這幾條之前一條突變都沒打過，而「編出來的數字」跟「量到的數字」印出來一模一樣。
run_case '問到數字也回報成「錯誤」'      1 check-pkgs.sh \
  's{if\(Number\.isInteger\(n\)&&n>=0\)process\.stdout\.write\(String\(n\)\)}{}'
run_case '那台回負數也照樣印出來'        1 check-pkgs.sh \
  's{&&n>=0}{}'
run_case '對照只看狀態碼，不看內容'      1 check-pkgs.sh \
  's{if \[ -z "\$\(dlnum "\$\{ctrl\}"\)" \]; then}{if [ "\$\{CTRL_DL\}" != "200" ]; then}'
run_case '單顆問不到說成整台問不到'      1 check-pkgs.sh \
  's{\*\)     why="這幾顆的下載數沒問到" ;;}{*)     why="下載數那台問不到" ;;}'
run_case '「關」那一格的補格數改掉'      1 check-pkgs.sh \
  's{\x27        關\x27}{\x27  關\x27}'

# 這一種打的是 verify.sh 自己。第 5 節是整份唯一真的裝套件的地方，擋住相依 preinstall
# 的東西就是那幾個 --ignore-scripts，不在 check-pkgs.sh 裡，所以突變的目標也在那裡。
run_case '裝的時候不關生命週期腳本'      5 verify.sh \
  's{ --ignore-scripts}{}g'

# 這裡數的是「跑了幾種」，不是把結果加起來。加總的版本每多一種結果分類就要記得
# 回來改一次，而漏改的後果正好是這支要抓的形狀：第 5 種明明跑了、只是這台機器
# 測不到，收尾卻回頭說「沒有第 5 種」，同一輪輸出前後打架。
if [ "${RAN}" -eq 0 ]; then
  printf '\n一種突變都沒跑到。%s可用的是 1 到 %s，或不給參數跑全部。\n' \
    "$([ -n "${ONLY}" ] && printf '沒有第 %s 種，' "${ONLY}")" "${N}" >&2
  exit 2
fi

printf '\n════════ 抓到 %s 種 / 漏掉 %s 種 / 沒有結論 %s 種 ════════\n' "${PASS}" "${FAIL}" "${UNTESTED}"
[ "${UNTESTED}" = 0 ] || printf '沒有結論的那幾種不要當成通過。\n'
[ "${FAIL}" = 0 ] && [ "${UNTESTED}" = 0 ]
