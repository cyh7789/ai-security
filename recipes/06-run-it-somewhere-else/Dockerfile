# 這個映像檔只做一件事：跑一段你還沒讀完的腳本。
# 所以裡面什麼都不放，連能寫的地方都不給，要什麼都在 docker run 那一行逐項加。
FROM alpine:3.22

# curl 是為了讓「連不連得出去」這條檢查在容器內外用同一支腳本問同一句話。
RUN apk add --no-cache curl

# 不用 root 跑。--cap-drop ALL 之後容器裡的 root 已經沒剩多少權力，
# 但「預設是 root」本身就是一個沒人做過的決定，改掉它是免費的。
#
# 別把這一行當成隔離的主力：在 macOS 上實測，掛進來的目錄讀得到什麼
# 是照宿主機那個使用者算的，容器裡是 uid 0 還是 10001 結果一樣。
# 決定它看得到什麼的是你掛了什麼，不是它在裡面是誰。
RUN adduser -D -u 10001 runner
USER runner

WORKDIR /work
ENTRYPOINT ["sh"]
