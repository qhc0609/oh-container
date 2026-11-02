#!/bin/sh
echo "== -u (uts) =="
unshare -u sh -c 'hostname ohc-x 2>&1; echo "  inside hostname=$(hostname)"' 2>&1
echo "  outside hostname=$(hostname)"
echo "== -i (ipc) =="
unshare -i true 2>&1 && echo "  ipc ok" || echo "  ipc fail"
echo "== -n (net) =="
unshare -n true 2>&1 && echo "  net ok" || echo "  net fail"
echo "== -U (user) =="
unshare -U true 2>&1 && echo "  user ok" || echo "  user fail"
echo "== -m -u -i 组合（不带 -p/-f） =="
unshare -m -u -i sh -c 'hostname ohc-y 2>&1; echo "  combo hostname=$(hostname) tty=$(tty 2>&1)"' 2>&1
echo "  outside hostname=$(hostname)"
