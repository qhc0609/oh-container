#!/bin/sh
echo "== 添加默认路由 =="
toybox route add default gw 192.168.76.15 dev wlan0 2>&1
echo "== 路由表 =="
toybox netstat -rn 2>&1 | head -8
echo "== ping 网关 =="
toybox ping -c 1 -W 3 192.168.76.15 2>&1 | tail -3
echo "== ping 公网 IP =="
toybox ping -c 1 -W 3 114.114.114.114 2>&1 | tail -3
echo "== dns =="
busybox nslookup api.deepseek.com 2>&1 | head -8
