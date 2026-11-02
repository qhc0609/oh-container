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
│   ├── ohc-tty              把宿主机窗口尺寸同步到设备 pty（含后台跟随）
│   ├── oc-setkey            写入 OpenCode Key
│   ├── ohc-term.ps1         PC 侧启动器：读宿主机窗口尺寸 + 控制台缓冲区（翻页）
│   ├── ohc-gateway.ps1      PC 侧网关启动器：让 VS Code 用上这套 DeepSeek
│   ├── ohc-gateway-daemon.ps1 常驻守护：手机插上自动起网关（计划任务）
│   └── ohc-profile.ps1      一次性安装 hdc 包装层，让 hdc shell 自动带尺寸
├── device-bin/              放到设备 PATH 里的入口脚本
│   ├── claude
│   └── opencode
├── etc/                     配置模板
│   ├── claude.env           DeepSeek 端点 / 模型 / 超时等
│   ├── claude.json          .claude.json 种子（跳过引导、信任目录）
│   ├── opencode.json        默认模型（免费 DeepSeek）
│   ├── ohc-gw.mjs           OpenAI 兼容网关（容器内跑，给 PC 的 VS Code 用）
│   ├── continue-config.yaml VS Code 里 Continue 的模型配置模板
│   ├── ohc-tmux             容器内滚屏启动器（部署到 /usr/local/bin）
│   └── tmux.conf            tmux 配置：5 万行历史 + PageUp 直接翻页
├── backup/                  备份与一键恢复
│   ├── restore.ps1          刷机后恢复（推包 → 解压 → 修权限 → 验证）
│   ├── backup.ps1           重新打包
│   └── README.md            详细说明 + 手动兜底命令
├── docs/
│   └── build-rootfs.md      从零构建 rootfs（换发行版 / 想搞清里面有什么）
├── scripts/
│   ├── check-namespace.sh   探测设备 namespace / 权限 / 挂载（换设备先跑这个）
│   ├── test-deepseek.sh     裸测 DeepSeek 的 Anthropic 兼容端点
│   ├── push-via-api.sh      github.com 被墙时改走 Git Data API 推送
│   └── archive/             搭建过程中的一次性探测脚本，原样留档
├── articles/                公众号系列文章（5 篇 + 选题库）
└── deploy.ps1               把运行时 + 配置 + PATH 入口部署到设备
```

## 快速开始

**第一次：装一次包装层（让 `hdc shell` 带上宿主机窗口尺寸）**

```powershell
.\bin\ohc-profile.ps1
```

装完重开一个 PowerShell 窗口。

**日常使用**

```powershell
hdc shell
```

进去后敲 `claude` 或 `opencode`。窗口尺寸会跟着走，历史输出能翻页。

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

**先做一次性安装**，让 `hdc shell` 自动带上宿主机窗口尺寸（PowerShell 和 cmd 都支持）：

```powershell
.\bin\ohc-profile.ps1
```

装完重开一个 PowerShell 窗口。之后**照旧用 `hdc shell`**：

```powershell
hdc shell
```

进去后，**在任意目录（包括根目录 `/`）直接敲**：

```sh
claude              # 交互式启动，后端已经是 DeepSeek
claude -p "你好"    # 单次提问
```

窗口尺寸会跟着 PowerShell 窗口走，历史输出能翻页。原理见下面「终端尺寸与翻页」。

不想装包装层也可以直接跑启动器（效果一样，只是要记一个新命令）：

```powershell
.\bin\ohc-term.ps1
```

卸载包装层：`.\bin\ohc-profile.ps1 -Uninstall`

### 它是怎么做到"在 / 下也能直接敲 claude"的

设备的 `/` 是 `ro` 挂载，`/bin -> /system/bin` 也在只读分区，改不了。
但 `hdc shell` 的默认 PATH 是：

```
/vendor/python/python:/usr/local/bin:/bin:/usr/bin:/vendor/bin:/data/python/lib/python3.8/script/bin
```

最后一项 `/data/python/lib/python3.8/script/bin` 落在 `/data` 下，**可写且本来就在 PATH 里**。
所以把入口脚本放进去即可，不动系统分区、不需要 remount、重启不丢。

入口脚本内容就几行：

```sh
export OHC_QUIET=1
[ -x /data/ohc/bin/ohc-tty ] && /data/ohc/bin/ohc-tty
exec /data/ohc/bin/ohc-claude "$@"
```

### 终端尺寸与翻页（hdc 的两个坑）

**坑一：窗口尺寸是写死的，而且拿错了源。**

`hdc shell` 给设备 pty 的尺寸固定 80x24，环境里也写死 `COLUMNS=80 LINES=24`，
而且**它会覆盖你传进去的值**——实测 `COLUMNS=133 LINES=44 hdc shell` 进去仍是 `80 24`。
拖动 PowerShell 窗口也**不会**通知设备。于是 claude 的 TUI 永远按 80x24 排版，
窗口再大也只用到左上角。

关键认知：**尺寸必须来自 hdc 之外那个宿主机控制台**（PowerShell / cmd 的窗口），
而不是 hdc shell 里那个假的 80x24。hdc 自己不读、也不转发，只能由 PC 侧读出来再送进去。

**坑二：翻屏——真凶是 claude 自己的渲染器，既不在 hdc，也不在 tmux。**

先说清楚一件事，免得后面走弯路：**`hdc shell` 本身是能翻屏的**，宿主控制台
的缓冲区是累积的。所以「翻不动」不是宿主的锅。但一进 claude，120 行输出就只剩
最后十几行，往上翻什么都没有。

这里我连着误判了两次：

| 误判 | 做法 | 结果 |
|---|---|---|
| 一 | 调大宿主控制台 `BufferHeight` | 没用；而且窗口一放大必闪退（窗口宽 120 > 缓冲区宽 80 时再设高度是非法状态） |
| 二 | 容器里装 tmux，`history-limit 50000` | 还是空的。实测真 claude 跑在 tmux 里，`#{history_size}` **一直是 0** |

