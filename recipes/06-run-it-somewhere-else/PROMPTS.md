# 兩種問法，同一個模型

文章裡那組對照的原始紀錄。放在這裡是因為「我問了兩次，答案不一樣」這種話
沒有紀錄就只是敘述，你沒辦法判斷差別出在模型還是出在我怎麼問的。

**環境**：macOS 26.5.2、Antigravity CLI（`agy`）1.1.10、`--model "Gemini 3.5 Flash (Low)"`、2026-08-06。

模型會改版，你今天跑不一定拿到一樣的字。要看的不是字，是**兩次的差別跟著問題走**。

---

## 第一次：照大家平常的問法

```
幫我在 Docker 裡跑我專案裡的 suspect.sh，給我 Dockerfile 和 docker run 指令就好。不要使用工具、不要讀取任何檔案。
```

回答（節錄，只留程式碼與那句補充）：

```dockerfile
FROM alpine:latest
RUN apk update && apk add --no-cache bash
WORKDIR /app
COPY . .
RUN chmod +x suspect.sh
ENTRYPOINT ["/bin/bash", "./suspect.sh"]
```

```bash
docker build -t suspect-app .
docker run --rm suspect-app
```

> 如果您的 `suspect.sh` 需要存取環境變數或掛載外部目錄，可以在 `docker run` 時加上 `-e KEY=VALUE` 或 `-v` 參數。

沒有 `USER`，所以裡面是 root。沒有任何網路限制。`COPY . .` 把整個專案複製進映像檔。
最後那句就是文章第 4 節示範的那一行。

---

## 第二次：把顧慮寫進問題

```
我有一支來路不明的 shell 腳本 suspect.sh，想在容器裡跑它，不要讓它碰到我本機的東西。請給我一個 Dockerfile 和一行 docker run 指令。只回程式碼區塊加簡短說明，不要使用工具、不要讀取任何檔案。
```

回答（節錄）：

```dockerfile
FROM alpine:latest
RUN apk add --no-cache bash
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY suspect.sh .
RUN chmod +x suspect.sh
USER appuser
CMD ["./suspect.sh"]
```

```bash
docker build -t suspect-runner .
docker run --rm --network none suspect-runner
```

`COPY . .` 變成只複製那一支，多了非 root 使用者，`docker run` 主動加上 `--network none`。

---

## 差在哪

同一個模型、同一支腳本、同一天。差的只有我有沒有把要求寫進問題。

第二份也不能照收：沒有 `--read-only`、沒有 `--cap-drop`、沒有資源上限，
而且 `docker run` 沒有掛任何目錄，所以它其實沒有在跑你的專案。
這個 recipe 的 `flags.sh` 是從第二份改出來的，不是它給的。

**注意 `docker run` 那一行要跟 Dockerfile 對得起來。** 第二份把腳本 `COPY` 到
`/app/suspect.sh`，所以指令是 `docker run … suspect-runner`（走 `CMD`）或
`… suspect-runner /app/suspect.sh`。本 recipe 走的是另一條路：腳本用 `-v` 掛在
`/suspect.sh`，跟「要給它看的目錄」分開，這樣換目標的時候腳本不會跟著不見。
兩種都可以，混著用會得到 `can't open '/suspect.sh': No such file or directory`。
