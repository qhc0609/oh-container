#!/bin/sh
R=/data/ohc/rootfs/claude
echo "--- usr/local/lib/node_modules 下 ---"
du -m "$R"/usr/local/lib/node_modules/* 2>/dev/null | sort -n | tail -8
echo "--- opencode 包内明细 ---"
du -m "$R"/usr/local/lib/node_modules/opencode-ai/* 2>/dev/null | sort -n | tail -10
echo "--- 大文件（>30MB）---"
busybox find "$R" -type f -size +30M 2>/dev/null | while read -r f; do
    echo "$(du -m "$f" | busybox awk '{print $1}')MB  $f"
done
