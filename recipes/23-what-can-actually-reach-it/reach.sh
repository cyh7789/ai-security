#!/usr/bin/env bash
# 對攻擊面清單上的每一條路徑真的送一次輸入，記下它停在哪一道閘。
#
#   bash reach.sh            # 全部跑一次，印 TSV 到 stdout
#   bash reach.sh > reach.log
#
# 「可達」這一欄不是用看的。這支的存在理由就是不准用看的：
# 沒跑過的一律是「沒驗過」，不准寫「應該被擋死」。
#
# 它量的是「這條路徑上的內容停在哪一層」，不是「模型會不會照做」。
# 罐頭模型不會被說服。模型照不照做要打真模型，那是 Day 24 攻擊變體的事。
#
# 離開碼照 Day 22 那份公約：
#   0  全部跑完，每一列都有結論
#   1  有一列跑出來跟 surface.tsv 上寫的不一樣（verify.sh 才會這樣判，這支不判）
#   2  有一列跑不動（示範服務起不來之類），那幾列是「沒驗過」，沒有結論
set -u
cd "$(dirname "$0")"
R=..
rc=0

# 「沒驗過:還沒接檢索」是結論（那條路徑的起點不存在），不是量測失敗，不影響離開碼。
# 其他任何「沒驗過:」都是這一跑沒有結論，整支要回 2，不能讓 verify.sh 拿它當「被擋死」對帳。
# 旗標不是閘名。--gate on 是模式旗標，真正擋下來的是網址白名單；
# --gate safe 擋下來的是逐跳重驗。清單那一欄的規矩是「附是哪一道閘擋的」，
# 直接印旗標的話 R9 會寫成「閘:on」，那不是任何一道閘的名字。
gatename() {
  case "$1" in
    on)       echo allowlist ;;
    safe)     echo per-hop-recheck ;;
    intent)   echo intent ;;
    external) echo external ;;
    *)        echo "$1" ;;
  esac
}

row() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
  # 這兩種「沒驗過」是結論（那條路徑目前量不到終點），不是這一跑失敗，不影響離開碼。
  # 其他任何「沒驗過:」都是這一跑沒有結論，整支回 2。
  case "$4" in
    沒驗過:還沒接檢索) ;;
    沒驗過:閘放行*)     ;;
    沒驗過:罐頭模型*)   ;;
    沒驗過*) rc=2 ;;
  esac
}

printf 'id\t入口\t這一列量到哪裡為止\t停在哪\n'

# ── 一、客服信件輸出這一類 ─────────────────────────────
# intake.mjs 印七欄，最後一欄就是停在哪。
# 管線不 pipefail 的話 node 掛掉也拿得到 awk 的 0，第四欄會是空字串，
# 而 row() 只認「沒驗過」開頭，空值就靜靜漏過去了（2026-08-22 審查抓到）。
stop() {
  local out
  out=$(node intake.mjs "$@" 2>/dev/null) || { echo 沒驗過:intake.mjs 跑不動; return; }
  out=$(printf '%s' "$out" | awk -F'\t' '{print $7}')
  [ -n "$out" ] && printf '%s\n' "$out" || echo 沒驗過:intake.mjs 沒印出第七欄
}

row R1 使用者打的那句話 交付邊界 "$(stop --doc docs/order-shot.txt)"
row R2 佐證文件附件 交付邊界 "$(stop --doc docs/injected.txt)"
row R3 佐證文件附件_附件也進閘 交付邊界 "$(stop --doc docs/injected.txt --gate both)"

