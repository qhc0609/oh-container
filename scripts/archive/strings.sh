#!/bin/sh
D=/usr/local/lib/node_modules/@anthropic-ai/claude-code
F=$D/bin/claude.exe
echo "--- 文件类型 ---"
busybox head -c 20 "$F" | toybox xxd | head -2
ls -lh "$F"
echo "--- CLAUDE_CODE_* 环境变量 ---"
busybox grep -a -o 'CLAUDE_CODE_[A-Z_]*' "$F" | sort -u
echo "--- 含 CONTEXT/WINDOW 的变量名 ---"
busybox grep -a -o '[A-Z_]*CONTEXT[A-Z_]*' "$F" | sort -u | head -30
