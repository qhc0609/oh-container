#!/bin/sh
R=/data/ohc/rootfs/claude/root
echo "--- 各缓存体积 ---"
du -sh "$R/.npm" "$R/.cache" "$R/.config/opencode" "$R/.local" 2>/dev/null
echo "--- rootfs 总体积 ---"
du -sh /data/ohc/rootfs/claude
echo "--- 清理 npm 缓存 ---"
rm -rf "$R/.npm" "$R/.cache" 2>/dev/null
echo "清理后:"
du -sh /data/ohc/rootfs/claude
