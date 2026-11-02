# ohc —— OpenHarmony 上的极简容器 + claude(DeepSeek)

在 OpenHarmony 4.0 设备上，用一套**从零写的容器运行时**把 claude code 跑起来，
后端走自己的 DeepSeek API Key，模型 `deepseek-flash`（DeepSeek-V4.1-Flash-1017）。

同一个容器里还装了 `opencode`，走 OpenCode Zen 的**免费** DeepSeek V4.1 Flash。
外加一套 834MB 整包备份 + 56 秒一键恢复。

> 不依赖 docker / runc / podman / lxc。运行时本体是一个 10KB 的 POSIX sh 脚本。

---

## 仓库结构

```
oh-container/
├── bin/                     容器运行时与工具（部署到设备 /data/ohc/bin/）
│   ├── ohc                  运行时本体，POSIX sh，约 10KB
│   ├── ohc-claude           启动 claude 的底层入口
│   ├── ohc-setkey           写入 DeepSeek Key
│   ├── ohc-verify           端到端自检（配置→依赖→裸接口→claude→TUI）
│   └── oc-setkey            写入 OpenCode Key
├── device-bin/              放到设备 PATH 里的入口脚本
│   ├── claude
│   └── opencode
├── etc/                     配置模板
│   ├── claude.env           DeepSeek 端点 / 模型 / 超时等
│   ├── claude.json          .claude.json 种子（跳过引导、信任目录）
│   └── opencode.json        默认模型（免费 DeepSeek）
├── backup/                  备份与一键恢复
│   ├── restore.ps1          刷机后恢复（推包 → 解压 → 修权限 → 验证）
│   ├── backup.ps1           重新打包
│   └── README.md            详细说明 + 手动兜底命令
├── docs/
│   └── build-rootfs.md      从零构建 rootfs（换发行版 / 想搞清里面有什么）
├── scripts/
│   ├── check-namespace.sh   探测设备 namespace / 权限 / 挂载（换设备先跑这个）
│   ├── test-deepseek.sh     裸测 DeepSeek 的 Anthropic 兼容端点
│   └── archive/             搭建过程中的一次性探测脚本，原样留档
├── articles/                公众号系列文章（5 篇 + 选题库）
└── deploy.ps1               把运行时 + 配置 + PATH 入口部署到设备
```

## 快速开始

**情况 A：设备上已经有环境（或刚刷完机要恢复）**

```powershell
cd backup
powershell -ExecutionPolicy Bypass -File .\restore.ps1
```

