#!/bin/sh
echo "== host pid: $$ =="
echo "== test1: unshare -p -f =="
unshare -p -f sh -c 'echo "  inside pid=$$"; echo "  tty: $(tty 2>&1)"'
echo "  after rc=$?"
echo "== test2: mnt+uts+ipc+pid, 改 hostname =="
unshare -m -u -i -p -f sh -c 'hostname ohc-test 2>&1; echo "  hostname=$(hostname)"; echo "  pid=$$"'
echo "  back: hostname=$(hostname) rc=$?"
echo "== test3: mnt ns 内 mount tmpfs =="
unshare -m -f sh -c 'mkdir -p /data/local/tmp/mnttest; mount -t tmpfs none /data/local/tmp/mnttest && echo "  mount ok" && echo hi > /data/local/tmp/mnttest/x && cat /data/local/tmp/mnttest/x; umount /data/local/tmp/mnttest'
echo "  back: $(ls /data/local/tmp/mnttest 2>&1)"
echo "== test4: chroot 到 alpine =="
chroot /data/alpine /bin/sh -c 'echo "  chroot ok: $(cat /etc/alpine-release)"' 2>&1
echo "== test5: pivot_root 是否存在 =="
command -v pivot_root; pivot_root 2>&1 | head -3
