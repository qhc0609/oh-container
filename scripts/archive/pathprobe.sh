#!/bin/sh
echo "--- PATH ---"
echo "$PATH"
echo "--- 各目录是否可写 ---"
for d in $(echo "$PATH" | tr ':' ' '); do
    if [ -d "$d" ]; then
        if touch "$d/.wtest" 2>/dev/null; then
            echo "  可写  $d"; rm -f "$d/.wtest"
        else
            echo "  只读  $d"
        fi
    else
        echo "  不存在 $d"
    fi
done
echo "--- 根挂载参数 ---"
busybox grep ' / ' /proc/mounts
echo "--- /bin 与 /usr/bin ---"
ls -ld /bin /usr/bin /system/bin 2>/dev/null
echo "--- 是否有 profile ---"
ls -l /etc/profile /system/etc/profile 2>/dev/null
echo "--- claude 是否已存在 ---"
command -v claude || echo "无"
