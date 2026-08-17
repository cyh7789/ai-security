#!/usr/bin/env python3
"""GUARD_LOG 落檔的每一段都要有長度上界。

    python3 check-guardlen.py <guard-sentences.tsv> <上限>

超過上限就印出最長那段的長度，沒有就不印。

為什麼需要：斷句只靠標點的話，一段沒有句末標點、只用逗號串起來的回覆
會被當成「一句」整段寫進留檔，那就繞過了「組合後全文不落檔」這條硬約束。
長度上界是這條約束在 GUARD_LOG 這條路徑上唯一承重的防線
（切逗號只影響片段品質，切不切都被上界擋住）。
"""
import sys


def main() -> int:
    path, limit = sys.argv[1], int(sys.argv[2])
    longest = 0
    for line in open(path, encoding="utf8"):
        text = line.rstrip("\n").split("\t")[-1]
        longest = max(longest, len(text))
    if longest > limit:
        print(longest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
