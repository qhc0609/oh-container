#!/bin/sh
F=/root/.claude.json
echo "--- 已记录的 projects 与信任状态 ---"
busybox grep -o '"/[a-z]*": {' "$F" 2>/dev/null
echo "--- 信任字段 ---"
busybox grep -o '"hasTrustDialogAccepted": *[a-z]*' "$F" 2>/dev/null
echo "--- 当前工作目录 ---"
pwd
