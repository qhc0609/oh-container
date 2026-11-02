#!/bin/sh
echo "--- /root/.claude.json ---"
busybox cat /root/.claude.json
echo
echo "--- 大小 ---"
wc -c /root/.claude.json
