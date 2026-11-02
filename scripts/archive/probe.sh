#!/bin/sh
echo "== busybox =="
busybox 2>&1 | head -2
echo "== toybox applets =="
toybox 2>&1 | head -4
echo "== net: wget =="
busybox wget -q -O /dev/null -T 10 http://connectivitycheck.gstatic.com/generate_204 && echo "HTTP_OK" || echo "HTTP_FAIL"
echo "== net: https =="
busybox wget -q -O /dev/null -T 10 https://api.deepseek.com/ 2>&1 && echo "HTTPS_OK" || echo "HTTPS_FAIL"
echo "== dns =="
busybox nslookup api.deepseek.com 2>&1 | head -8
echo "== alpine release =="
cat /data/alpine/etc/alpine-release 2>/dev/null
head -4 /data/alpine/etc/os-release 2>/dev/null
echo "== alpine apk =="
ls -l /data/alpine/sbin/apk 2>/dev/null
echo "== alpine bin sample =="
ls /data/alpine/bin 2>/dev/null | head -12
echo "== alpine lib =="
ls /data/alpine/lib 2>/dev/null | head -8
echo "== id / uname =="
id
uname -m
