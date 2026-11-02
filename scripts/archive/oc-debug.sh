#!/bin/sh
echo "=== opencode run 带 DEBUG 日志（限时 90 秒）==="
busybox timeout 90 opencode run \
  -m opencode/deepseek-v4.1-flash-free \
  --print-logs --log-level DEBUG \
  "Reply with exactly: OC_FREE_OK" 2>&1 | tail -45
echo "=== 退出码: $? ==="
