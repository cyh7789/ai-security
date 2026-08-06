#!/usr/bin/env bash
# 06 它在哪裡跑
#
# 同一支 suspect.sh，換三個地方跑，比的是「它碰得到什麼」：
#   第 1 節  本機。它同時是後面每一條比較的對照組
#   第 2 節  容器，預設全關。掛載清單、家目錄讀不讀得到、連不連得出去
#   第 3 節  一發問四件事：/tmp 能寫、其他地方不能寫、capability 清空、不能提權
#   第 4 節  陷阱：只多加一個 -v 把家目錄掛進去，第 2 節的結論就整條翻掉
#
# 這份腳本自己的判準只有一條：**每一條「找不到」都要有一條「找得到」撐著。**
# 腳本沒跑起來、掛載沒生效、容器裡沒有 curl，症狀跟隔離成功長得一模一樣。
# 而且那個「找得到」不能由 suspect.sh 提供，它正是你還沒讀完的那支。
#
# 用法：
#   bash verify.sh          全部
#   bash verify.sh 3        只跑第 3 節
#
# 需要：bash、curl、docker（或 podman、nerdctl）。
# 沒有容器 CLI 的時候後三節跳過，而**跳過會讓離開碼變成 1**，不會假裝通過。

set -u
ONLY="${1:-}"
case "$ONLY" in
  ''|[1-4]) ;;
  *) printf '不認得的節號：%s\n用法：bash verify.sh [1-4]，不給參數就全部跑\n' "$ONLY" >&2
     exit 2 ;;
esac
PASS=0; FAIL=0; SKIP=0
ok()   { printf '  [OK]   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  [SKIP] %s\n' "$1"; SKIP=$((SKIP+1)); }
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=flags.sh
. "$HERE/flags.sh"
IMAGE="ai-security-day06-verify"

# 「沒裝」跟「裝了但引擎沒回應」是兩件事。混在一起的訊息會把人導向錯的方向
# （8/06 實測：OrbStack 更新中，docker 在 PATH 裡但 socket 回 EOF，
#  而當時的訊息印的是「找不到能用的 CLI」）
DOCKER=""; ENGINE_DOWN=""
for d in docker podman nerdctl; do
  command -v "$d" >/dev/null 2>&1 || continue
  if "$d" info >/dev/null 2>&1; then DOCKER=$d; break; else ENGINE_DOWN="$ENGINE_DOWN $d"; fi
done

readable() { printf '%s' "$1" | sed -n 's/^可讀   //p' | sort; }
online()   { printf '%s' "$1" | grep -q '^連得到外面'; }

# ── 1. 本機：它碰得到什麼 ────────────────────────────────
HOST_OUT=$(cd "$HERE" && sh suspect.sh 2>&1)
HOST_READ=$(readable "$HOST_OUT")
if want 1 || want 4; then
  printf '\n=== 1. 直接在本機跑，它碰得到什麼 ===\n'
  printf '%s\n' "$HOST_OUT" | sed 's/^/  | /'
fi
# 這一條不綁 want 1。綁了的話 `bash verify.sh 2` 會繞過對照組，
# 五個路徑一個都不存在的機器上照樣拿到「容器裡讀不到」的綠燈
if [ -n "$HOST_READ" ]; then
  want 1 && ok "本機讀得到 $(printf '%s\n' "$HOST_READ" | grep -c .) 個家目錄裡的檔案，後面的比較有對照組"
else
  bad "本機這五個路徑一個都讀不到，這台機器上這組比較沒有鑑別力。請改 suspect.sh 的清單成你真的有的檔案"
fi
if want 1; then
  if online "$HOST_OUT"; then ok "本機連得到外面"
  else bad "本機也連不出去（沒網路？），後面的網路比較會失去一半的對照"; fi
fi

