#!/bin/sh
# =============================================================================
#  探测这台设备到底支持哪些 namespace
#
#  用法（在设备上跑，不要放进容器里）：
#      hdc shell sh /data/local/tmp/check-namespace.sh
#
#  结论会直接决定你的容器能做成什么样：
#    - 有 pid  -> 可以做 PID 隔离，能跑 init
#    - 没 pid  -> 只能做 mount + uts + ipc + chroot，进程列表和宿主共享
# =============================================================================

echo "==================== 基本信息 ===================="
echo "uname      : $(uname -a)"
echo "uid        : $(id -u)"
echo "SELinux    : $(cat /sys/fs/selinux/enforce 2>/dev/null || echo 'n/a')"
echo "CapEff     : $(grep CapEff /proc/self/status 2>/dev/null)"
echo "Seccomp    : $(grep Seccomp: /proc/self/status 2>/dev/null)"
echo

echo "================= namespace 文件 ================="
for ns in mnt uts ipc net pid user cgroup time; do
    if [ -e "/proc/self/ns/$ns" ]; then
        printf '  %-8s 可用   %s\n' "$ns" "$(readlink /proc/self/ns/$ns 2>/dev/null)"
    else
        printf '  %-8s 不可用（内核未开启）\n' "$ns"
    fi
done
echo

echo "================= unshare 实测 ================="
# 注意：只做"能不能创建"的测试，不 fork，不执行任何东西
for opt in "-m" "-u" "-i" "-U" "-p" "-n" "-C"; do
    if unshare $opt true 2>/dev/null; then
        printf '  unshare %-3s  OK\n' "$opt"
    else
        printf '  unshare %-3s  失败（EINVAL / EPERM）\n' "$opt"
    fi
done
echo

echo "================== 关键工具 =================="
for c in chroot pivot_root unshare nsenter busybox tar gzip xz curl; do
    p="$(command -v $c 2>/dev/null)"
    printf '  %-12s %s\n' "$c" "${p:-缺失}"
done
echo

echo "================== 挂载点 ==================="
mount 2>/dev/null | grep -E ' /data | /storage | / ' | head -10
echo

echo "================== 结论 ==================="
if [ -e /proc/self/ns/pid ]; then
    echo "  有 PID namespace：可以按 Docker 的方式做隔离"
else
    echo "  无 PID namespace：容器只能是 mount+uts+ipc+chroot 的最小实现"
    echo "  unshare 千万别加 -f，加了会把交互 TTY 切断"
fi
if [ -e /proc/self/ns/user ]; then
    echo "  有 user namespace：可以做 rootless"
else
    echo "  无 user namespace：容器内 root == 宿主 root，别跑不可信代码"
fi