`history_size=0` 说明了一件很关键的事：**claude 一行都没有交给终端**。
不是 tmux 存不下，是压根没东西可存。

真凶在 claude 二进制里。2.x 默认用 **fullscreen renderer**：切备用屏幕 +
自己维护一块「虚拟滚动」的视口，用光标定位重画。120 行它只把最后十几行画到
屏幕上，其余的自己截掉——终端、tmux、宿主缓冲区全都不知道那些行存在过。

二进制里的原话（`busybox strings` 之后 grep 出来的）：

> It happened while the fullscreen renderer was starting, so the next launch
> will use the **classic renderer** (`CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1`
> forces that any time).

所以解法是一行 env，强制回到 classic renderer：

```sh
CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1
```

classic renderer 是顺序追加：行会真正流进 pty → hdc → PowerShell 的控制台缓冲区，
于是**直接拖 PowerShell 的滚动条 / 滚鼠标滚轮就能翻**，不用背任何快捷键。

两个配套结论：

- **别加 `CLAUDE_CODE_DISABLE_VIRTUAL_SCROLL`**。听着最对症，实测界面直接变空白。
- **默认不要再套 tmux**。tmux 只把「重画后的那一屏」交给 hdc，宿主的滚动条
  依然是空的，等于把已经到手的回滚能力挡住了。想要「断开还能接回同一个会话」
  的人再显式开：`OHC_TMUX=1 claude`（这条路下 `etc/tmux.conf` 里的
  `set -g alternate-screen off` 才有意义）。

配套改动：

- `etc/claude.env` → 容器 env：**`CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1`**（翻屏的根）
- `device-bin/claude`、`device-bin/opencode`：交互式**默认直接跑**，`-p` / `run` 同理；
  想要会话续接再显式 `OHC_TMUX=1 claude`
