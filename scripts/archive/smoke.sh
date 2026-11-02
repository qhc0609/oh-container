#!/bin/sh
echo "--- 容器内部自检 ---"
echo "alpine    : $(cat /etc/alpine-release 2>/dev/null)"
echo "hostname  : $(hostname)"
echo "arch      : $(uname -m)"
echo "kernel    : $(uname -r)"
echo "rootfs /  : $(df / 2>/dev/null | tail -1)"
echo "proc 可见 : $(ls /proc | wc -l) 项"
echo "dev/null  : $(ls -l /dev/null 2>&1)"
echo "tty       : $(tty 2>&1)"
echo "--- 宿主目录是否可见（应该看不到 /data/ohc）---"
ls /data/ohc 2>&1 | head -2
echo "--- DNS ---"
cat /etc/resolv.conf
echo "--- 出网测试 ---"
busybox nslookup api.deepseek.com 2>&1 | head -6
