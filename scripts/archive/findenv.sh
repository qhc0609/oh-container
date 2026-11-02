#!/bin/sh
F=/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js
ls -l "$F" 2>/dev/null || { echo "找不到 cli.js"; exit 1; }
echo "--- 与 context/window 相关的环境变量 ---"
busybox grep -o 'CLAUDE_CODE_[A-Z_]*' "$F" | sort -u | busybox grep -Ei 'CONTEXT|WINDOW|TOKEN|MODEL'
echo "--- 全部 CLAUDE_CODE_* ---"
busybox grep -o 'CLAUDE_CODE_[A-Z_]*' "$F" | sort -u
