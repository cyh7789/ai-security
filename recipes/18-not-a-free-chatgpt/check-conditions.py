#!/usr/bin/env python3
"""run-conditions.txt 寫的發數，要對得上同一輪 results.tsv 真的有幾條。

    python3 check-conditions.py <run-conditions.txt> <results.tsv>

對不上就一組印一行，全對不印東西（呼叫端拿有沒有輸出當判準）。

為什麼需要：這條原本只盯一個寫死的輪次，於是後來新開的輪次整個在驗證範圍外，
而 Day 16 的教訓正是「補跑一組之後公開紀錄沒跟著改」。紀錄裡的發數兩種寫法都收：
逐組寫「split 12 條」，或每組一樣多時寫「各 12 條」。
"""
import re
import sys
from collections import Counter


def main() -> int:
    cond, res = sys.argv[1], sys.argv[2]
    text = open(cond, encoding="utf8").read()
    rows = [l.rstrip("\n").split("\t") for l in open(res, encoding="utf8") if l.strip()]
    ia = rows[0].index("arm")
    counts = Counter(r[ia] for r in rows[1:] if len(r) > ia)
    if not counts:
        print("results.tsv 一條資料都沒有")
        return 0

    same = len(set(counts.values())) == 1
    n_each = next(iter(counts.values()))
    each_ok = same and re.search(rf"各\s*{n_each}\s*條", text)

    bad = []
    for arm, n in sorted(counts.items()):
        if each_ok and arm in text:
            continue
        if not re.search(rf"{re.escape(arm)}\s*{n}\s*條", text):
            bad.append(f"{arm} 實際 {n} 條，紀錄裡找不到這個數字")

    total = sum(counts.values())
    # 總數只在有寫的時候查，寫了就要對
    m = re.search(r"共\s*(\d+)\s*條", text)
    if m and int(m.group(1)) != total:
        bad.append(f"紀錄寫共 {m.group(1)} 條，實際 {total} 條")

    for b in bad:
        print(b)
    return 0


if __name__ == "__main__":
    sys.exit(main())
