#!/bin/sh
echo "--- 已认证后的模型列表（deepseek 相关）---"
opencode models 2>&1 | busybox grep -i deepseek
echo
echo "--- 免费模型实测（限时 120 秒）---"
busybox timeout 120 opencode run -m opencode/deepseek-v4.1-flash-free "Reply with exactly this token and nothing else: OC_FREE_OK" 2>&1 | tail -25
echo "--- 退出码: $? ---"
