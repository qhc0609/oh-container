# 从零构建 rootfs

`deploy.ps1` 假设设备上已经有 `/data/ohc/rootfs/claude`。这份文档讲怎么从零建一个。

如果你只是想让环境跑起来，**别走这条路**——用 `backup/restore.ps1` 恢复 834MB 整包，56 秒搞定，不联网。

这份文档是给这两种人看的：

- 想换一个别的发行版（Debian、Ubuntu base）
- 想搞清楚 rootfs 里到底装了什么

---

## 0. 前置条件

设备上必须满足：

```sh
id -u                        # 必须是 0
ls /proc/self/ns/            # 至少要有 mnt、uts、ipc
mount | grep ' /data '       # 不能有 noexec
command -v chroot            # 存在
```

四条有一条不满足就别往下走。`scripts/check-namespace.sh` 一次跑完。

---

## 1. 拿 Alpine minirootfs

```sh
mkdir -p /data/ohc/rootfs/claude /data/local/tmp/dl
cd /data/local/tmp/dl

curl -LO https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-minirootfs-3.21.3-aarch64.tar.gz

tar -xzf alpine-minirootfs-3.21.3-aarch64.tar.gz -C /data/ohc/rootfs/claude
rm -f alpine-minirootfs-3.21.3-aarch64.tar.gz
```

验证：

```sh
chroot /data/ohc/rootfs/claude /bin/sh -c 'cat /etc/alpine-release'
# 3.21.3
```

能打出 `3.21.3` 就成。

> 换成 Debian 的话，用 `debian-*-arm64-rootfs.tar.xz`，步骤一样，只是后面的 `apk` 换成 `apt`。

---

## 2. 装运行时需要的挂载点

`chroot` 之前这些目录必须存在，否则运行时挂载会失败：

```sh
cd /data/ohc/rootfs/claude
mkdir -p proc sys dev/pts dev/shm tmp run work root
printf 'nameserver 223.5.5.5\nnameserver 114.114.114.114\n' > etc/resolv.conf
printf '127.0.0.1\tlocalhost\n' > etc/hosts
```

---

## 3. 用 ohc 进去装东西

先部署运行时：

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -SkipVerify
```

（`deploy.ps1` 会检查 rootfs 里的 `/bin/sh` 是否可执行，这时已经满足了。）

然后进容器：

```sh
/data/ohc/bin/ohc shell claude
```

容器里执行：

```sh
apk update

apk add --no-cache \
    nodejs npm bash curl ca-certificates \
    ripgrep libstdc++ gcompat git

node -v      # v22.23.4
npm -v       # 10.9.1

npm install -g @anthropic-ai/claude-code
npm install -g opencode-ai

claude --version     # 2.1.316 (Claude Code)
opencode --version   # 1.19.5
```

---

## 4. 瘦身

不做这一步，rootfs 会到 1.0G。

**删 glibc 版 opencode**（Alpine 只用 musl 版）：

```sh
rm -rf /usr/local/lib/node_modules/opencode-ai/node_modules/opencode-linux-arm64
opencode --version      # 必须还有输出
```

**清 npm 缓存**：

```sh
npm cache clean --force
rm -rf /root/.npm
```

**清 apk 缓存**：

```sh
rm -rf /var/cache/apk/*
```

三刀下去：1.0G → 839M。

---

## 5. 装配置

退出容器，在宿主上写配置：

```sh
# DeepSeek key 与模型
/data/ohc/bin/ohc-setkey sk-你的key

# OpenCode 登录
/data/ohc/bin/oc-setkey oc_sk_你的key
```

或者用 `deploy.ps1` 一次性推：

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Key sk-xxx -OcKey oc_sk_xxx
```

---

## 6. 装 PATH 入口

```sh
P=/data/python/lib/python3.8/script/bin
mkdir -p "$P"

cat > "$P/claude" <<'EOF'
#!/bin/sh
export OHC_QUIET=1
exec /data/ohc/bin/ohc-claude "$@"
EOF

cat > "$P/opencode" <<'EOF'
#!/bin/sh
export OHC_QUIET=1
if [ "$1" = "run" ]; then
    exec /data/ohc/bin/ohc run claude -- opencode "$@" < /dev/null
fi
exec /data/ohc/bin/ohc run claude -- opencode "$@"
EOF

chmod 755 "$P/claude" "$P/opencode"
```

确认这个目录在 PATH 里：

```sh
echo $PATH | tr ':' '\n' | grep script
```

不在的话，换一个 PATH 里可写且在 `/data` 下的目录。

---

## 7. 验证

```sh
cd /
claude --version
claude -p "Reply with exactly: BUILD_OK"
opencode run "Reply with exactly: BUILD_OK"
```

两个都返回 `BUILD_OK`，就成了。

---

## 8. 打包备份

别忘了这一步。新环境一定要重新打一份：

```powershell
powershell -ExecutionPolicy Bypass -File .\backup\backup.ps1
```

---

## 各组件体积参考

| 组件 | 体积 |
|---|---|
| Alpine base | 8 MB |
| Node.js 22 + npm | 110 MB |
| `@anthropic-ai/claude-code` | ~300 MB |
| `opencode-ai`（含 musl 二进制） | ~210 MB |
| ripgrep + bash + 其他 | ~30 MB |
| npm/apk 缓存（清掉后） | 0 |
| **合计** | **839 MB** |