- `etc/ohc-tmux` → 容器内 `/usr/local/bin/ohc-tmux`，把 argv 逐个转义后交给
  `tmux new-session -A`（`-A`：已有会话就接上，断开后还能回来）
- `etc/tmux.conf` → 容器内 `/root/.tmux.conf`：5 万行历史、`alternate-screen off`、
  `PageUp` / `Ctrl+B [` 翻页（只在 `OHC_TMUX=1` 那条路下才用到）
- `TMUX_TMPDIR=/work/.tmux`：tmux 的 socket 默认放 `/tmp`，而 `ohc` 每次进来都会给
  `/tmp` 挂一个新的 tmpfs，等于每次都是全新服务端，`-A` 永远接不上上一次的会话。
  放到 `/work`（绑定到宿主 `/data/ohc/workspace`，刷机前都在）才真能续上
- `bin/ohc`：容器内**单独挂一次 devpts**。实测 `mount --rbind /dev` 在本机会退化成
  `--bind`，submount 没带进来，`/dev/pts` 是空目录 → tmux 报
  `create window failed: fork failed: No such device`。不指定 `newinstance`，
  和宿主的 `/dev/ptmx` 同实例，才能正常开 pty

实测（真 claude 跑在 100x30 的 tmux 里，让它输出 120 行「1」；
这里用 tmux 只是当**测量工具**——它的 `history_size` 涨了，等价于「这些行确实交给了终端」）：

| 项 | 未设 env（fullscreen renderer） | 设 `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` |
|---|---|---|
| `#{alternate_on}` | 0（tmux 已拦掉备用屏幕） | 0 |
| `#{history_size}` | **0** | **108** |
| 历史里「1」的行数 | **0** | **120** |
| 屏幕上能看到 | 最后十几行 | 最后一屏（其余在回滚区） |

结论：拦掉备用屏幕**不够**，必须让 claude 换回 classic renderer，
行才会交给终端。只关备用屏幕时 `history_size` 依然是 0。

> 同一个载荷换成裸脚本（`ESC[?1049h` + 喷 200 行）时，
> `alternate-screen off` 能让 `history_size` 到 177（= 200 − 24 + 1）——
> 这证明 tmux 那一侧没问题，问题只在 claude 的渲染器。
> 回归脚本：`scripts/test-scrollback.sh`（裸载荷）、`scripts/test-claude-render.sh`（真 claude）。

> 用 `busybox resize` 兜底那条路也试过：它本该发 CSI 18 t 问终端尺寸，
> 但这台设备上一次都没发出去，已删掉（详见上一节）。

### 窗口尺寸同步（`ohc-tty`）

修法（`bin/ohc-profile.ps1` + `bin/ohc-term.ps1` + `bin/ohc-tty`）：

```
PowerShell 窗口 [Console]::WindowWidth/Height
        │  每 500ms 轮询，变化才写
        ▼
/data/ohc/run/tty  （内容：行 列）
        ▼
设备侧 ohc-tty ── busybox stty -F /dev/pts/N rows R cols C ──▶ SIGWINCH ──▶ TUI 重画
```

- `bin/ohc-profile.ps1` 装一层同名包装：PowerShell 里是 `function hdc`，
  cmd 里是 `%LOCALAPPDATA%\oh-container\hdc.cmd`。
  拦到「`hdc shell` 且不带命令」时改走启动器，其它子命令原样透传给真 hdc
- `bin/ohc-term.ps1` 读宿主机控制台尺寸，写设备文件
- `bin/ohc-tty` 启动时应用一次，并起后台守护每秒比对文件，变了就改 pty

实测（容器内 Node 的 `process.stdout.columns`，也就是 ink 排版真正读的值）：

| 写入 `/data/ohc/run/tty` | 容器内 `stty size` | 容器内 `process.stdout` |
|---|---|---|
| `40 120` | `40 120` | `120x40` |
| `28 96` | `28 96` | `96x28` |
| `52 160` | `52 160` | `160x52` |