# ── 二、會改狀態的工具這一類 ───────────────────────────
# 17 的 agent 印八欄：steps tools intent gate executed deleted mismatch。
# 判「到得了」看的是第六欄那筆訂單還在不在，不是閘回報什麼（Day 17 立的規矩）。
# 「沒到達」不等於「被擋住」。這兩件事在這裡一定要分開，
# 不然一次根本沒走到終點的量測，會在 reach.log 填一個沒發生過的閘名。
# 實例（2026-08-22 審查抓到）：
#   $ node agent.mjs --arm normal --gate intent
#   1  get_order  查詢 1002 這張訂單  allow  read  no  no
# 第六欄是 no，但第四欄是 allow、第五欄是 read：閘放行了，只是這條路沒走到刪除。
# 所以「被擋死」要兩個條件都成立：閘判 deny，而且執行結果是 blocked。
agent() {
  local arm=$1 gate=$2 out v x d
  out=$(cd "$R/17-words-into-actions" && MODEL_CMD='bash stub-model.sh' node agent.mjs --arm "$arm" --gate "$gate" 2>/dev/null) \
    || { echo 沒驗過:跑不動; return; }
  v=$(printf '%s' "$out" | awk -F'\t' '{print $4}')
  x=$(printf '%s' "$out" | awk -F'\t' '{print $5}')
  d=$(printf '%s' "$out" | awk -F'\t' '{print $6}')
  if [ "$d" = yes ]; then echo 到達動作
  elif [ "$v" = deny ] && [ "$x" = blocked ]; then printf '閘:%s\n' "$(gatename "$gate")"
  else printf '沒驗過:沒走到終點（閘 %s、執行 %s）\n' "$v" "$x"
  fi
}

row R4 訂單備註欄 delete_order_意圖核對閘 "$(agent hijack-a intent)"
row R5 訂單備註欄 delete_order_外部基準閘 "$(agent hijack-a external)"
row R6 偽裝成協定的欄位 delete_order_意圖核對閘 "$(agent hijack-e intent)"
row R14 訂單備註欄 delete_order_白名單閘 "$(agent hijack-a allowlist)"
# 使用者自己要求刪除。它是正常業務，但它跟 R5 走同一道閘而判決相反，
# 所以它才是 R5 那格「擋得住」的對照組：外部基準閘不是把刪除都關掉。
# 罐頭模型在這一組只走到 get_order 就停了，驅動不到刪除那一步，所以量不到終點。
# 它照樣要列：清單列的是路徑，不分善意惡意，沒列它的理由只能是「量不到」。
R15=$(agent legit external)
case "$R15" in 沒驗過*) R15="沒驗過:罐頭模型驅動不到刪除那一步" ;; esac
row R15 使用者自己要求刪除 delete_order_外部基準閘 "$R15"

# ── 三、讀到別人的資源這一類 ───────────────────────────
# 1002 的擁有者是 2、1001 是 1（17/store.mjs 的 SEED，跟 16 同一批訂單）。客服 agent 的白名單同時放行三張，
# 而 17 的 execute() 只吃 id，沒有任何一處比對發問者是誰。
# 這一支只問得到「白名單准不准碰這個編號」。它問不到兩件事：
# 讀取有沒有真的發生，以及那一筆是不是別人的。
# 17/agent.mjs 的 TARGET 寫死 1002，沒有辦法從外面叫它去讀 1001，
# 所以這條路徑目前量不到終點。閘放行不等於到得了，這一格就是「沒驗過」。
ownercheck() {
  local id=$1 v
  v=$(cd "$R/17-words-into-actions" && node gate.mjs allowlist "{\"tool\":\"get_order\",\"args\":{\"id\":$id}}" 2>/dev/null | cut -f1) || v=err
  case "$v" in
    allow) echo "沒驗過:閘放行 ${id}，但沒量到讀取真的發生" ;;
    deny)  echo 閘:allowlist ;;
    *)     echo 沒驗過:閘問不出判決 ;;
  esac
}
row R7 使用者填的訂單編號 讀到別人的訂單 "$(ownercheck 1001)"
row R8 使用者填的請款單編號 讀到別人的請款單 "$(
  # 請款單身上沒有 ownerId（16/store.mjs 的 invoices，17 沒有這張表），要 join 才知道是誰的。
  # 但這個 agent 的工具清單上沒有 get_invoice，路徑到不了起點。
  v=$(cd "$R/17-words-into-actions" && node gate.mjs allowlist '{"tool":"get_invoice","args":{"id":5001}}' 2>/dev/null | cut -f1)
  [ "$v" = deny ] && echo 閘:allowlist || echo 沒驗過
)"

