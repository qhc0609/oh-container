#!/bin/sh
R=/data/ohc/rootfs/claude
echo "--- rootfs 顶层体积（MB，降序）---"
du -m "$R"/* 2>/dev/null | sort -n | tail -12
echo "--- claude.exe 的硬链接伙伴 ---"
busybox find "$R" -inum 5577 2>/dev/null
echo "--- npm 缓存 ---"
du -sh "$R/root/.npm" 2>/dev/null || echo "无 .npm"
du -sh "$R/usr/local/lib/node_modules/.cache" 2>/dev/null || echo "无 .cache"
echo "--- apk 缓存 ---"
du -sh "$R/var/cache/apk" 2>/dev/null || echo "无"
echo "--- claude 会话记录 ---"
du -sh "$R/root/.claude" 2>/dev/null