> 试过但**没用**的路：`busybox resize` 会发 CSI 18 t 问终端尺寸，理论上很优雅。
> 用真实 pty 抓字节流实测，这台设备上它**一次都没发出询问**、也不输出结果，
> 只会让启动白等 2 秒，已从 `ohc-tty` 里删掉。
>
> 手动再同步一次尺寸（会话里敲）：`/data/ohc/bin/ohc-tty`

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

---

## 11. 让 PC 上的 VS Code 用这套 DeepSeek

先分清一件事：**DeepSeek 不在手机里，在云上**。手机里装的是 claude 这个壳子，
它拿着你的 Key 去连 `api.deepseek.com`。所以「VS Code 用手机里的模型」这件事，
本质是「VS Code 怎么才能连上 `api.deepseek.com`」。

### 情况 A：PC 能上网（90% 的人）

别绕手机，直接连。VS Code 装 Continue / Cline / Roo Code，选 `OpenAI`（或
`OpenAI Compatible`）provider，填：

| 项 | 值 |
|---|---|
| Base URL | `https://api.deepseek.com/v1` |
| API Key | 你自己的 `sk-...` |
| Model | `deepseek-flash`（或 `deepseek-v4-pro`） |

手机、容器、hdc 全都不用管。

### 情况 B：PC 不能上网，只有手机能上网（本项目的真实场景）

这就是第 01 篇文章里那个场景：内网机器、涉密机器、临时工位，PC 连不上外网，
但 USB 口是通的、手机有流量。那就让手机当**中转站**：

```
VS Code ──http──▶ 127.0.0.1:18080 ──hdc fport(USB)──▶ 容器内 ohc-gw ──https──▶ api.deepseek.com
```

PC 上没有任何一包外网流量，走的是 USB 上的 hdc 端口转发。防火墙、代理、白名单全绕开。

#### 起网关

```powershell
cd <仓库目录>
powershell -ExecutionPolicy Bypass -File .\bin\ohc-gateway.ps1
```

它干四件事：把 `etc/ohc-gw.mjs` 推进容器 → 在容器里 `nohup node` 起来 →
`hdc fport tcp:18080 tcp:18080` → 自己打一遍 healthz 和一次真实对话验证。

成功的样子：

```
==> 建立端口映射（USB 转发）
    Forwardport result:OK
    [OK] 127.0.0.1:18080 -> 设备 18080
==> 验证通道
    [OK] healthz: ohc-gw ok
    [OK] 真实对话: 收到
```

#### VS Code 里填

| 项 | 值 |
|---|---|
| Provider | `OpenAI` / `OpenAI Compatible` |
| Base URL | `http://127.0.0.1:18080/v1` |
| API Key | `sk-any-nonempty`（**随便填个非空串**，网关会换成真 Key） |
| Model | `deepseek-flash` 或 `deepseek-v4-pro` |

Continue 的 `config.json`：

```json
{
  "models": [{
    "title": "DeepSeek (via phone)",
    "provider": "openai",
    "model": "deepseek-flash",
    "apiBase": "http://127.0.0.1:18080/v1",
    "apiKey": "sk-any-nonempty",
    "completionOptions": { "maxTokens": 4096 }
  }]
}
```

Cline / Roo Code：Provider 选 `OpenAI Compatible`，Base URL 填上面那个，
勾上「支持流式」即可。

#### 管它

```powershell
.\bin\ohc-gateway.ps1 -Status    # 看进程和端口映射还在不在
.\bin\ohc-gateway.ps1 -Stop      # 用完关掉
```

拔 USB、手机重启，映射就没了，重跑一次启动命令即可。

### 为什么中间要加一层网关

理论上 `hdc fport` 直接转发到 `api.deepseek.com:443` 不行吗？不行，
`fport` 只能转发到**设备上的端口**，不能替你做 TLS 和目标域名解析。
所以容器里必须有个进程真的去发那个 HTTPS 请求，`ohc-gw.mjs` 就是它——
一个 90 行的 Node 脚本，把 `/v1/*` 原样转给上游，顺手把 `Authorization` 换成
容器 env 里的真 Key。

