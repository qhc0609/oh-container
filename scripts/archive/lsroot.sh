#!/bin/sh
echo "--- /root 内容 ---"
ls -la /root
echo "--- /root/.claude ---"
ls -la /root/.claude 2>/dev/null
echo "--- 找 json 配置 ---"
busybox find /root -maxdepth 3 -name '*.json' 2>/dev/null | head -20
echo "--- .claude.json 内容 ---"
busybox cat /root/.claude.json 2>/dev/null | head -40
