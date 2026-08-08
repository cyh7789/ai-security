#!/usr/bin/env bash
# 跑 list-tools.sh 拿到工具描述，掃裡面有沒有在對模型下指令。
#
#   bash scan-descriptions.sh npx -y @modelcontextprotocol/server-filesystem /tmp/somewhere
#
# 離開碼分三種，因為「乾淨」跟「我沒問到」不能混在一起：
#   0  問到了，四類樣式一個都沒中
#   1  問到了，命中，逐條點名在上面
#   2  沒問到（server 起不來、逾時、沒給指令）。這不是乾淨。
#
# 這支只讀不寫。它會啟動你給的那個指令，理由跟 list-tools.sh 一樣。
#
# 掃的是描述的原文，所以它跟 list-tools.sh 走同一條資料路徑：
# list-tools.sh 一截斷，這支就掃不到藏在後半段的東西。故意這樣接的，
# 這樣「描述被截斷」這個壞法會同時讓兩支失效，而 mutations.sh 打得到它。
#
# 樣式命中不等於這台有惡意，也不等於沒中就安全：
# 這四類是已經公開過的手法的形狀，換一種寫法就繞得過去。它擋的是抄現成的那一批。

set -u
HERE=$(cd "$(dirname "$0")" && pwd)

command -v node >/dev/null 2>&1 || { echo "沒有 node，這支跑不了"; exit 2; }
[ "$#" -gt 0 ] || { echo "沒給啟動指令。用法：bash scan-descriptions.sh <指令...>"; exit 2; }

OUT=$(bash "${HERE}/list-tools.sh" "$@"); rc=$?
if [ "${rc}" != 0 ]; then
  printf '%s\n' "${OUT}"
  printf '沒問到就沒有掃到，離開碼 2。這不是「乾淨」。\n'
  exit 2
fi

printf '%s\n' "${OUT}" | head -1
printf '%s\n' "${OUT}" | node -e '
let s = "";
process.stdin.on("data", (d) => s += d).on("end", () => {
  // 四類樣式。分類是為了讓 verify.sh 能一類一類驗，少一類就少一個抓得到的形狀。
  // 大小寫一律不敏感（旗標在下面的 RegExp 裡）。
  // 撇號用 . 代掉（don.t）：來源可能打的是 U+2019 那個彎的，也可能是半形的，
  // 而這個檔本身是包在單引號裡餵給 node 的，寫不進半形撇號。
  const PATTERNS = [
    ["標籤", "<\\s*(important|system|critical|instruction|secret|hidden)"],
    ["路徑", "(~/\\.ssh|\\.ssh/|id_rsa|id_ed25519|\\.env\\b|mcp\\.json|\\.aws/credentials|\\.npmrc|\\.git-credentials|authorized_keys)"],
    ["隱瞞", "(do not mention|don.?t mention|without mentioning|do not tell|don.?t tell|without telling|do not inform|do not reveal|keep (this|it|that) (a )?secret)"],
    ["覆寫", "(ignore (all )?previous|ignore the above|disregard (all |the )?(previous|above)|override your (instructions|prompt)|your real instructions)"],
  ].map(([g, r]) => [g, new RegExp(r, "i")]);

  // list-tools.sh 的每一段開頭是這一行。工具名從這裡取，命中才點得出是哪一個工具。
  // 這一行本身也要掃：工具名字裡塞路徑的話，證據就在名字上。
  const HEAD = /^── 第 \d+ 個工具（共 \d+ 個）：(.+)，描述 \d+ 字元 ──$/;
  let tool = "(還沒進到任何工具)";
  const hits = [];
  for (const line of s.split("\n")) {
    const m = line.match(HEAD);
    if (m) tool = m[1];
    for (const [g, re] of PATTERNS) {
      const found = line.match(re);
      if (!found) continue;
      // 這裡截斷的是「證據那一行」，不是描述。完整描述 list-tools.sh 已經整份印過了。
      const around = line.length > 100 ? line.slice(0, 100) + " […]" : line;
      hits.push([tool, g, found[0], around]);
    }
  }
  if (!hits.length) {
    process.stdout.write("四類樣式（標籤／路徑／隱瞞／覆寫）一個都沒中。\n");
    process.stdout.write("那代表它沒有用已經公開過的那幾種寫法，不代表它安全。\n");
    process.exitCode = 0;
    return;
  }
  process.stdout.write("\n── 命中 " + hits.length + " 條 ──\n");
  for (const [t, g, what, around] of hits) {
    process.stdout.write(t + "  [" + g + "]  抓到「" + what + "」\n");
    process.stdout.write("    " + around + "\n");
  }
  process.stdout.write("\n這幾條是寫在工具描述裡的，模型每一輪都會收到，而你在 UI 上只看到工具名字。\n");
  process.exitCode = 1;
});
'
