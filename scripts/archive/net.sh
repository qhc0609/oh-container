#!/bin/sh
echo "== interfaces =="
ifconfig -a 2>&1 | head -40
echo "== routes =="
toybox route -n 2>&1 | head -20
echo "== ip link =="
ip link 2>&1 | head -20
echo "== wifi state =="
param get ohos.wifi.p2p.mac 2>/dev/null
param get const.product.wifi.mac 2>/dev/null
echo "== ping test =="
toybox ping -c 1 -W 3 114.114.114.114 2>&1 | head -5
echo "== try 223.5.5.5 =="
toybox ping -c 1 -W 3 223.5.5.5 2>&1 | head -5
