# 唯一一份隔離旗標清單。run-isolated.sh 與 verify.sh 都 source 這一份。
#
# 為什麼要抽出來：兩邊各抄一份的話，「驗證過生效」講的就不是讀者手上那一份。
# 實測過，把 run-isolated.sh 的旗標整組刪光，verify.sh 照樣滿分。
#
# 每一行都是一個「本來會給、現在不給」的決定，不是樣板。

ISOLATION_FLAGS=(
  --network none                      # 不連外，容器裡只剩 loopback
  --read-only                         # 根檔案系統唯讀
  --tmpfs /tmp:rw,noexec,nosuid,size=16m   # 上一行擋掉之後真的需要暫存檔，只開這一格
  --cap-drop ALL                      # Linux capability 一個不留
  --security-opt no-new-privileges    # 跑起來之後不能再提權
  --pids-limit 128                    # 它跑瘋了不會把你的機器一起拖下去
  --memory 256m
)

# 容器裡應該只看得到這幾個掛載點（/proc、/sys、/dev 這些是執行環境自己的，不算）。
# 多出任何一個，就是有東西被你順手打開了。verify.sh 第 2 節會逐項比對。
ALLOWED_MOUNTS="/suspect.sh /work /tmp"
