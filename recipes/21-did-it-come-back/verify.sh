#!/usr/bin/env bash
# 這一份自己的檢查。一發模型都不打。
#
#   bash verify.sh        # 全部
#   bash verify.sh 3      # 只跑第 3 條
#
# 這支會暫時改 recipe 18 的 gates.mjs（第 3、4 條要證明測試真的會紅），
# 所以還原走 trap，中途 Ctrl-C 也會還原，最後一條再核對一次還原乾淨了沒有。
set -u
cd "$(dirname "$0")"
ONLY="${1:-}"
command -v node >/dev/null || { echo "這份要 Node 才能跑，先裝 Node 再來。"; exit 2; }

PASS=0; FAIL=0
case_() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  [OK]   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
want() { [ -z "${ONLY}" ] || [ "${ONLY}" = "$1" ]; }
TAB=$(printf '\t')

GATES=../18-not-a-free-chatgpt/gates.mjs
BAK=$(mktemp)
cp "${GATES}" "${BAK}"
restore() { [ -f "${BAK}" ] && cp -f "${BAK}" "${GATES}"; return 0; }
trap 'restore; rm -f "${BAK}"' EXIT INT TERM

# 把判準改回某個壞掉的狀態，跑一次回歸測試，還原。回傳的是那次的退出碼。
# 兩個參數是 python 那邊的 old / new。
break_and_run() {
  python3 - "${GATES}" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1, f"找不到要改的那一行：{old[:40]}"
open(p, "w").write(s.replace(old, new))
PY
  # 逐條記下來是誰紅了。只收整體退出碼的話，「這次是哪幾條轉紅」在輸出裡沒有證據，
  # 而 d1 從頭到尾沒紅過這件事就看不出來（8/20 收斂後那輪抓到）。
  # 不要用 awk：macOS 的 awk 比中文欄位值會每一列都成立（recipe 19、20 各撞過一次），
  # 這裡用它會印出「轉紅的是 id B4 d1 b1」，連表頭都算進去。
  RED=$(node regress.mjs 2>/dev/null | grep -E "^(B4|d1|b1)${TAB}.*${TAB}紅$" | cut -f1 | tr '\n' ' ')
  restore
  [ -n "${RED}" ] && printf '        轉紅的是：%s\n' "${RED}"
  [ -z "${RED}" ]
}

BLACK_NOW='export const OUT_OF_SCOPE = ["詐", "冒充", "假冒", "偽裝成", "誘導", "套出"];'
BLACK_OLD='export const OUT_OF_SCOPE = ["騙", "詐", "冒充", "假冒", "偽裝成", "誘導", "套出"];'
SCEN_NOW='客服信件: ["客服信", "回覆客戶", "通知信", "公告", "信件開頭", "結尾", "語氣"],'
SCEN_OLD='客服信件: ["客服信", "回覆客戶", "通知信", "信件開頭", "結尾", "語氣"],'

# ── 1 三條現在全綠 ────────────────────────────────
if want 1; then
  case_ "1 三條回歸測試在現行判準下全綠"
  if node regress.mjs > /tmp/r21.out 2>&1; then
    ok "$(tail -1 /tmp/r21.out)"
  else
    bad "還有紅的：$(grep 紅 /tmp/r21.out | head -3 | tr '\n' ' ')"
  fi
fi

# ── 2 綁的輸入是撈來的，不是抄的 ─────────────────────
# 抄一份的話，改了固定集這裡不會跟著變，而測試還是綠的。
# 那時候它守的是抄下來的那句，不是防線真正面對的那句。
if want 2; then
  case_ "2 三句輸入都不在 regress.mjs 裡"
  M=""
  for pair in "14-same-attacks-every-time/benign.jsonl:B4" \
              "18-not-a-free-chatgpt/prompts/direct.tsv:d1" \
              "18-not-a-free-chatgpt/prompts/probe-bait.tsv:b1"; do
    f=../${pair%%:*}; id=${pair##*:}
    case "${f}" in
      *.jsonl) q=$(node -e '
        const fs=require("node:fs");
        const rows=fs.readFileSync(process.argv[1],"utf8").trim().split("\n").map(JSON.parse);
        process.stdout.write(rows.find(r=>r.id===process.argv[2]).question);' "${f}" "${id}") ;;
      *) q=$(awk -F'\t' -v k="${id}" '$1==k {print $2; exit}' "${f}") ;;
    esac
    [ -n "${q}" ] || { M="${M} ${id} 在來源檔裡找不到"; continue; }
    grep -qF "${q}" regress.mjs && M="${M} ${id} 被抄進 regress.mjs 了"
  done
  [ -z "${M}" ] && ok "B4／d1／b1 三句都只住在來源檔裡" || bad "對不上：${M}"
