#!/usr/bin/env bash
# 預設全關，要什麼再逐項加回來。
#
# 旗標清單住在 flags.sh，verify.sh 也 source 同一份。所以你跑 verify.sh 拿到的通過，
# 講的就是這一支會用的那組旗標，不是驗證腳本自己另外抄的一份。
#
# 腳本自己另外掛在 /suspect.sh，跟「給它看的目錄」分開。
# 混在一起的話，你把目標換成別的專案，腳本就跟著不見了。
#
# 用法：bash run-isolated.sh [要給它看的目錄，預設是這個 recipe 自己]

set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=flags.sh
. "$HERE/flags.sh"
IMAGE="${IMAGE:-ai-security-day06}"
TARGET=$(cd "${1:-$HERE}" && pwd)

# podman 與 nerdctl 這些旗標都支援，所以認它們。寫死 docker 的話，
# 沒裝 docker 的機器會拿到一個 127 然後什麼訊息都沒有
DOCKER=""
for d in docker podman nerdctl; do
  command -v "$d" >/dev/null 2>&1 && { "$d" info >/dev/null 2>&1 && DOCKER=$d && break; }
done
[ -n "$DOCKER" ] || { printf '找不到能用的 docker／podman／nerdctl（裝了但引擎沒回應也算）\n' >&2; exit 1; }

"$DOCKER" build -q -t "$IMAGE" "$HERE" >/dev/null

exec "$DOCKER" run --rm "${ISOLATION_FLAGS[@]}" \
  -e "PROBE_HOME=$HOME" \
  -v "$HERE/suspect.sh:/suspect.sh:ro" \
  -v "$TARGET:/work:ro" \
  -w /work \
  "$IMAGE" /suspect.sh
