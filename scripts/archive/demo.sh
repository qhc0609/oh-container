#!/bin/sh
echo "===== claude -p 干净输出测试 ====="
printf '用一句话说明你在什么运行环境里，并说出你的模型名。\n' | claude -p 2>/dev/null
echo
echo "===== 退出码: $? ====="
