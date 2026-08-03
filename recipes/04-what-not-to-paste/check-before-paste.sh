#!/usr/bin/env bash
# 貼給 AI 之前，先問這個檔案在不在你的紅線清單上。
#
# 用法：bash check-before-paste.sh <檔案>
#
# 離開碼刻意分成三種，因為「沒檢查成功」跟「檢查過而且乾淨」是兩回事：
#   0  不在紅線上
#   1  踩到紅線
#   2  這次沒有檢查成功，不要當成安全

die2() { echo "$1"; echo "  這次沒有檢查成功，不要當成它是乾淨的"; exit 2; }

[ $# -eq 1 ] || die2 "用法：bash check-before-paste.sh <要貼的檔案>"
T=$1

# 順序有意義：失效的 symlink 要先判，否則會被 -e 誤報成「找不到」，
# 而那兩件事該做的處置不一樣（一個是打錯字，一個是連結壞了）
if [ -L "$T" ] && [ ! -e "$T" ]; then
  die2 "這是一條失效的 symlink，它指向的東西不在了：$T"
fi
[ -e "$T" ] || die2 "找不到這個路徑：$T"
[ -d "$T" ] && die2 "這是一個目錄，不是要貼的檔案：$T"

# 解真實路徑。沒有它的話，指向 fixtures/ 的 symlink 會整條規則繞過去。
# 兩種失敗分開報，否則你會拿「權限不足」當成「這台沒裝 realpath」去查
command -v realpath >/dev/null 2>&1 \
  || die2 "這台沒有 realpath，symlink 那條規則沒辦法生效"
R=$(realpath "$T" 2>/dev/null) \
  || die2 "realpath 解不開這條路徑，可能是權限或循環連結：$T"

# 檔名規則與目錄規則要分開。併成一個 case 不會報錯，
# 但 basename 的結果永遠不含斜線，目錄 pattern 從此不成立
case "$(basename "$R")" in
  .env*|docker-compose.yml) echo "踩到紅線：$T"; exit 1 ;;
esac
case "$R" in
  */fixtures/*|*/config/secrets.*) echo "踩到紅線：$T"; exit 1 ;;
esac

echo "不在紅線清單上：$T"