**情况 B：rootfs 已经有了，只想部署/更新运行时和配置**

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Key sk-你的DeepSeekKey
```

**情况 C：从零开始**

先读 [`docs/build-rootfs.md`](docs/build-rootfs.md)。

## 公众号系列

| # | 标题 | 文件 |
|---|---|---|
| 1 | 我在这台鸿蒙手机上从零写了个容器，然后把 Claude Code 跑了进去 | [`articles/01-容器篇.md`](articles/01-容器篇.md) |
| 2 | 让手机上的 Claude Code 用上 DeepSeek V4.1 Flash：一行命令，五个坑 | [`articles/02-claude接DeepSeek.md`](articles/02-claude接DeepSeek.md) |
| 3 | 白嫖 DeepSeek V4.1 Flash：在手机上装 opencode 的免费模式 | [`articles/03-opencode免费DeepSeek.md`](articles/03-opencode免费DeepSeek.md) |
| 4 | 我亲手 rm -rf 了自己搭了三小时的环境，然后 56 秒把它救回来 | [`articles/04-备份与一键恢复.md`](articles/04-备份与一键恢复.md) |
| 5 | 我在一个 297MB 的二进制里 grep 出了两个官方文档没有的环境变量 | [`articles/05-从二进制里挖隐藏变量.md`](articles/05-从二进制里挖隐藏变量.md) |

还有 12 个未写选题：[`articles/06-选题库.md`](articles/06-选题库.md)

---

## 1. 设备实测信息

| 项 | 值 |
|---|---|
| OpenHarmony 版本 | `OpenHarmony-4.0.10.13`（`const.ohos.fullname`） |
| API Version | 10 |
| 设备型号 | `TaiHang2102` |
| 系统软件版本 | `Taihang_TX_V2.00.58` |
| 内核 | `Linux 5.10.79 aarch64` |
| CPU | Cortex-A55（`CPU part 0xd05`） |
| SELinux | Permissive（`enforce=0`） |
| hdc | `Ver: 3.2.0f`，位于 `C:\Tools\HarmonyOS\toolchains\hdc.exe` |
| 设备序列号 | `03516892320539` |

复现命令：

```powershell
hdc shell param get const.ohos.fullname
hdc shell param get const.ohos.apiversion
hdc shell param get const.product.software.version
hdc shell uname -a
```

---

## 2. 内核能力边界（决定了容器长什么样）

这不是"配一下就好"的问题，是内核编译时就没开：

| 能力 | 状态 | 影响 |
|---|---|---|
| mount namespace | 可用 | 容器挂载点与宿主隔离 |
| uts namespace | 可用 | 容器有独立 hostname |
| ipc namespace | 可用 | 独立 SysV IPC / 共享内存 |
| net namespace | 可用 | 本方案**不启用**，容器直接用宿主网络 |
| **PID namespace** | **不可用** | `/proc/self/ns` 无 `pid`，`unshare -p` 返回 EINVAL |
| **user namespace** | **不可用** | `unshare -U` 返回 EINVAL |

所以本容器是「**mount + uts + ipc 隔离 + chroot 根切换**」的最小实现，
不是 Docker 那种全隔离。**容器内进程列表与宿主共享，没有 PID 1，不能做 init 回收**。

其他实测结论：

- `hdc shell` 落地身份是 `uid=0(root)`，`CapEff=000001ffffffffff`（全 capability），`Seccomp=0`
- `/data` 挂载参数 `nodev,nosuid`，但**没有 noexec**，所以 `node` 二进制可以正常执行
- `/storage` 带 `noexec`，**不要把 rootfs 放那儿**
- toybox 0.8.2：没有 `awk`；`grep` 读管道会报 `Invalid argument` → 运行时里统一退回 `busybox`
- 系统自带 `busybox 1.36.1`、`chroot`、`pivot_root`、`unshare`、`nsenter`

---

## 3. 目录结构

设备上：

```
/data/ohc/
├── bin/ohc                  # 容器运行时（POSIX sh，从零写）
├── bin/ohc-claude           # 启动 claude 的底层入口
├── bin/ohc-setkey           # 安全写入 DeepSeek Key
├── bin/ohc-verify           # 端到端自检
├── rootfs/claude/           # 容器根文件系统（Alpine 3.21.3）
├── containers/claude/env    # 容器环境变量（含 DeepSeek Key，权限 600）
├── workspace/               # 容器内 /work 的实体目录，claude 改的文件落在这里
├── scripts/                 # 留档的安装 / 测试脚本
└── logs/

/data/python/lib/python3.8/script/bin/claude
                             # 放进设备 PATH 的 claude 入口，见第 6 节
