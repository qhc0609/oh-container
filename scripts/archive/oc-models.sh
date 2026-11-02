#!/bin/sh
echo "--- opencode 版本 ---"
opencode --version 2>&1 | head -2
echo "--- 模型列表中的 deepseek ---"
opencode models 2>&1 | busybox grep -i deepseek
echo "--- 带 -free 的模型 ---"
opencode models 2>&1 | busybox grep -i 'free'
echo "--- 总模型数 ---"
opencode models 2>&1 | wc -l
