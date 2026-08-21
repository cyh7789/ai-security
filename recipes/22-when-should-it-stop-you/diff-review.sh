#!/usr/bin/env bash
# 把這次改動丟給你手邊的模型，要它列「可能引入的疏漏候選」。
#
#   bash diff-review.sh                    # 比 main
#   bash diff-review.sh HEAD~3             # 比某個 commit
#   REVIEW_CMD='codex exec' bash diff-review.sh
#
# 它印出候選清單，然後停在那裡。**判斷是你做的，這支不擋任何東西。**
#
# 為什麼不放進 CI：官方那個 actions/ai-inference 的 README 寫著
# 「The action is Copilot-only」，而且要 COPILOT_GITHUB_TOKEN 這個 secret
# （2026-08-22 查證）。要訂閱才跑得動的東西，不該是這個系列的必要步驟。
# 換成別家的 API 也一樣要把金鑰放進 repo secrets。
# 在本機跑不用金鑰進 CI，而且你手邊本來就有一個模型在用。
set -u
cd "$(dirname "$0")"
BASE="${1:-main}"

# 你的模型怎麼呼叫。這幾個是常見的，抓到哪個用哪個；
# 都沒有的話自己設 REVIEW_CMD，它要能吃 stdin 或把 prompt 當最後一個參數。
pick_cmd() {
  [ -n "${REVIEW_CMD:-}" ] && { echo "${REVIEW_CMD}"; return; }
  command -v claude  >/dev/null && { echo "claude -p"; return; }
  command -v codex   >/dev/null && { echo "codex exec"; return; }
  command -v gemini  >/dev/null && { echo "gemini -p"; return; }
  echo ""
}
CMD=$(pick_cmd)
if [ -z "${CMD}" ]; then
  cat <<'EOT'
找不到可以用的模型指令。設一個再跑：

  REVIEW_CMD='claude -p' bash diff-review.sh
  REVIEW_CMD='codex exec' bash diff-review.sh

不想裝 CLI 的話，把下面那段 prompt 加上 git diff 的內容，
貼進你平常在用的那個對話視窗，效果一樣。這一步本來就不該自動化到底。
EOT
  exit 2
fi

D=$(git -C ../.. diff "${BASE}...HEAD" -- recipes/ 2>/dev/null)
[ -n "${D}" ] || { echo "跟 ${BASE} 沒有差異，沒東西可以審。"; exit 0; }
LINES=$(printf '%s' "${D}" | grep -c '')

read -r -d '' P <<'EOT' || true
下面是一份 diff。你的工作是列出「這次改動可能引入的疏漏候選」，不是給我一份程式碼審查。

規則：
1. 每一條寫成一個可以被驗證的懷疑，附上它在 diff 裡的行。不要寫「建議加強錯誤處理」這種沒有對象的話。
2. 特別看這幾種：檢查在某個條件下會不會什麼都沒驗就回成功、新加的判斷會不會讓原本擋得住的東西過去、有沒有東西只在某一個作業系統上成立。
3. 你不確定的也列，標成不確定。漏報比誤報貴。
4. 最多十條。沒有的話就說沒有，不要湊。

你列的是候選，不是結論。判斷由人做。

diff：
EOT

printf '%s\n\n' "${P}"
printf '（%s 行 diff，模型：%s）\n\n' "${LINES}" "${CMD}"
printf '%s\n%s\n' "${P}" "${D}" | ${CMD} 2>/dev/null || {
  echo "那個指令跑不起來。手動的話：把上面那段 prompt 加 git diff 貼進你的對話視窗。"
  exit 2
}
printf '\n────\n這些是候選，不是結論。哪一條算數由你決定，這支不擋任何東西。\n'
