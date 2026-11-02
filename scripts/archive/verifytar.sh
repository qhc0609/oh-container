#!/bin/sh
F=/data/local/tmp/ohc-backup.tar.gz
echo "--- 头部 4 字节（gzip 应为 1f 8b）---"
busybox head -c 4 "$F" | toybox xxd
echo "--- 大小 ---"
ls -l "$F"
echo "--- 完整性校验 ---"
if tar -tzf "$F" > /data/local/tmp/tarlist.txt 2>/data/local/tmp/tarerr.txt; then
    echo "OK 条目数: $(wc -l < /data/local/tmp/tarlist.txt)"
    busybox head -3 /data/local/tmp/tarlist.txt
else
    echo "失败:"; busybox head -5 /data/local/tmp/tarerr.txt
fi
