#!/bin/sh
# 在设备上打包整套环境：/data/ohc + /data/python（PATH 入口）
# 注意：toybox tar 不支持 socket 文件，必须先清理

OUT=/data/local/tmp/ohc-backup.tar.gz
R=/data/ohc/rootfs/claude

echo "--- 清理残缺包 ---"
rm -f "$OUT"

echo "--- 清理 apk 缓存 ---"
rm -rf "$R/var/cache/apk"/* 2>/dev/null

echo "--- 清理残留 socket（claude 的 IPC 文件，运行时自动重建）---"
busybox find "$R" -type s 2>/dev/null | while read -r f; do
    echo "  rm $f"
    rm -f "$f"
done

echo "--- 开始打包 ---"
S=$(date +%s)
cd /data
tar -czf "$OUT" ohc python
E=$(date +%s)
echo "打包耗时: $((E - S)) 秒"

ls -lh "$OUT"

echo "--- 完整性校验（能完整列出即通过）---"
if tar -tzf "$OUT" > /tmp/tarlist.txt 2>/tmp/tarerr.txt; then
    echo "校验通过，条目数: $(wc -l < /tmp/tarlist.txt)"
    echo "--- 顶层 ---"
    busybox head -3 /tmp/tarlist.txt
else
    echo "校验失败:"; cat /tmp/tarerr.txt | busybox head -10
fi
