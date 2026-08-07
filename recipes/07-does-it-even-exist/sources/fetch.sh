#!/usr/bin/env bash
# 重抓所有來源，覆寫快照。快照過期就跑這支，跑完再按 README 那段迴圈核一次原句。
# 用法：bash sources/fetch.sh（在 recipe 目錄裡跑）
set -u
cd "$(dirname "$0")"
get() {  # get <輸出檔> <網址> [raw]
  if [ "${3:-}" = raw ]; then
    curl -sSL -m 40 -A 'Mozilla/5.0' "$2" -o "$1"
  else
    curl -sSL -m 40 -A 'Mozilla/5.0' "$2" | python3 -c '
import sys,re,html
h=sys.stdin.read()
h=re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>"," ",h)
t=html.unescape(re.sub(r"(?s)<[^>]+>"," ",h))
t=re.sub(r"[ \t\xa0]+"," ",t); t=re.sub(r" ([,.;:%])",r"\1",t)
sys.stdout.write(re.sub(r"\n\s*\n+","\n",t))' > "$1"
  fi
  printf '  %-46s %s bytes\n' "$1" "$(wc -c < "$1" | tr -d ' ')"
}
echo "重抓（$(date +%F)）："
get arxiv-2406.10279-abstract.txt "https://arxiv.org/abs/2406.10279"
get arxiv-2406.10279-fulltext.txt "https://arxiv.org/html/2406.10279v3"
get npm-ci-docs.txt            "https://docs.npmjs.com/cli/v11/commands/npm-ci"
get npm-audit-signatures.txt      "https://docs.npmjs.com/cli/v11/commands/npm-audit"