finish() {
  printf '\n════════ %s 綠 / %s 紅 / %s 跳過 ════════\n' "$PASS" "$FAIL" "$SKIP"
  if [ "$SKIP" -gt 0 ]; then
    printf '跳過的那幾節沒有結論，所以離開碼算它不通過。\n'
    printf '`bash verify.sh && echo 通過` 不該在一台完全沒有容器隔離的機器上印出那句話。\n'
  fi
  if [ $((PASS + FAIL + SKIP)) -eq 0 ]; then
    printf '一項檢查都沒有執行，這不算通過\n' >&2
    exit 1
  fi
  [ "$FAIL" = 0 ] && [ "$SKIP" = 0 ]
  exit
}

# ── 沒有可用的容器 CLI 就到此為止 ────────────────────────
if [ -z "$DOCKER" ]; then
  if [ -n "$ENGINE_DOWN" ]; then
    # 這不是「這台機器不適用」，是「你要驗的東西壞了」，所以報紅不報跳過
    for n in 2 3 4; do want $n && bad "找到${ENGINE_DOWN} 但引擎沒有回應。先把它叫起來，這不是可以跳過的情況"; done
  else
    for n in 2 3 4; do want $n && skip "這台機器沒有裝 docker／podman／nerdctl"; done
  fi
  finish
fi

if want 2 || want 3 || want 4; then
  "$DOCKER" build -q -t "$IMAGE" "$HERE" >/dev/null || { printf '映像檔建不起來\n' >&2; exit 1; }
fi

# 旗標從 flags.sh 來，run-isolated.sh 用的是同一份。
# 兩邊各抄一份的時候，把 run-isolated.sh 的旗標刪光這裡照樣滿分（8/06 實測）
MOUNTS=(-v "$HERE/suspect.sh:/suspect.sh:ro" -v "$HERE:/work:ro" -w /work)
BASE=(--rm "${ISOLATION_FLAGS[@]}" "${MOUNTS[@]}")
# 網路對照組：從同一份清單濾掉 --network none，不要另外抄一份
NONET=(--rm); sk=0
for f in "${ISOLATION_FLAGS[@]}"; do
  [ "$f" = --network ] && { sk=1; continue; }
  [ "$sk" = 1 ] && { sk=0; continue; }
  NONET+=("$f")
done
NONET+=("${MOUNTS[@]}")

# 探針：不執行 suspect.sh，只問容器本身被架成什麼樣。
# 問的每一句都是這份腳本寫的，受測腳本偽造不了。
probe() {  # probe <額外旗標…>
  "$DOCKER" run "${BASE[@]}" "$@" "$IMAGE" -c '
    test -r /suspect.sh && test -d /work && echo SETUP_OK
    a=0; u=0; r=0
    for p in $CANARY_PATHS; do
      if   [ -r "$p" ]; then r=$((r+1))
      elif [ -e "$p" ]; then u=$((u+1))
      else                   a=$((a+1)); fi
    done
    echo "ABSENT=$a UNREADABLE=$u READ=$r"' 2>&1
}
cnt() { printf '%s' "$1" | sed -n "s/.*$2=\([0-9]*\).*/\1/p" | head -1; }
NC=$(printf '%s\n' "$HOST_READ" | grep -c .)