顺带的好处：Key 只存在手机里（`/data/ohc/containers/claude/env`，600 权限），
PC 的 VS Code 配置里那个 Key 是假的，配置文件被同事看到、被同步到云端都不怕。

### 三个坑（都实测踩过）

**1. `max_tokens` 给小了，模型「不回话」**

`deepseek-flash` 是推理模型，思考过程也占 `max_tokens`。给 64 的结果：

```
max_tokens=64   content_len=0    completion=64      ← 全花在思考上，content 是空串
max_tokens=800  content_len=144  completion=84      ← 正常
```

界面上的表现就是「有回复，但内容是空的」，很容易误判成网关坏了。
所以 `ohc-gw.mjs` 里加了个下限：请求里的 `max_tokens` 小于 2048 就抬到 2048
（可用环境变量 `OHC_GW_MIN_MAXTOKENS` 改）。修完之后：

```
max_tokens=64   content_len=144   completion=84     ← 抬到 2048 了
```

**2. `hdc fport rm` 也必须是两个独立参数**

`fport` 要两个参数这事已经踩过一次，`rm` 竟然一样：

```powershell
hdc fport rm "tcp:18080 tcp:18080"    # [Fail] ruler is not exist  ← 静默失败，返回码还是 0
hdc fport rm tcp:18080 tcp:18080      # Remove forward ruler success
```

拼成一个字符串时它**不删也不报错**（返回码 0）。后果是下一次 `fport` 建映射时
报 `TCP Port listen failed at 18080`——端口被上一次的残留占着。
你以为新映射建好了，其实一直在用旧的。排查了半天才发现是这行。

**3. PowerShell 5.1 的编码是双向的坑**

发出去：

```powershell
Invoke-RestMethod -Body $jsonString -ContentType 'application/json'   # 中文变 '?'
```

PS 5.1 对没有 `charset` 的 content-type 按 ASCII 编码 body，要显式加
`; charset=utf-8` **并传字节数组**。

收回来：

```
content = "æ¶å°"      ← 这是 "收到"，6 个字符
```

DeepSeek 上游返回的 `content-type` 只有 `application/json`，不带 charset，
PS 5.1 就按 **Latin-1** 解码，一个 UTF-8 汉字被拆成两三个乱码字符。
所以 `ohc-gw.mjs` 里统一给响应补 `; charset=utf-8`，修完 `content.Length = 2`。

VS Code 的插件走 Node 的 fetch，本来就不受影响——只有 PC 侧的自检脚本会被坑，
很容易误判成「网关把中文搞坏了」。

另外 `Invoke-WebRequest` 的进度条会往控制台乱写，把输出搅成一团，
脚本开头要 `$ProgressPreference = 'SilentlyContinue'`。

### 实测记录

```
healthz                          -> ohc-gw ok
/v1/models                       -> deepseek-flash, deepseek-v4-pro
非流式 chat (max_tokens=800)     -> content=收到, completion=251
流式 chat (stream=true)          -> 50 个 SSE chunk, 拼出 "1、2、3、4、5"
max_tokens=64 自动抬升           -> content_len=144（修复前是 0）
响应补 charset 后                -> content.Length=2, codepoints=25910,21040（收、到）
```

---

## 12. VS Code 一键配置（不用手工填任何东西）

上一章讲的是「怎么配」，这一章是**已经配好之后长什么样**，以及怎么复现。

### 为什么没用 VS Code 自带的 Copilot BYOK

VS Code 1.144 内置了 Copilot，也支持 `chatLanguageModels.json` 接第三方模型，
听起来是最短路径。但实测这台机器上：

```
state.vscdb -> extensionsIdentifiers/disabled = [{"id":"github.copilot-chat"}]
           -> chat.setupContext = {"installed":true,"disabled":true}
```