fi

# ── 3 把修補拿掉，測試會紅（黑名單那一半）──────────────
# 規格第 4 步：故意把修補拿掉確認它會紅。沒紅過的測試不算數。
if want 3; then
  case_ "3 「騙」加回黑名單，測試轉紅"
  if break_and_run "${BLACK_NOW}" "${BLACK_OLD}"; then
    bad "「騙」加回去之後測試竟然還是綠的：這三條斷言接不到 gates.mjs 的行為"
  else
    ok "加回去就紅，還原之後綠"
  fi
fi

# ── 4 把修補拿掉，測試會紅（場景清單那一半）────────────
# 這一半是 8/20 當天差點漏掉的：只拿掉「騙」B4 還是 deny，
# 它改成卡在允許清單。修補有兩層，測試就要兩層都咬得到。
if want 4; then
  case_ "4 「公告」從場景清單拿掉，測試轉紅"
  if break_and_run "${SCEN_NOW}" "${SCEN_OLD}"; then
    bad "拿掉「公告」之後測試還是綠的：B4 那條沒有真的在問「它會不會過」"
  else
    ok "拿掉就紅，還原之後綠"
  fi
fi

# ── 5 b1 那條釘的是缺口，方向不能被寫回去 ───────────────
# 它的期望是 allow。哪天有人「順手把它改成 deny 比較安全」，
# 這條會擋下來——那個改動要的是把「騙」加回去，那是誤擋跟缺口的取捨，不是筆誤。
if want 5; then
  case_ "5 b1 的期望值是 allow"
  E=$(node -e '
    const s=require("node:fs").readFileSync("regress.mjs","utf8");
    const i=s.indexOf(`id: "b1"`);
    const seg=s.slice(i, i+400);
    const m=seg.match(/expect:\s*(true|false)/);
    console.log(m ? m[1] : "找不到");')
  [ "${E}" = "true" ] && ok "b1 期望 allow，釘的是那個已知缺口" \
    || bad "b1 的 expect 是 ${E}，它應該是 true"
fi

# ── 6 兩個固定集都收了這次改動長出來的東西 ────────────────
if want 6; then
  case_ "6 攻擊集有 b1、應放行集有 B5"
  A=../14-same-attacks-every-time/attacks.jsonl
  B=../14-same-attacks-every-time/benign.jsonl
  M=""
  grep -q '"key":"21-bait-single-word"' "${A}" || M="${M} 攻擊集裡沒有 Day 21 那條"
  grep -q '"carrier":"gate"' "${A}" || M="${M} 那條的載體不是 gate（會被送去打模型）"
  grep -q '"id":"B5"' "${B}" || M="${M} 應放行集裡沒有 B5"
  (cd ../14-same-attacks-every-time && node collect.mjs --check > /dev/null 2>&1) \
    || M="${M} attacks.jsonl 跟來源分岔了"
  [ -z "${M}" ] && ok "攻擊集 $(grep -c . "${A}") 條、應放行集 $(grep -c . "${B}") 條，都跟來源一致" \
    || bad "對不上：${M}"
fi

# ── 7 形狀 vs 行為那支自己會判 ────────────────────────
if want 7; then
  case_ "7 形狀斷言綠、行為斷言紅"
  if bash shape-vs-behavior.sh > /tmp/svb21.out 2>&1; then
    ok "$(tail -1 /tmp/svb21.out)"
  else
    bad "shape-vs-behavior.sh 報紅：$(tail -2 /tmp/svb21.out | tr '\n' ' ')"
  fi
fi

# ── 8 跑完之後 gates.mjs 回到原樣 ───────────────────
# 這支動了別人的判準。示範跑完把別人的閘留在改過的狀態，是最糟的失敗。
if want 8; then
  case_ "8 gates.mjs 還原乾淨"
  if diff -q "${BAK}" "${GATES}" > /dev/null 2>&1; then
    ok "跟這支開跑之前逐字相同"
  else
    bad "gates.mjs 沒有還原：$(diff "${BAK}" "${GATES}" | head -4 | tr '\n' ' ')"
  fi
fi

printf '\n%d 綠 %d 紅\n' "${PASS}" "${FAIL}"
[ "${FAIL}" = 0 ]
