#!/bin/sh
# 把 claude 之前误写到 / 的状态迁到 /root
R=/data/ohc/rootfs/claude

if [ -f "$R/.claude.json" ]; then
    echo "迁移 /.claude.json -> /root/.claude.json"
    mv -f "$R/.claude.json" "$R/root/.claude.json"
fi

if [ -d "$R/.claude" ]; then
    echo "迁移 /.claude -> /root/.claude"
    rm -rf "$R/root/.claude"
    mv "$R/.claude" "$R/root/.claude"
fi

chmod 600 "$R/root/.claude.json" 2>/dev/null

echo "--- 结果 ---"
ls -la "$R/root" | busybox grep -E 'claude'
