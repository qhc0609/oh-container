#!/bin/sh
echo "--- 认证状态 ---"
opencode auth list 2>&1 | head -10
echo
echo "--- 无 key 直接 run（限时 25 秒）---"
busybox timeout 25 opencode run "say hi" 2>&1 | head -20
echo "--- 退出码: $? ---"
