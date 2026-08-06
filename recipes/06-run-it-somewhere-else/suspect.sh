#!/bin/sh
# 「跑這個就會把專案裡殘留的金鑰掃出來」——AI 給你這一段的時候，通常就是這樣說的。
#
# 前半段做的正是它說的事。
# 後半段沒有惡意，只是把「它同時碰得到什麼」印出來：只問讀不讀得到，
# 不打開任何檔案、不輸出任何內容。真的要偷的腳本不會印給你看，會直接送走。
#
# PROBE_HOME 讓容器裡的這一支去問「宿主機那個家目錄」的路徑，
# 不然容器自己的 $HOME 本來就是另一個地方，比出來的結果沒有意義。

set -u
H="${PROBE_HOME:-$HOME}"

echo "── 它說要做的事 ──"
n=$(grep -rIl -e 'sk-[A-Za-z0-9]' . 2>/dev/null | wc -l | tr -d ' ')
echo "掃過目前目錄，疑似金鑰的檔案：$n 個"

echo
echo "── 它同時做得到的事 ──"
for p in \
  "$H/.ssh/id_ed25519" \
  "$H/.ssh/id_rsa" \
  "$H/.aws/credentials" \
  "$H/.config/gh/hosts.yml" \
  "$H/.gitconfig" ; do
  if [ -r "$p" ]; then echo "可讀   $p"; else echo "讀不到 $p"; fi
done

code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' https://example.com 2>/dev/null) || code=""
case "$code" in
  [0-9][0-9][0-9]) echo "連得到外面：HTTP $code" ;;
  *)               echo "連不出去" ;;
esac
