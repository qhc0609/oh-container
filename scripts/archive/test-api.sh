#!/bin/sh
echo "--- 直接探 DeepSeek 的 /anthropic/v1/messages ---"
curl -s -o /tmp/resp.txt -w "HTTP_CODE=%{http_code}\n" \
  -X POST "$ANTHROPIC_BASE_URL/v1/messages" \
  -H "x-api-key: $ANTHROPIC_AUTH_TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "{\"model\":\"$ANTHROPIC_MODEL\",\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
echo "--- 响应体 ---"
head -c 600 /tmp/resp.txt
echo
