#!/bin/sh
OC=/usr/local/lib/node_modules/opencode-ai

echo "--- 目录内容 ---"
ls -li "$OC/bin/" 2>/dev/null
echo "--- 平台包 ---"
ls -1 "$OC/node_modules/" 2>/dev/null
echo "--- 各自体积 ---"
du -sh "$OC/node_modules/opencode-linux-arm64" "$OC/node_modules/opencode-linux-arm64-musl" 2>/dev/null

echo "--- 把 glibc 版挪走 ---"
mv "$OC/node_modules/opencode-linux-arm64" "$OC/node_modules/opencode-linux-arm64.bak" 2>&1 && echo "已挪走"

echo "--- 版本 ---"
opencode --version 2>&1 | head -2
echo "--- 免费模型实测 ---"
busybox timeout 90 opencode run "Reply with exactly: TRIM_OK" < /dev/null 2>&1 | tail -5
