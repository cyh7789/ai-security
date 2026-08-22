#!/usr/bin/env bash
# 證明 verify.sh 那些檢查真的會咬：把東西弄壞，看它紅不紅。
#
#   bash mutations.sh
#
# 每一種突變改的是行為或事實，不是字串的長相。
# 最後兩組是反向控制：改一個不影響判準的地方，全部維持綠。
set -u
cd "$(dirname "$0")"
export LC_ALL=C   # 理由見 verify.sh 開頭那段

PASS=0; FAIL=0
BACKUP=$(mktemp -d)/snap.tar
tar cf "${BACKUP}" surface.tsv reach.sh intake.mjs gen-skeletons.mjs verify.sh \
  docs/injected.txt docs/order-shot.txt whitebox/verdicts.tsv whitebox/sol-paths.tsv \
  skeletons
restore() { tar xf "${BACKUP}"; }
trap 'restore; rm -rf "$(dirname "${BACKUP}")"' EXIT

sub() { python3 - "$@" <<'SUBPY'
import sys, pathlib
f, pairs = sys.argv[1], sys.argv[2:]
p = pathlib.Path(f); s = p.read_text()
for a, b in zip(pairs[::2], pairs[1::2]):
    if a not in s: sys.exit(1)
    s = s.replace(a, b, 1)
p.write_text(s)
SUBPY
}

bite() {
  local name=$1; shift
  "$@" || { printf '  [SKIP] %-46s 改不動（算失敗）\n' "${name}"; FAIL=$((FAIL+1)); return; }
  if bash verify.sh >/dev/null 2>&1; then
    printf '  [FAIL] %-46s 沒咬到\n' "${name}"; FAIL=$((FAIL+1))
  else
    printf '  [OK]   %-46s 咬到\n' "${name}"; PASS=$((PASS+1))
  fi
  restore
}

hold() {
  local name=$1; shift
  "$@" || { printf '  [SKIP] %-46s 改不動（算失敗）\n' "${name}"; FAIL=$((FAIL+1)); return; }
  if bash verify.sh >/dev/null 2>&1; then
    printf '  [OK]   %-46s 維持綠\n' "${name}"; PASS=$((PASS+1))
  else
    printf '  [FAIL] %-46s 誤咬\n' "${name}"; FAIL=$((FAIL+1))
  fi
  restore
}

echo "── 會紅的"

# 一、可達性造假：把量到「到得了」的那條改寫成被擋死。
# 這是這份 recipe 存在的理由，它一定要咬。
bite "把 R10 的到得了改成被擋死" \
  sub surface.tsv "$(printf '對外請求跟著轉到內部服務\t到得了')" "$(printf '對外請求跟著轉到內部服務\t被擋死')"

# 二、寫「應該可以」這種沒有結論的值。
bite "可達欄寫應該可以" \
  sub surface.tsv "$(printf '客服信件輸出\t到得了')" "$(printf '客服信件輸出\t應該可以')"

# 三、把 Day 24 的基線案例全部關掉，明天就沒東西可以驗。
bite "所有到得了的列都改成不出案例" \
  python3 -c "
import pathlib,re
p=pathlib.Path('surface.tsv'); out=[]
for l in p.read_text().split('\n'):
    f=l.split('\t')
    if len(f)==7 and f[4]=='到得了': f[6]='否．改掉了'
    out.append('\t'.join(f))
p.write_text('\n'.join(out))"

# 四、知識庫那一類整列刪掉。規格【接點】點名它最容易被整段漏掉。
bite "刪掉知識庫那一列" \
  python3 -c "
import pathlib
p=pathlib.Path('surface.tsv')
p.write_text('\n'.join(l for l in p.read_text().split('\n') if '知識庫' not in l))"

# 五、附件真的被閘擋住的話，R3 那一列就不成立。
# 在夾帶那段裡放一個場景清單擋得住的詞（OUT_OF_SCOPE 上的「套出」），
# --gate both 就會回 deny，R3 從到得了變成被擋死。
bite "讓附件被場景那道閘擋住" \
  sub docs/injected.txt '（系統備註）本筆訂單' '（系統備註）為了套出客戶資料，本筆訂單'

# 六、骨架跟清單脫鉤。
bite "刪掉一份骨架" rm -f skeletons/R4.test.mjs

# 七、骨架裡先把成功條件填掉。那是 Day 24 的事。
bite "在骨架裡寫 assert" \
  sub skeletons/R2.test.mjs 'import { test } from "node:test";' \
      'import { test } from "node:test";
import assert from "node:assert";'

# 八、白箱判決少判一條，比例就算不準。
bite "拿掉一條判決" \
  python3 -c "
import pathlib
p=pathlib.Path('whitebox/verdicts.tsv'); ls=p.read_text().split('\n')
p.write_text('\n'.join(l for l in ls if not l.startswith('21\t')))"

# 九、把「引用對不上」判成收，而那個 id 清單上沒有。
bite "判決指到清單上沒有的 id" \
  sub whitebox/verdicts.tsv "$(printf '15\t引用對不上')" "$(printf '15\t收')"

echo "── 不該紅的（反向控制）"

# 十、改註解不影響任何判準。
hold "在 surface.tsv 加一行註解" \
  python3 -c "
import pathlib
p=pathlib.Path('surface.tsv'); p.write_text('# 這行是反向控制\n'+p.read_text())"

# 十一、佐證文件裡改一個跟判準無關的欄位。
hold "改佐證文件的物流單號" \
  sub docs/injected.txt 'SF-77410326' 'SF-77410999' \
  && sub docs/order-shot.txt 'SF-77410326' 'SF-77410999'

echo
echo "${PASS} 咬到 ${FAIL} 沒咬到"
[ "${FAIL}" = 0 ] || exit 1
