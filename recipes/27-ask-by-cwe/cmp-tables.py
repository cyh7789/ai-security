#!/usr/bin/env python3
"""比兩份 cwes 表：差異列的編號集合要剛好是指定的那幾條，而且只准差描述那一欄。

    python3 cmp-tables.py <表A> <表B> <只准差的編號>...

離開碼 0 符合、1 不符合。

為什麼不用 `diff | wc -l`：那個數字不管差的是哪兩列、也不管差在哪一欄。
把底稿的描述改回一致、再去動另外兩列的標題欄，行數照樣是 4 而檢查照樣綠。
"""
import sys


def load(path):
    rows = {}
    for line in open(path, encoding="utf-8"):
        if line.strip() and not line.startswith("#"):
            cols = line.rstrip("\n").split("\t")
            rows[cols[0]] = cols
    return rows


a, b = load(sys.argv[1]), load(sys.argv[2])
want = set(sys.argv[3:])

if set(a) != set(b):
    only_a = sorted(set(a) - set(b))
    only_b = sorted(set(b) - set(a))
    print(f"  兩份表的編號集合就不一樣了：只在 A 的 {only_a}、只在 B 的 {only_b}")
    sys.exit(1)

diff = {k for k in a if a[k] != b[k]}
if diff != want:
    print(f"  差異列是 {sorted(diff)}，期望 {sorted(want)}")
    sys.exit(1)

DESC = 3  # 第 4 欄（編號、答案、標題、描述）
for k in sorted(diff):
    cols = [i for i in range(max(len(a[k]), len(b[k]))) if a[k][i:i + 1] != b[k][i:i + 1]]
    if cols != [DESC]:
        print(f"  {k} 差在第 {[i + 1 for i in cols]} 欄，只准差第 {DESC + 1} 欄（描述）")
        sys.exit(1)

sys.exit(0)
