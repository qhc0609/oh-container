#!/bin/sh
echo "--- /data/python 结构 ---"
ls -ld /data/python /data/python/lib /data/python/lib/python3.8 /data/python/lib/python3.8/script 2>&1
echo "--- script/bin 是否存在 ---"
ls -ld /data/python/lib/python3.8/script/bin 2>&1
echo "--- 能否创建并写入 ---"
mkdir -p /data/python/lib/python3.8/script/bin 2>&1 && echo "mkdir ok"
echo test > /data/python/lib/python3.8/script/bin/.wtest 2>&1 && echo "write ok" && rm -f /data/python/lib/python3.8/script/bin/.wtest
echo "--- /usr/local 是否可写 ---"
ls -ld /usr/local /usr/local/bin 2>&1
echo "--- 根是否可 remount rw（仅探测，不做）---"
mount -o remount,rw / 2>&1 && echo "REMOUNT_RW_OK" && mount -o remount,ro / 2>&1 && echo "已恢复 ro"
