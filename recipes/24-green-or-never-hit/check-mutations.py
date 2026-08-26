#!/usr/bin/env python3
"""找出沒有接在指令後面的參數行。

mutations.sh 曾經留下兩行舊參數（改寫那個突變的時候新舊都留下了），
shell 把它們當成指令執行、印 command not found，而腳本照樣回 0，
最後印「20 種抓到 0 種沒抓到」。bash -n 抓不到，那個語法完全合法。

判準是那個失敗的精確特徵：把續行接起來之後，一個邏輯行如果以引號開頭，
它就是被誤當成指令名的參數。這種行沒有第二種可能。
"""
import io, sys

path = sys.argv[1] if len(sys.argv) > 1 else "mutations.sh"
buf, start, bad = "", 0, []
for n, raw in enumerate(io.open(path, encoding="utf8"), 1):
    line = raw.rstrip("\n")
    if not buf:
        start = n
    if line.rstrip().endswith("\\"):
        buf += line.rstrip()[:-1]
        continue
    logical = (buf + line).strip()
    buf = ""
    if logical[:1] in ("'", '"'):
        bad.append((start, logical[:70]))

if bad:
    for n, t in bad:
        print(f"  第 {n} 行是沒有接在指令後面的參數，shell 會把它當指令執行：{t}")
    sys.exit(1)
print("沒有落單的參數行")
