#!/bin/sh
echo "--- /data/ohc 各项 ---"
du -sh /data/ohc/* 2>/dev/null
echo "--- rootfs 下各项 ---"
du -sh /data/ohc/rootfs/claude/* 2>/dev/null | sort -h | tail -10
echo "--- claude 包 ---"
du -sh /data/ohc/rootfs/claude/usr/local/lib/node_modules 2>/dev/null
echo "--- 硬链接情况 ---"
ls -li /data/ohc/rootfs/claude/usr/local/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe
