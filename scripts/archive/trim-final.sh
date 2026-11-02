#!/bin/sh
OC=/usr/local/lib/node_modules/opencode-ai
rm -rf "$OC/node_modules/opencode-linux-arm64.bak"
rm -f /root/trim-oc.sh
echo "--- 平台包剩余 ---"
ls -1 "$OC/node_modules/"
echo "--- rootfs 体积 ---"
du -sh /data/ohc/rootfs/claude
echo "--- 最终可用性确认 ---"
opencode --version 2>&1 | head -1
