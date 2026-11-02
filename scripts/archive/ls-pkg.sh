#!/bin/sh
D=/usr/local/lib/node_modules/@anthropic-ai/claude-code
echo "--- 目录 ---"
ls -l "$D" 2>&1 | head -20
echo "--- 大文件 ---"
busybox find "$D" -type f -size +1M 2>/dev/null | head -10
echo "--- bin 链接 ---"
ls -l /usr/local/bin/claude
