#!/bin/sh
echo "===== opencode --help ====="
opencode --help 2>&1 | head -40
echo
echo "===== opencode run --help ====="
opencode run --help 2>&1 | head -30
echo
echo "===== opencode auth --help ====="
opencode auth --help 2>&1 | head -25
echo
echo "===== opencode auth login --help ====="
opencode auth login --help 2>&1 | head -25
