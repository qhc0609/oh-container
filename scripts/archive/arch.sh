#!/bin/sh
echo "== cpuinfo =="
head -12 /proc/cpuinfo
echo "== cpu architecture =="
toybox xxd -l 20 /vendor/python/python/python3 2>/dev/null
echo "== ELF machine (python3) =="
toybox xxd -l 20 /bin/sh 2>/dev/null
echo "== unshare help =="
unshare --help 2>&1 | head -25
echo "== toybox version =="
toybox --version 2>&1
echo "== 内核支持的 ns =="
ls /proc/self/ns
echo "== cgroup =="
ls /dev/cpuctl /dev/memcg 2>/dev/null | head -20
