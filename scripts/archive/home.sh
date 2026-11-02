#!/bin/sh
echo "HOME = [$HOME]"
echo "PWD  = [$PWD]"
echo "--- / 下是否有 .claude.json ---"
ls -la /.claude.json 2>/dev/null || echo "无"
echo "--- 当前目录下的 .claude* ---"
ls -la .claude* 2>/dev/null || echo "无"
