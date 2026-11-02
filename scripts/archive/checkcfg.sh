#!/bin/sh
echo "--- .claude.json ---"
busybox cat /root/.claude.json 2>/dev/null | head -40
echo "--- 关键字段 ---"
busybox grep -o '"hasCompletedOnboarding":[a-z]*' /root/.claude.json 2>/dev/null
busybox grep -o '"hasTrustDialogAccepted":[a-z]*' /root/.claude.json 2>/dev/null
busybox grep -o '"theme":"[^"]*"' /root/.claude.json 2>/dev/null
