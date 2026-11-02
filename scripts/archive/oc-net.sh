#!/bin/sh
KEY=$(busybox sed -n 's/.*"key":"\([^"]*\)".*/\1/p' /root/.local/share/opencode/auth.json)

echo "--- 1. 直连 opencode 推理网关 ---"
curl -s -o /tmp/m.json -w "HTTP=%{http_code}\n" --max-time 30 \
  https://opencode.ai/inference/v1/models \
  -H "Authorization: Bearer $KEY"
busybox head -c 200 /tmp/m.json; echo

echo "--- 2. 直接打一次 chat completions（免费模型）---"
curl -s -o /tmp/c.json -w "HTTP=%{http_code}\n" --max-time 90 \
  https://opencode.ai/inference/openai/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "content-type: application/json" \
  -d '{"model":"deepseek-v4.1-flash-free","messages":[{"role":"user","content":"Reply with exactly: OC_CURL_OK"}],"max_tokens":32}'
busybox head -c 400 /tmp/c.json; echo