```

---

## 4. 容器运行时做了什么

`ohc run <name> -- <cmd>` 的完整动作序列：

1. **网络自检** —— OpenHarmony 的 `wlan0` 经常只有链路路由、没有默认路由，
   导致容器里 DNS 能解析但 TCP 出不去。运行时检测到缺默认路由就补一条（幂等，可用 `OHC_NO_NETSETUP=1` 关闭）。
2. **创建 namespace** —— `unshare -m -u -i`。关键点：**不带 `-f`**。
   因为 PID namespace 不可用，不需要 fork 子进程当 PID 1；不带 `-f` 时 `unshare` 直接 exec 目标命令，
   进程的 stdin/stdout 原样保留，**交互式 TTY 不会被切断**（claude 必须有 tty）。
3. **挂载树私有化** —— `mount --make-rprivate /`，防止容器内挂载传播回宿主。
4. **挂载文件系统** —— `proc`、`sys`(bind)、`dev`(rbind，带上宿主 pts 保证有 tty)、`tmp`(tmpfs)。
5. **注入 DNS** —— 写容器内 `/etc/resolv.conf`（223.5.5.5 / 114.114.114.114）。
6. **加载环境变量** —— `set -a` 后 source `containers/<name>/env`，导出 PATH/HOME/TERM/LANG。
   `HOME` 强制为 `/root`（不能用宿主继承来的 `/`）。
7. **切根执行** —— `chroot <rootfs> /bin/sh -c 'cd /; exec "$@"'`。

退出时 namespace 销毁，容器内挂载自动回收，宿主不受影响。

### 子命令

```sh
ohc doctor                          # 自检：namespace 支持、SELinux、路由
ohc create <name> [--from <dir>]    # 创建容器
ohc run <name> [--] [cmd...]        # 启动并执行（默认 /bin/sh）
ohc shell <name>                    # 交互 shell
ohc ls / info <name> / net / rm <name>
```

---

## 5. claude 侧的关键配置

`/data/ohc/containers/claude/env`：

```sh
ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
ANTHROPIC_AUTH_TOKEN=sk-你的key
ANTHROPIC_MODEL=deepseek-flash
ANTHROPIC_SMALL_FAST_MODEL=deepseek-flash
USE_BUILTIN_RIPGREP=0
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
API_TIMEOUT_MS=600000
CLAUDE_CODE_MAX_CONTEXT_TOKENS=200000
CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1
```

### 四个容易踩的坑（都是实测踩出来的）

1. **模型名用 `deepseek-flash`**。官方文档明确：`deepseek-v4-flash` 是遗留名（仍可用但已路由到
   V4.1-Flash-1017），新代码用 `deepseek-flash`。想要更强的推理换成 `deepseek-v4-pro`。
2. **`USE_BUILTIN_RIPGREP=0`**。claude 内置的 ripgrep 是 glibc 版，Alpine(musl) 下跑不起来，
   必须用 `apk add ripgrep` 装的系统版。
3. **认证两种都行**：`x-api-key`（`ANTHROPIC_API_KEY`）或 `Authorization: Bearer`（`ANTHROPIC_AUTH_TOKEN`）。
4. **`HOME` 必须强制成 `/root`**。`hdc shell` 环境里 `HOME=/`，会一路传进容器，
   导致 claude 把配置写到根目录的 `/.claude.json`。运行时的 `cmd_inner` 里已经强制 `export HOME=/root`。

另外，`source env` 必须包在 `set -a` 里，否则变量只是 shell 局部变量、传不进 `exec` 出去的 claude，
表现就是 **"Not logged in · Please run /login"**（这个坑已经修在 `ohc` 里）。

---

## 6. 使用（最常用：进去直接敲 claude）

```powershell
hdc shell
```

进去后，**在任意目录（包括根目录 `/`）直接敲**：

```sh
claude              # 交互式启动，后端已经是 DeepSeek
claude -p "你好"    # 单次提问
```

就这两条，不需要先切目录、不需要记路径。

### 它是怎么做到"在 / 下也能直接敲 claude"的

设备的 `/` 是 `ro` 挂载，`/bin -> /system/bin` 也在只读分区，改不了。
但 `hdc shell` 的默认 PATH 是：

```
/vendor/python/python:/usr/local/bin:/bin:/usr/bin:/vendor/bin:/data/python/lib/python3.8/script/bin
```

最后一项 `/data/python/lib/python3.8/script/bin` 落在 `/data` 下，**可写且本来就在 PATH 里**。
所以把入口脚本放进去即可，不动系统分区、不需要 remount、重启不丢。

入口脚本内容就三行：

```sh
export OHC_QUIET=1
exec /data/ohc/bin/ohc-claude "$@"
```

### 工作目录

容器启动时会把宿主 `/data/ohc/workspace` 绑定到容器内 `/work`，并 `cd /work`。
也就是说 **claude 在容器里改的文件，宿主上在 `/data/ohc/workspace` 能看到**，重启不丢。

### 其它入口（保留）

```sh
/data/ohc/bin/ohc-claude              # 等价的底层入口
/data/ohc/bin/ohc shell claude        # 只进容器，不启 claude
/data/ohc/bin/ohc-setkey sk-xxxx      # 换 key
/data/ohc/bin/ohc-verify              # 端到端自检
```

> 交互式使用必须是真的终端（`hdc shell` 交互进来就带 pty）。脚本里调用请用 `claude -p`。

---

## 7. 实测验证结果

| 验证项 | 结果 |
|---|---|
| 容器内 Alpine 版本 | 3.21.3 |
| 容器内 hostname | `claude`（宿主仍为 `localhost`） |
| 宿主 `/data/ohc` 在容器内可见性 | 不可见（chroot 生效） |
| 容器内 Node / npm | v22.23.4 / 10.9.1 |
| 容器内 claude | 2.1.316 (Claude Code) |
| 容器内 ripgrep / bash | 14.1.1 / 5.2.37 |
| 直连 DeepSeek `/anthropic/v1/messages` | **HTTP 200**，`"model":"deepseek-flash"` |
| `claude -p` 单次调用 | 退出码 0，正常返回文本 |
| 交互式 TUI | pty 下正常启动，约 2 秒出界面 |
| 从 `/` 敲 `claude` | 直接启动，无需切换目录 |
| 容器内工作目录 | `/work`（绑定宿主 `/data/ohc/workspace`） |
| claude 侧计费记录 | `.claude.json` 里 `lastModelUsage` 已记录 `deepseek-flash` 的 token 消耗 |

实测一次 `claude -p` 的回答（在设备 `/` 目录下敲的命令）：

```
我的模型名为 deepseek-flash，运行在 Linux（5.10.79，bash shell）环境下，工作目录为 /work。
```

---

## 8. 已知限制

- 无 PID namespace：容器内 `ps` 能看到宿主全部进程，不能隔离进程树
- 无 user namespace：容器内是 root，等于宿主 root（本机 SELinux 是 Permissive，没有额外兜底）
- 网络与宿主共享：容器内可以直接访问宿主网络接口
- 因此这套东西适合**自己设备上跑开发工具**，不适合多租户或不可信负载

---

## 9. 刷机后的恢复（重要）

整套环境已打包备份到 PC，刷机清空 `/data` 后**一条命令还原，全程不联网安装**。

详见 [`backup/README.md`](backup/README.md)。最简用法：

```powershell
cd oh-container\backup
powershell -ExecutionPolicy Bypass -File .\restore.ps1
```

| 项 | 值 |
|---|---|
| 备份包 | `backup/ohc-backup.tar.gz`（834.7 MB） |
| SHA256 | `E756D43F104672ADE12AF360F9B2673BAA2A40AFBF410CE3BC11E35ABEDE58A2` |
| 推送耗时 | 约 34 秒（26 MB/s） |
| 解压耗时 | 约 22 秒 |
| 全流程耗时 | **约 56 秒** |

已实测：删掉 `/data/ohc` 和 `/data/python` 模拟刷机，跑 `restore.ps1` 后
`claude` 和 `opencode` 都回到 PATH、版本正确、DeepSeek 调用返回预期标记、
OpenCode 登录状态保留（不用重新登录）、容器内 `cwd=/work` 全部正常。

环境有改动（换 key、升级 claude）后，用 `backup.ps1` 重新打包即可。

---

## 10. opencode（走 OpenCode Zen 免费 DeepSeek）

同一个容器里还装了 **opencode 1.19.5**，默认模型是 OpenCode Zen 的**免费** DeepSeek：

```
opencode/deepseek-v4.1-flash-free
```

### 用法

```powershell
hdc shell
```
```sh
opencode                                  # 交互式 TUI
opencode run "解释一下这段代码"            # 单次提问
opencode run -m opencode/deepseek-v4-pro "..."   # 临时换付费模型
oc-setkey oc_sk_xxxx                      # 换 OpenCode Key
```

### 关于"免费"

- **不需要绑卡**，但要 **OpenCode 账号的 API Key**（`https://opencode.ai/console` 生成，形如 `oc_sk_...`）。
  这不是 DeepSeek 的 key，免费额度是 OpenCode 的网关在兜。