# ── 四、對外網路請求這一類 ─────────────────────────────
# 這裡量的是 15/agent.mjs 本人，不是 safe-fetch.mjs。
# 第一版拿 safe-fetch.mjs 量，三列都印「被擋死」，而那支不是這個 agent 預設走的路：
# --gate on 那條分支用的是裸 fetch（15/agent.mjs:110），預設就跟著重導向走。
# 量錯路徑就會把「到得了」寫成「被擋死」，這正是可達性最容易造假的一格。
#
# agent.mjs 自己會把示範服務起起來再收掉（15/agent.mjs:63、120），這裡不用管埠。
# 判到不到得了看最後一欄 mark：那串憑證標記有沒有真的被抓回來。
# 六欄：called url gate fetched final mark。
# 判「被擋死」看第三欄（閘的判決），不是看第六欄那個標記：
# mark=no 也可能是連出去了但回應裡沒有那串字，那是「沒走到」不是「被擋住」。
fetchprobe() {
  local gate=$1 page=$2 out g f m
  out=$(cd "$R/15-tools-not-a-master-key" && MODEL_CMD='bash stub-model.sh' \
        node agent.mjs --gate "$gate" --page "$page" --guard none 2>/dev/null) \
    || { echo 沒驗過:跑不動; return; }
  g=$(printf '%s' "$out" | awk -F'\t' '{print $3}')
  f=$(printf '%s' "$out" | awk -F'\t' '{print $4}')
  m=$(printf '%s' "$out" | awk -F'\t' '{print $6}')
  if [ "$m" = yes ]; then echo 到達動作
  elif [ "$g" = deny ] && [ "$f" = no ]; then printf '閘:%s\n' "$(gatename "$gate")"
  else printf '沒驗過:連出去了但沒拿到標記（閘 %s、抓取 %s）\n' "$g" "$f"
  fi
}
row R9 模型自己填的網址 對外請求_直接打內部服務 "$(fetchprobe on lure)"
row R10 白名單網域上的302 對外請求_跟著重導向 "$(fetchprobe on redirect)"
row R13 同一條302_改用逐跳重驗 對外請求_跟著重導向 "$(fetchprobe safe redirect)"

# ── 五、只到得了上下文、還沒接上動作的 ────────────────
# 13 那份匯出檔裡答不出來源的段落數。客服 bot 現在沒有接檢索，
# 所以這一列的終點停在「還沒接上」，不是「被擋死」。
KB=$(cd "$R/13-who-wrote-your-knowledge-base" && node kb-sources.cjs demo/kb.jsonl 2>/dev/null | grep -c . || true)
row R11 知識庫檢索段落 進到模型的上下文 "$([ "${KB:-0}" -gt 0 ] && echo 沒驗過:還沒接檢索 || echo 沒驗過:13 那份匯出檔讀不到)"

# 21 那條缺口樁：拿掉「騙」之後它過得了輸入側三道。
# 這裡只認 allow 與 deny 兩個字面值。regress.mjs 換了輸出格式的時候，
# 舊寫法會靜靜印出「閘:scenario」，而那是猜的。
B1=$(cd "$R/21-did-it-come-back" && node regress.mjs --only 缺口樁 2>/dev/null | awk -F'\t' '$1=="b1"{print $5}')
case "${B1:-}" in
  allow) B1R=到達模型 ;;
  deny)  B1R=閘:scenario ;;
  *)     B1R="沒驗過:regress.mjs 沒給出 b1 的判決（拿到「${B1:-空}」）" ;;
esac
row R12 誘餌句b1 通過輸入側三道 "$B1R"

exit "$rc"