# ── 2. 容器，預設全關 ────────────────────────────────────
if want 2; then
  printf '\n=== 2. 同一支腳本，關進預設全關的容器 ===\n'
  P=$(probe -e "CANARY_PATHS=$(printf '%s' "$HOST_READ" | tr '\n' ' ')")
  printf '  | 探針（不跑 suspect.sh）：%s\n' "$(printf '%s' "$P" | tr '\n' ' ')"

  # 掛載清單。只問那幾條固定路徑不夠：家目錄多掛一份到 /host2、
  # 或整個根目錄掛到 /hostroot，那種探針完全瞎掉，而 token 拿得到（8/06 實測）
  # 前綴要有邊界。沒有的話 -v "$HOME:/devdata:ro" 或 -v "$HOME:/etc/hostroot:ro"
  # 會被當成 /dev 與 /etc 濾掉，整個家目錄在容器裡而這條印綠燈（8/06 實測）。
  # /etc 底下 docker 只會塞那三個檔案，其餘一律要現形
  SEEN=$("$DOCKER" run "${BASE[@]}" "$IMAGE" -c \
    'awk "\$2 !~ /^\/(proc|sys|dev)(\/|\$)/ && \$2 !~ /^\/etc\/(resolv\.conf|hosts|hostname)\$/ && \$2 != \"/\" {print \$2}" /proc/self/mounts | sort -u' 2>&1)
  # 只留最上層的那幾個。掛一個 /hostroot 進來會連帶冒出上百個子掛載點，
  # 全印出來訊息就沒人看得懂，而讀者要知道的只有「你多開了哪一個」
  EXTRA=""
  for m in $SEEN; do
    case " $ALLOWED_MOUNTS " in *" $m "*) continue ;; esac
    child=no
    for e in $EXTRA; do case "$m" in "$e"/*) child=yes; break ;; esac; done
    [ "$child" = no ] && EXTRA="$EXTRA $m"
  done
  if [ -n "$EXTRA" ]; then
    NE=$(printf '%s\n' $EXTRA | grep -c .)
    bad "容器裡多了白名單以外的掛載（${NE} 個，最上層的是：$(printf '%s' "$EXTRA" | cut -c1-60)）。「多出來一項就是有東西被你順手打開了」講的就是這個"
  else
    ok "容器裡看得到的掛載就是 flags.sh 白名單那三個，沒有多"
  fi

  BOX_OUT=$("$DOCKER" run "${BASE[@]}" -e "PROBE_HOME=$HOME" "$IMAGE" /suspect.sh 2>&1); BOX_RC=$?
  printf '%s\n' "$BOX_OUT" | sed 's/^/  | /'
  case "$P" in *SETUP_OK*) SETUP=yes ;; *) SETUP=no ;; esac
  if [ "$SETUP" = no ]; then
    bad "容器沒有被架起來（/suspect.sh 或 /work 不在），下面每一條「讀不到」都不代表任何事"
  else
    ok "掛載到位、腳本在容器裡（這句由驗證腳本自己的探針證明，不是 suspect.sh 說的）"
    if [ "$NC" = 0 ]; then
      bad "沒有 canary 可用（本機一個檔案都讀不到），探針那條「讀不到」沒有意義"
    elif [ "$(cnt "$P" ABSENT)" = "$NC" ]; then
      ok "探針去找那 ${NC} 個檔案，${NC} 個都不存在。家目錄真的沒進來"
    elif [ "$(cnt "$P" READ)" != 0 ]; then
      bad "探針還讀得到家目錄的檔案，隔離沒有生效"
    else
      bad "那幾個檔案在容器裡存在卻讀不到，代表有東西被掛進來了，只是權限擋著"
    fi
    [ "$BOX_RC" = 0 ] || bad "suspect.sh 在容器裡的離開碼是 ${BOX_RC}，它自己沒跑完"
    if [ -z "$(readable "$BOX_OUT")" ]; then
      ok "suspect.sh 的輸出跟探針一致：本機讀得到的那幾條，容器裡一條都讀不到"
    else
      bad "容器裡還讀得到家目錄的檔案，隔離沒有生效"
    fi
    # 網路的正向對照：同一份旗標濾掉 --network none 再跑一發，要連得到
    NET_OUT=$("$DOCKER" run "${NONET[@]}" -e "PROBE_HOME=$HOME" "$IMAGE" /suspect.sh 2>&1)
    printf '  | 對照組（同一份旗標，只濾掉 --network none）：%s\n' "$(printf '%s' "$NET_OUT" | tail -1)"
    if ! online "$NET_OUT"; then
      bad "濾掉 --network none 之後容器還是連不出去，代表裡面的 curl 不能用（換過 base image？），這一節的網路檢查沒有鑑別力"
    elif online "$BOX_OUT"; then
      bad "--network none 之下還連得出去"
    else
      ok "同一個容器不加旗標連得到、加了連不到，所以擋住它的是 --network none"
    fi
  fi
fi

# ── 3. 唯讀、capability、提權 ────────────────────────────
if want 3; then
  printf '\n=== 3. 一發問四件事：/tmp 能寫、其他地方不能寫、capability 清空、不能提權 ===\n'
  # 「/work 寫不進去 + /tmp 寫得進去」只驗得到 :ro 那個 bind。
  # --read-only 與 --tmpfs 一起消失的時候，/tmp 寫得進去是因為整個根檔案系統都能寫，
  # 而那兩條照樣印同一句綠燈（8/06 實測）。所以對照組要換方向：
  # 問的不是「/tmp 寫不寫得進去」，是「/tmp 以外的地方寫不寫得進去」
  R=$("$DOCKER" run "${BASE[@]}" "$IMAGE" -c '
    test -e /work/suspect.sh || { echo NOMOUNT; exit 9; }
    touch /tmp/ok 2>/dev/null && echo TMP_OK
    touch /home/runner/x 2>/dev/null && echo ROOTFS_WRITABLE
    touch /work/PWNED 2>/tmp/e && echo WORK_WRITABLE || cat /tmp/e
    # 看 CapBnd 不看 CapEff：容器裡是非 root 的時候 CapEff 一律全 0，
    # 不管你有沒有下 --cap-drop ALL，連 --privileged 都是 0。實測（8/06）：
    #   什麼都不加  CapBnd=00000000a80425fb   --privileged  CapBnd=000001ffffffffff
    #   --cap-drop ALL  CapBnd=0000000000000000
    grep -qE "^CapBnd:[[:space:]]*0+$" /proc/self/status && echo NOCAP
    grep -qE "^NoNewPrivs:[[:space:]]*1$" /proc/self/status && echo NNP
    exit 0' 2>&1); R_RC=$?
  printf '  | %s（離開碼 %s）\n' "$(printf '%s' "$R" | tr '\n' ' ')" "$R_RC"
  if [ -e "$HERE/PWNED" ]; then
    rm -f "$HERE/PWNED"
    bad "唯讀掛載沒擋住，檔案真的寫進 recipe 目錄了"
  fi
  case "$R" in
    *NOMOUNT*) bad "/work 上根本沒有掛載，這一節量到的是空目錄不是唯讀" ;;
    *)
      N=0
      case "$R" in *TMP_OK*) ;; *) bad "連 /tmp 都寫不進去，其他三條的「寫不進去」證明不了什麼"; N=1 ;; esac
      case "$R" in *ROOTFS_WRITABLE*) bad "根檔案系統寫得進去，--read-only 沒有生效"; N=1 ;; esac
      case "$R" in *WORK_WRITABLE*)   bad "/work 寫得進去，那個 :ro 沒有生效"; N=1 ;; esac
      case "$R" in *NOCAP*) ;; *) bad "CapBnd 不是全 0，--cap-drop ALL 沒生效（或有人加了 --privileged）"; N=1 ;; esac
      case "$R" in *NNP*)   ;; *) bad "NoNewPrivs 不是 1，no-new-privileges 沒生效"; N=1 ;; esac
      [ "$N" = 0 ] && ok "/tmp 能寫、根檔案系統與 /work 都不能寫、capability 全清、不能再提權，四樣一起成立" ;;
  esac
fi

# ── 4. 陷阱：多一個 -v ───────────────────────────────────
if want 4; then
  printf '\n=== 4. 只多加一行 -v，第 2 節的結論就沒了 ===\n'
  # 跟第 2 節唯一的差別：家目錄掛在 /host。網路一樣關著，唯讀一樣開著
  if [ "$NC" = 0 ]; then
    bad "沒有 canary 可用（本機一個檔案都讀不到），這一節的對照做不起來"
  else
    MAPPED=$(printf '%s\n' "$HOST_READ" | sed "s|^$HOME|/host|" | tr '\n' ' ')
    TP=$(probe -v "$HOME:/host:ro" -e "CANARY_PATHS=$MAPPED")
    printf '  | 探針：%s\n' "$(printf '%s' "$TP" | tr '\n' ' ')"
    # 「掛載有沒有生效」要用掛載本身證明，不要用「讀不讀得到」。
    # 原生 Linux 上 ~/.ssh 是 0700，容器裡的 uid 連 traverse 都不行，
    # [ -e ] 直接是假，於是計進 ABSENT。用讀取當判準的話，
    # 一個掛載完全正常的 Linux 讀者會拿到「掛了卻找不到」的紅燈，被叫去查一個不存在的問題
    MNT=$("$DOCKER" run "${BASE[@]}" -v "$HOME:/host:ro" "$IMAGE" -c \
      'awk "\$2 == \"/host\" {print \"MOUNTED\"}" /proc/self/mounts' 2>&1)
    R_READ=$(cnt "$TP" READ); R_UNREAD=$(cnt "$TP" UNREADABLE)
    # 只看這一節自己那發探針。混進第 2 節的 $P 會讓 `bash verify.sh 4` 單跑直接死在
    # unbound variable，而單跑正是 README 教讀者做的事
    case "$TP" in *SETUP_OK*) TP_OK=yes ;; *) TP_OK=no ;; esac
    if [ "$TP_OK" = no ]; then
      bad "第 4 節那一發容器沒有跑起來，比不出東西：$(printf '%s' "$TP" | tr '\n' ' ')"
    elif [ "$MNT" != MOUNTED ]; then
      bad "/host 沒有出現在容器的掛載表裡，掛載根本沒生效"
    elif [ "${R_READ:-0}" -gt 0 ] 2>/dev/null; then
      ok "/host 掛進去了，而且探針讀得到 ${R_READ}/${NC} 個剛剛讀不到的檔案"
    elif [ "${R_UNREAD:-0}" -gt 0 ] 2>/dev/null; then
      skip "/host 掛進去了，但那幾個檔案容器裡的 uid 讀不到（0600 之類）。隔離的結論不受影響，只是這幾個檔案示範不了，換一個 644 的再試"
    else
      skip "/host 掛進去了，但那幾個路徑在容器裡連 traverse 都不行（Linux 上 ~/.ssh 是 0700 就會這樣）。掛載有生效，換一個 644 的檔案才示範得出來"
    fi
  fi
  TRAP_OUT=$("$DOCKER" run "${BASE[@]}" -e PROBE_HOME=/host -v "$HOME:/host:ro" "$IMAGE" /suspect.sh 2>&1); TRAP_RC=$?
  printf '%s\n' "$TRAP_OUT" | sed 's/^/  | /'
  [ "$TRAP_RC" = 0 ] || bad "suspect.sh 在容器裡的離開碼是 ${TRAP_RC}，這一節比不出東西"
  # 比 basename 不比整條路徑。$HOME 裡有 sed 的特殊字元時正規化會壞掉
  TRAP_READ=$(readable "$TRAP_OUT" | sed 's|.*/||' | sort)
  HOST_NORM=$(printf '%s\n' "$HOST_READ" | sed 's|.*/||' | sort)
  if [ -n "$TRAP_READ" ] && [ "$TRAP_READ" = "$HOST_NORM" ]; then
    ok "掛了家目錄之後，容器讀得到的跟本機一模一樣。容器還在，隔離沒了"
  elif [ -n "$TRAP_READ" ]; then
    ok "掛了家目錄之後容器又讀得到家目錄的檔案了（清單跟本機不完全一致，看上面）"
  else
    bad "掛了家目錄卻還是讀不到，那第 2 節的綠燈是別的原因造成的，要查清楚"
  fi
fi

finish
