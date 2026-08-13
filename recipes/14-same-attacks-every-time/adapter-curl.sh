#!/usr/bin/env bash
# 另一個 MODEL_CMD 的實作：直接打 OpenAI 相容的 /chat/completions。
# 大部分自架端點（Ollama、vLLM、LM Studio）與多數雲端供應商都吃這個形狀。
#
#   API_BASE=http://localhost:11434/v1 API_MODEL=llama3.1 \
#   MODEL_CMD='bash adapter-curl.sh' bash run-suite.sh
#
# 約定就那一條：從 stdin 讀整段 prompt，把回覆印到 stdout。
# 你家的 API 長得不一樣的話，要改的只有最後那個 jq 取值路徑。
set -u

: "${API_BASE:?請設 API_BASE，例如 http://localhost:11434/v1}"
: "${API_MODEL:?請設 API_MODEL}"

prompt=$(cat)

# 用 jq 組 JSON，不要自己用 printf 拼字串：這些 prompt 裡有引號、換行、
# HTML 標籤跟隱形碼點，手拼一定會在某一條上壞掉，而壞掉的那一發會被記成「擋住了」。
body=$(jq -n --arg m "$API_MODEL" --arg p "$prompt" \
  '{model: $m, messages: [{role: "user", content: $p}]}')

resp=$(curl -sS --fail-with-body --max-time 120 \
  -H 'Content-Type: application/json' \
  ${API_KEY:+-H "Authorization: Bearer ${API_KEY}"} \
  -d "$body" "${API_BASE}/chat/completions") || {
    # 錯誤訊息不要印到 stdout。它裡面沒有標記，會被判成「這一條擋住了」。
    printf '呼叫失敗：%s\n' "$resp" >&2; exit 1; }

# 取不到內容就非零退出，不要印空字串：run-suite.sh 對空回覆會中止整輪，
# 那是對的，但它得先看到非零或空值，而不是一段被誤當成回覆的 JSON。
out=$(printf '%s' "$resp" | jq -r '.choices[0].message.content // empty')
[ -n "$out" ] || { printf '回應裡沒有 content：%s\n' "$resp" >&2; exit 1; }
printf '%s\n' "$out"
