#!/bin/sh
# =============================================================================
#  裸测 DeepSeek 的 Anthropic 兼容端点
#
#  用途：claude 报 "Not logged in" 或者转圈不动时，先用这个排除"到底是不是
#        key / 网络 / 模型名的问题"。
#
#  用法（在容器里跑，或者任何有 curl 的地方）：
#      sh test-deepseek.sh sk-xxxxxxxx
#
#  注意：这不是 claude 的调用路径，只是打同一个 HTTP 接口做对照。
#        返回 200 就说明 key + 网络 + 模型名都没问题，问题在 claude 侧配置。
# =============================================================================

KEY="$1"
[ -n "$KEY" ] || { echo "用法: sh $0 sk-xxxxxxxx"; exit 1; }

echo "--- 1. DNS ---"
nslookup api.deepseek.com 2>/dev/null | tail -4 || echo "(没有 nslookup，跳过)"

echo
echo "--- 2. TCP/TLS 连通性 ---"
curl -s -o /dev/null -w "connect=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s http=%{http_code}\n" \
    https://api.deepseek.com/anthropic/v1/messages \
    -H "content-type: application/json" \
    -H "x-api-key: $KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"deepseek-flash","max_tokens":16,"messages":[{"role":"user","content":"hi"}]}'

echo
echo "--- 3. 实际响应体 ---"
curl -s https://api.deepseek.com/anthropic/v1/messages \
    -H "content-type: application/json" \
    -H "x-api-key: $KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"deepseek-flash","max_tokens":64,"messages":[{"role":"user","content":"只回答两个字：通了"}]}'
echo

echo
echo "--- 判断 ---"
echo "返回 200 + 有 content  -> key/网络/模型名 全部正常，问题在 claude 配置（看 ANTHROPIC_BASE_URL / set -a）"
echo "返回 401               -> key 错了或者没带对 header"
echo "返回 404               -> base url 少了 /anthropic，或者模型名拼错"
echo "返回 429               -> 限流，等一下再试"
echo "connect 卡住           -> 默认路由缺失，跑 ohc net"
