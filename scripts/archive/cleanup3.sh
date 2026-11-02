#!/bin/sh
R=/data/ohc/rootfs/claude/root
rm -f "$R"/oc-models.sh "$R"/oc-help.sh "$R"/oc-noauth.sh "$R"/oc-test.sh \
      "$R"/oc-net.sh "$R"/oc-debug.sh "$R"/oc-try2.sh
rm -f /data/local/tmp/ptyoc.py /data/local/tmp/oc-*.sh
echo "--- 容器 /root ---"
ls -a "$R"
echo "--- opencode 相关状态 ---"
echo "config : $(ls /data/ohc/rootfs/claude/root/.config/opencode/ 2>/dev/null)"
echo "auth   : $(ls -l /data/ohc/rootfs/claude/root/.local/share/opencode/auth.json 2>/dev/null | busybox awk '{print $1, $5"B"}')"
echo "binary : $(ls -l /data/ohc/rootfs/claude/usr/local/bin/opencode 2>/dev/null | busybox awk '{print $NF}')"
