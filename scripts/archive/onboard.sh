#!/bin/sh
F=/usr/local/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe
echo "--- onboarding 相关标识 ---"
busybox grep -a -o '[A-Za-z]*[Oo]nboarding[A-Za-z]*' "$F" | sort -u | head -20
echo "--- 配置文件名字符串 ---"
busybox grep -a -o '\.claude\.json' "$F" | sort -u | head -5
busybox grep -a -o 'hasTrustDialogAccepted' "$F" | sort -u | head -3
busybox grep -a -o 'hasCompletedOnboarding' "$F" | sort -u | head -3
echo "--- theme 键 ---"
busybox grep -a -o 'theme[A-Za-z]*' "$F" | sort -u | head -10
