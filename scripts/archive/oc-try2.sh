#!/bin/sh
echo "=== A. 重定向 stdin ==="
busybox timeout 90 opencode run -m opencode/deepseek-v4.1-flash-free "Reply with exactly: OC_FREE_OK" < /dev/null 2>&1 | tail -20
echo "--- A 结束 ---"
echo
echo "=== B. --pure + 重定向 stdin ==="
busybox timeout 90 opencode run --pure -m opencode/deepseek-v4.1-flash-free "Reply with exactly: OC_FREE_OK" < /dev/null 2>&1 | tail -20
echo "--- B 结束 ---"
