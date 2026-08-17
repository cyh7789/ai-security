#!/usr/bin/env python3
"""guard-sentences.tsv 的 arm 分佈要對得上 results.tsv 的 guarded 欄。

    python3 check-guardlog.py <results.tsv> <guard-sentences.tsv>

對不上就把每一組印一行，全對就不印任何東西（呼叫端拿有沒有輸出當判準）。

為什麼需要這條：guarded 欄記的是「這條鏈有沒有防呆句」，留檔記的是句子本身。
落檔那段如果放在最後一次 classify 之前，classify 拋錯就會留下對不上任何一列的
孤兒句子，補跑同一格還會再寫一次。這兩個檔分岔的時候沒有別的東西會叫。
"""
import sys


def main() -> int:
    res, log = sys.argv[1], sys.argv[2]
    rows = [l.rstrip("\n").split("\t") for l in open(res, encoding="utf8") if l.strip()]
    head = rows[0]
    if "guarded" not in head:
        return 0  # 舊 schema，這一輪沒量這一欄
    ia, ig = head.index("arm"), head.index("guarded")

    want: dict[str, int] = {}
    for r in rows[1:]:
        if len(r) > ig:
            want[r[ia]] = want.get(r[ia], 0) + int(r[ig])

    got: dict[str, int] = {}
    for line in open(log, encoding="utf8"):
        if line.strip():
            a = line.split("\t")[0]
            got[a] = got.get(a, 0) + 1

    bad = []
    # 留檔裡出現 results.tsv 沒有的 arm，是純孤兒。只迭代 want 的話這一向永遠看不到，
    # 而那正是「落檔寫在判決之前、那一列最後沒進 results」會留下的痕跡。
    for a in sorted(set(got) - set(want)):
        bad.append(f"{a}: results.tsv 裡沒有這一組，留檔卻有 {got[a]} 句（孤兒）")
    for a, n in sorted(want.items()):
        g = got.get(a, 0)
        # 一條鏈可以貢獻多句，所以句數要 >= 鏈數；反過來 guarded=0 卻有句子是孤兒
        if n > 0 and g < n:
            bad.append(f"{a}: guarded={n} 但留檔只有 {g} 句")
        if n == 0 and g > 0:
            bad.append(f"{a}: guarded=0 但留檔有 {g} 句（孤兒）")
    for b in bad:
        print(b)
    return 0


if __name__ == "__main__":
    sys.exit(main())
