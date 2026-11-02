#!/bin/sh
F=/data/ohc/rootfs/claude/root/.claude.json
[ -f "$F" ] || { echo "找不到 $F"; exit 1; }
busybox sed -i 's/"hasTrustDialogAccepted": *false/"hasTrustDialogAccepted": true/g' "$F"
echo "--- 修改结果 ---"
busybox grep -o '"hasTrustDialogAccepted": *[a-z]*' "$F"
busybox grep -o '"hasCompletedOnboarding": *[a-z]*' "$F"
