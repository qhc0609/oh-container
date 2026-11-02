#!/usr/bin/env bash
# 组装「VS Code 离线套件」并打成一个 zip，方便拷到不能上网的电脑上。
#
# 用法：  bash scripts/build-kit.sh
#
# 产物：  dist/ohc-vscode-kit.zip
#
# 说明：
#   continue.vsix 是从本机已装的 Continue 扩展重新打包出来的（见 build-vsix.py），
#   因为目标机器连不上扩展市场。hdc.exe / libusb_shared.dll 从 HarmonyOS SDK 拷，
#   这样目标机器不用装 SDK 也能建 USB 端口转发。
#   这三个大文件不进 git，所以别人拿到仓库后要先跑一遍本脚本。

set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$(pwd)"
KIT="$REPO/kit"
PAYLOAD="$KIT/payload"
DIST="$REPO/dist"

# ---------------------------------------------------------------- 找 hdc
HDC_SRC="${HDC_SRC:-C:/Tools/HarmonyOS/toolchains}"
if [ ! -f "$HDC_SRC/hdc.exe" ]; then
    echo "[失败] 找不到 $HDC_SRC/hdc.exe，用环境变量 HDC_SRC 指定 SDK 的 toolchains 目录"
    exit 1
fi

# ---------------------------------------------------------------- 找已装的 Continue
EXT=""
for d in "$HOME/.vscode/extensions"/continue.continue-*; do
    [ -d "$d" ] && EXT="$d"
done
if [ -z "$EXT" ]; then
    echo "[失败] 本机没装 Continue 扩展，先装一次再打包："
    echo "       code --install-extension Continue.continue"
    exit 1
fi
echo "[1/5] 找到扩展: $(basename "$EXT")"

# ---------------------------------------------------------------- 生成 vsix
mkdir -p "$PAYLOAD"
python scripts/build-vsix.py "$EXT" "$PAYLOAD/continue.vsix"

# ---------------------------------------------------------------- 拷二进制
echo "[2/5] 拷 hdc"
cp "$HDC_SRC/hdc.exe" "$PAYLOAD/hdc.exe"
[ -f "$HDC_SRC/libusb_shared.dll" ] && cp "$HDC_SRC/libusb_shared.dll" "$PAYLOAD/libusb_shared.dll"

# ---------------------------------------------------------------- 同步运行时脚本
echo "[3/5] 同步网关与守护进程"
cp "$REPO/etc/ohc-gw.mjs" "$PAYLOAD/ohc-gw.mjs"
cp "$REPO/bin/ohc-gateway-daemon.ps1" "$PAYLOAD/ohc-gateway-daemon.ps1"

# ---------------------------------------------------------------- 确保脚本带 BOM
echo "[4/5] 检查 BOM"
python - "$KIT/install.ps1" "$PAYLOAD/ohc-gateway-daemon.ps1" <<'PY'
import io, sys
for p in sys.argv[1:]:
    raw = io.open(p, 'rb').read()
    if not raw.startswith(b'\xef\xbb\xbf'):
        io.open(p, 'wb').write(b'\xef\xbb\xbf' + raw)
        print("    BOM 已补:", p)
PY

# ---------------------------------------------------------------- 打包
echo "[5/5] 打 zip"
rm -rf "$DIST"
mkdir -p "$DIST/ohc-vscode-kit"
cp -r "$KIT"/. "$DIST/ohc-vscode-kit/"
rm -f "$DIST/ohc-vscode-kit"/*.bak

python - "$DIST" <<'PY'
import os, sys, zipfile
dist = sys.argv[1]
src = os.path.join(dist, 'ohc-vscode-kit')
out = os.path.join(dist, 'ohc-vscode-kit.zip')
n = 0
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for base, dirs, files in os.walk(src):
        for f in files:
            full = os.path.join(base, f)
            arc = os.path.relpath(full, dist).replace('\\', '/')
            z.write(full, arc)
            n += 1
print(f"    文件 {n} 个，{os.path.getsize(out)/1024/1024:.1f} MB")
print(f"    -> {out}")
PY
