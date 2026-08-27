#!/usr/bin/env python3
"""列出範例專案那七個檔之間的檔對檔引用，一行一條。

    python3 edges.py <playground 目錄>

數的是「邊」，不是「有引用語句的檔案數」。後者會把 orders.js 引用外部套件
那種也算進去，印出一個跟結論打架的數字。收檔規則跟前幾輪一致：`*.js`、排除 test。
"""
import pathlib
import re
import sys

if len(sys.argv) < 2:
    print("要給 playground 目錄", file=sys.stderr)
    sys.exit(2)

pg = pathlib.Path(sys.argv[1]).resolve()
files = sorted(p for p in pg.rglob("*.js") if p.is_file() and "test" not in p.parts)
names = {str(p.relative_to(pg)) for p in files}

edges = []
for path in files:
    for m in re.finditer(r"""(?:from|require\()\s*["']([^"']+)["']""", path.read_text()):
        target = m.group(1)
        if not target.startswith("."):
            continue  # 外部套件不算檔對檔
        resolved = (path.parent / target).resolve().relative_to(pg)
        for cand in (str(resolved), str(resolved) + ".js"):
            if cand in names:
                edges.append(f"{path.relative_to(pg)} -> {cand}")

for e in sorted(edges):
    print(e)
