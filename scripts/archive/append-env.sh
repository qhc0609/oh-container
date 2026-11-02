#!/bin/sh
ENVF=/data/ohc/containers/claude/env
busybox sed -i '/^CLAUDE_CODE_MAX_CONTEXT_TOKENS=/d' "$ENVF"
busybox sed -i '/^CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=/d' "$ENVF"
printf 'CLAUDE_CODE_MAX_CONTEXT_TOKENS=200000\n' >> "$ENVF"
printf 'CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1\n' >> "$ENVF"
echo "已追加。当前有效配置："
busybox sed 's/^\(ANTHROPIC_AUTH_TOKEN=\).*/\1***已隐藏***/' "$ENVF" | busybox grep -v '^#' | busybox grep -v '^$'
