#!/bin/sh
R=/data/ohc/rootfs/claude/root
rm -f "$R/trustcheck.sh" "$R/catcfg.sh" "$R/home.sh" "$R/findcfg.sh" "$R/checkcfg.sh"
rm -f /data/local/tmp/pathprobe.sh /data/local/tmp/writable.sh /data/local/tmp/fix-trust.sh \
      /data/local/tmp/migrate-home.sh /data/local/tmp/cleanup.sh /data/local/tmp/append-env.sh \
      /data/local/tmp/probe.sh /data/local/tmp/net.sh /data/local/tmp/route.sh /data/local/tmp/tcp.py \
      /data/local/tmp/arch.sh /data/local/tmp/nstest.sh /data/local/tmp/ns2.sh /data/local/tmp/pty*.py
echo "--- 容器 /root ---"
ls -a "$R"
echo "--- /data/ohc/bin ---"
ls -l /data/ohc/bin
echo "--- PATH 中的 claude ---"
ls -l /data/python/lib/python3.8/script/bin/claude
echo "--- workspace ---"
ls -ld /data/ohc/workspace
