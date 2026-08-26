#!/usr/bin/env bash
# 重抓 cwes.tsv 那十三條描述的來源頁。用法：bash cwe-pages/fetch.sh
#
# 為什麼要留快照：描述的措辭會動搖模型的答案（見 FINDINGS.md 那節），
# 所以那段字必須是一個不由我決定的東西，而「不由我決定」要驗得出來才算數。
set -u
cd "$(dirname "$0")"
for id in 78 22 79 798 639 209 89 502 611 327 190 1333 330; do
  curl -sSL -m 40 -A 'Mozilla/5.0' "https://cwe.mitre.org/data/definitions/${id}.html" | python3 -c '
import sys,re,html
h=sys.stdin.read()
h=re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>"," ",h)
t=html.unescape(re.sub(r"(?s)<[^>]+>"," ",h))
t=re.sub(r"[ \t\xa0]+"," ",t); t=re.sub(r" ([,.;:%])",r"\1",t)
sys.stdout.write(re.sub(r"\n\s*\n+","\n",t))' > "cwe-${id}.txt"
  printf '  cwe-%-6s %s bytes\n' "$id" "$(wc -c < "cwe-${id}.txt" | tr -d ' ')"
done
