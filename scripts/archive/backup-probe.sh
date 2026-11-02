#!/bin/sh
echo "--- tar / gzip 版本 ---"
tar --help 2>&1 | head -12
echo "--- 支持 gzip 压缩吗（-z）---"
echo "--- /data 剩余空间 ---"
df -h /data
echo "--- 待备份体积 ---"
du -sh /data/ohc /data/ohc/rootfs /data/ohc/workspace /data/ohc/bin 2>/dev/null
echo "--- PATH 入口体积 ---"
du -sh /data/python 2>/dev/null
