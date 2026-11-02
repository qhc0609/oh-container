#!/bin/sh
R=/data/ohc/rootfs/claude
echo "--- socket 文件 ---"
busybox find "$R" -type s 2>/dev/null | head -30
echo "--- 数量 ---"
busybox find "$R" -type s 2>/dev/null | wc -l
echo "--- fifo 文件 ---"
busybox find "$R" -type p 2>/dev/null | head -10
echo "--- 残留 tar ---"
ls -lh /data/local/tmp/ohc-backup.tar.gz 2>/dev/null || echo "无"