- **免费模型只能通过 opencode 自己的客户端调用**。用裸 `curl` 打同一个模型会返回
  `429 FreeUsageLimitError`——这是它的设计，不是额度用完。
- 免费档有速率限制；重度使用要转 OpenCode Go 订阅或换回自己的 DeepSeek key（`claude` 那条路）。
- 数据政策：官方模型页标注 `DeepSeek V4.1 Flash Free` 是 **zero-retention provider**。

### 配置文件位置（容器内）

| 文件 | 作用 |
|---|---|
| `/root/.config/opencode/opencode.json` | 默认模型 |
| `/root/.local/share/opencode/auth.json` | OpenCode API Key（600 权限） |

两个都在 rootfs 里，会被打进备份，**刷机恢复后不用重新登录**。

### 两个坑

1. **`opencode run` 在非交互环境会一直等 stdin**，表现为卡住不动。
   入口脚本 `/data/python/lib/python3.8/script/bin/opencode` 已经对 `run` 子命令自动加 `< /dev/null`。
2. **npm 会把 glibc 和 musl 两份二进制都装上**（各 200MB+）。
   Alpine 只用 musl 版，glibc 那份已删，省了 202MB。删之前实测过 `opencode` 仍正常。

### 模型清单（已认证后）

```
opencode/deepseek-v4.1-flash-free    # 免费
opencode/deepseek-v4.1-flash         # 付费
opencode/deepseek-v4-pro             # 付费
```

`opencode models` 可随时查看完整列表。
