#!/bin/sh
# 在容器内执行：装 Node 运行时 + claude code
set -x

echo "===== [1/4] apk update ====="
apk update || exit 1

echo "===== [2/4] 安装基础包 ====="
apk add --no-cache \
    nodejs npm bash curl ca-certificates \
    ripgrep libstdc++ gcompat git || exit 1

echo "===== [3/4] 版本确认 ====="
node -v
npm -v
which node
npm config get prefix

echo "===== [4/4] 安装 claude code ====="
npm install -g @anthropic-ai/claude-code || exit 1

echo "===== 完成 ====="
which claude
claude --version