Copilot Chat 是被**显式禁用**的，没有聊天面板，BYOK 配置再好也没地方用。
而改 `state.vscdb` 必须在 VS Code 关闭时做，风险高、收益低。

所以走 **Continue 扩展**：自带侧边栏聊天面板，不依赖 Copilot，配置就是一个 YAML 文件。

### 装了/写了什么

| 位置 | 内容 |
|---|---|
| `~/.vscode/extensions/continue.continue-2.0.0-win32-x64/` | Continue 扩展本体 |
| `~/.continue/config.yaml` | 两个模型，都指向 `http://127.0.0.1:18080/v1` |
| `%LOCALAPPDATA%\ohc-gateway\ohc-gateway-daemon.ps1` | 守护进程（开机自启） |
| `%LOCALAPPDATA%\ohc-gateway\ohc-gw.mjs` | 网关脚本副本，仓库不在了也能跑 |
| 计划任务 `ohc-gateway-daemon` | 登录时启动守护进程 |

`config.yaml` 的核心就这几行：

```yaml
models:
  - name: DeepSeek V4.1 Flash（手机中转）
    provider: openai
    model: deepseek-flash
    apiBase: http://127.0.0.1:18080/v1
    apiKey: sk-ohc-gateway        # 假的，网关会换成手机里的真 Key
    contextLength: 65536
    roles: [chat, edit, apply]
    capabilities: [tool_use]
    defaultCompletionOptions:
      maxTokens: 8192             # 别低于 2048，见上一章坑 1
```

写完用 Continue 自己的 schema 校验过一遍：

```
PASS  config.yaml 通过 Continue 官方 schema 校验
  - DeepSeek V4.1 Flash（手机中转）: provider=openai model=deepseek-flash roles=['chat','edit','apply']
  - DeepSeek V4 Pro（手机中转）:     provider=openai model=deepseek-v4-pro  roles=['chat','edit','apply']
```

Continue 启动后自动选中了它（`~/.continue/index/globalContext.json`）：

```json
{"local": {"chat": "DeepSeek V4.1 Flash（手机中转）",
           "edit": "DeepSeek V4.1 Flash（手机中转）",
           "apply": "DeepSeek V4.1 Flash（手机中转）"}}
```

### 怎么用

打开 VS Code，**`Ctrl+L`** 打开 Continue 聊天框，直接问就行。

第一次装完扩展要重载窗口：新开一个窗口，或 `Ctrl+Shift+P` → `Reload Window`。

### 手机插上就自动可用

不用再手动跑脚本。计划任务在登录时拉起守护进程，它每 5 秒看一眼设备：

```
[00:46:11] 检测到设备 03516892320539，开始准备网关
[00:46:14] 网关已启动 pid=7248
[00:46:15] 端口映射已建立 tcp:18080
[00:46:15] 就绪，VS Code 现在可以用了
```

拔掉手机：

```
[00:52:03] 设备已断开，收掉网关
```

管理命令：

```powershell
$d = "$env:LOCALAPPDATA\ohc-gateway\ohc-gateway-daemon.ps1"
powershell -ExecutionPolicy Bypass -File $d -Status      # 看任务状态 + 最近日志
powershell -ExecutionPolicy Bypass -File $d -Install     # 重装/修复计划任务
powershell -ExecutionPolicy Bypass -File $d -Uninstall   # 卸载
powershell -ExecutionPolicy Bypass -File $d -Once        # 前台跑一轮，排查用
```

网关自己在设备上打访问日志，排查「VS Code 到底有没有打到网关」看这里：

```powershell
hdc shell "tail -5 /data/ohc/workspace/ohc-gw.log"
# 2026-11-02T16:48:19.749Z GET /healthz -> 200 15ms
# 2026-11-02T16:51:02.113Z POST /v1/chat/completions -> 200 3412ms
```

### 一个提醒

Continue 的 `apiKey` 是假的（`sk-ohc-gateway`），**网关只认真 Key 在手机里**。
所以这份 `config.yaml` 就算被同步到云端、发给同事，也不泄露任何东西。


