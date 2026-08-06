#!/usr/bin/env bash
# 重抓所有來源，覆寫快照。改稿引到新來源時跑這支，然後 verify.sh 會比對線上與快照。
# 用法：bash posts/day06/sources/fetch.sh
set -u
cd "$(dirname "$0")"
get() {  # get <輸出檔> <網址>
  curl -sSL -m 40 -A 'Mozilla/5.0' "$2" | python3 -c '
import sys,re,html
h=sys.stdin.read()
h=re.sub(r"(?is)<(script|style|svg|nav|head)[^>]*>.*?</\1>"," ",h)
t=html.unescape(re.sub(r"(?s)<[^>]+>"," ",h))
t=re.sub(r"[ \t\xa0]+"," ",t)
sys.stdout.write(re.sub(r"\n\s*\n+","\n",t).strip())' > "$1"
  printf '  %-30s %s bytes\n' "$1" "$(wc -c < "$1" | tr -d ' ')"
}
echo "重抓（$(date +%F)）："
get docker-network-none.txt "https://docs.docker.com/engine/network/drivers/none/"
get docker-cli-run.txt      "https://docs.docker.com/reference/cli/docker/container/run/"
get embracethered-copilot-cve.txt "https://embracethered.com/blog/posts/2025/github-copilot-remote-code-execution-via-prompt-injection/"
# MSRC 的 CVE 頁是前端渲染的，抓 CVRF 這份 XML 才有內文。整份 3.9 MB，只留這個 CVE 的區塊。
# 注意 CVE 編號在檔案裡出現三次，前兩次在文件註記區，真正的 Vulnerability 元素是最後一次
curl -sSL -m 90 -A 'Mozilla/5.0' "https://api.msrc.microsoft.com/cvrf/v3.0/cvrf/2025-Aug" | python3 -c '
import sys,re,html
x=sys.stdin.read()
i=x.rfind("CVE-2025-53773")
a=x.rfind("<vuln:Vulnerability",0,i); b=x.find("</vuln:Vulnerability>",i)
t=html.unescape(re.sub(r"<[^>]+>"," ",x[a:b+21]))
sys.stdout.write(re.sub(r"[ \t]+"," ",t).strip())' > msrc-cve-2025-53773.txt
printf '  %-30s %s bytes\n' msrc-cve-2025-53773.txt "$(wc -c < msrc-cve-2025-53773.txt | tr -d ' ')"
