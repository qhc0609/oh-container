#!/bin/sh
echo "--- /root 全部（含隐藏）---"
ls -la /root
echo "--- 最近 20 分钟内修改的文件 ---"
busybox find /root /tmp /etc /usr/local -newermt '-20 minutes' -type f 2>/dev/null | busybox grep -v 'node_modules' | head -30
echo "--- 可能的配置目录 ---"
ls -la /root/.config 2>/dev/null
ls -la /root/.claude 2>/dev/null
