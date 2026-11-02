#!/bin/sh
F=/root/.local/share/opencode/auth.json
echo "--- auth.json 存在性 ---"
ls -l "$F" 2>&1
echo "--- 结构与 key 前缀 ---"
busybox cat "$F" 2>/dev/null | busybox sed 's/\("key":"\(......\).*"\)/\1***"/'
echo
echo "--- 与预期值比对 ---"
EXPECT='oc_sk_请填入你自己的key'
ACTUAL=$(busybox sed -n 's/.*"key":"\([^"]*\)".*/\1/p' "$F")
if [ "$ACTUAL" = "$EXPECT" ]; then
    echo "MATCH  设备上的 key 与你给的一致"
else
    echo "MISMATCH"
    echo "  实际: $ACTUAL"
fi
echo "--- 认证列表 ---"
opencode auth list 2>&1 | busybox grep -E 'OpenCode|credentials'
