# 02｜让手机上的 Claude Code 用上 DeepSeek V4.1 Flash：一行命令，五个坑

> 系列第二篇。上一篇把容器建好了，这篇把 AI 接进去。
> 代码：`qhc0609/oh-container`

---

上一篇结束时，容器能进去了。你兴冲冲敲下 `claude`。

```
Not logged in · Please run /login
```

按提示敲 `/login`，它让你开浏览器做 OAuth。手机上没有浏览器，就算有，你也不想为这个注册账号。

这篇解决的就是这件事：**让 claude 认 DeepSeek，不认 Anthropic 账号。**

---

## 一、DeepSeek 有个 Anthropic 兼容端点

这件事很多人不知道。

DeepSeek 除了自己的 OpenAI 格式接口，还专门开了一个 Anthropic 兼容端点，路径是：

```
https://api.deepseek.com/anthropic
```

意思就是：**claude 这个客户端，可以原封不动地去调 DeepSeek**。它以为自己在调 Anthropic，实际上对面是 DeepSeek 的服务器。

这是整件事的技术前提。没有这个端点，一切免谈。

先用裸 curl 验证它真的通，别急着配 claude：

```sh
curl -s https://api.deepseek.com/anthropic/v1/messages \
  -H "content-type: application/json" \
  -H "x-api-key: sk-你的key" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"deepseek-flash","max_tokens":64,
       "messages":[{"role":"user","content":"只回答两个字：通了"}]}'
```

返回里能看到 `"model":"deepseek-flash"` 和正常的内容块，就说明三件事都没问题：key 有效、网络通、模型名对。

**这一步千万别跳。** 后面 claude 出问题时，你就靠这个来判断到底是 key 的问题还是 claude 配置的问题。分不清的话，你会在这两个方向上来回瞎改。

我把这个测试写成脚本了：`scripts/test-deepseek.sh`。

---

## 二、模型名：`deepseek-flash`，不是 `deepseek-v4-flash`

这是第一个坑，而且官方文档里藏得很深。

网上很多教程写 `deepseek-v4-flash`，这个名**还能用**，但它是个遗留别名，实际会被路由到 `DeepSeek-V4.1-Flash-1017`。新代码应该直接用：

```
deepseek-flash
```

想要更强的推理，换 `deepseek-v4-pro`。

在 claude 里怎么确认自己真用上了？问它：

```
> 你是什么模型
```

它会回：

```
我的模型名为 deepseek-flash
```

因为 DeepSeek 会在响应里把真实模型名带回来，claude 会照实说。如果它说自己是 `claude-sonnet-4-5`，那说明你的请求根本没走 DeepSeek，还在打 Anthropic 官方。

---

## 三、配置：一个文件，十一行

claude 认环境变量。全部配置就一个文件，放在宿主上：

`/data/ohc/containers/claude/env`

```sh
ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
ANTHROPIC_AUTH_TOKEN=sk-你的key
ANTHROPIC_MODEL=deepseek-flash
ANTHROPIC_SMALL_FAST_MODEL=deepseek-flash

USE_BUILTIN_RIPGREP=0
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
DISABLE_AUTOUPDATER=1
DISABLE_TELEMETRY=1
DISABLE_ERROR_REPORTING=1

API_TIMEOUT_MS=600000
CLAUDE_CODE_MAX_CONTEXT_TOKENS=200000
CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1
```

权限必须是 600，里面有明文 key：

```sh
chmod 600 /data/ohc/containers/claude/env
```

逐行解释一下值得解释的。

**`ANTHROPIC_SMALL_FAST_MODEL`**

claude 内部有些小任务（比如给对话起标题、判断意图）会用"快模型"。不设这个，它会去调 `claude-3-5-haiku`，DeepSeek 那边没有这个模型，直接 404。设成同一个就行。

**`USE_BUILTIN_RIPGREP=0`**

这个坑很硬。claude 的 npm 包里**自带一个 ripgrep 二进制**，是 glibc 编译的。Alpine 用的是 musl。两者 ABI 不兼容。

不设这一行，claude 一起来就崩，报错长得像这样：

```
Error: spawn .../vendor/ripgrep/arm64-linux/rg ENOENT
```

或者更莫名其妙的 `Exec format error`。

设成 0，它就会用系统 PATH 里的 `rg`——前提是你 `apk add ripgrep` 装过了。这一步在上一篇里做过了。

**`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`**

claude 默认会往 Anthropic 发一些遥测、版本检查、feature flag 请求。在 DeepSeek 这条路上这些请求全是 404 或者超时，白白拖慢启动，日志里一堆红字。关掉。

**`API_TIMEOUT_MS=600000`**

默认超时对手机网络太短。DeepSeek 在长上下文时首字延迟可能到十几秒，默认值会直接掐断。给到 10 分钟。

**最后两行是"消警告"的。**

claude 认识 Anthropic 那几个模型，知道它们的上下文窗口是 200K。碰到 `deepseek-flash` 这个陌生名字，它会警告：

```
⚠ Large files detected. Model has limited context window...
```

或者每次启动都提示上下文窗口未知。这两行告诉它：窗口是 200K，别猜了。

> 这两个变量名不在任何文档里。我是从 297MB 的 claude 二进制里 grep 出来的，过程写在第五篇。

---

## 四、那个"明明配了却说没登录"的坑

配好文件，进容器，敲 `claude`。

```
Not logged in · Please run /login
```

文件明明在，`cat` 出来内容也对。

我在这上面花了两个小时，中间重新生成了三次 key。

原因是 `source` 和 `export` 的区别。

运行时的代码本来是：

```sh
. /data/ohc/containers/claude/env     # 这样不行
```

`source` 一个文件，里面的 `VAR=value` 会变成**当前 shell 的变量**。但当前 shell 马上就要 `exec` 成 `claude` 了，`exec` 只继承**被导出（exported）**的变量。

所以 `ANTHROPIC_AUTH_TOKEN` 在 shell 里 `echo $ANTHROPIC_AUTH_TOKEN` 有值，`claude` 进程里就是空的。

改一行：

```sh
set -a
. /data/ohc/containers/claude/env
set +a
```

`set -a` 的意思是"从现在开始，所有赋值的变量自动 export"。`set +a` 关掉。

改完立刻通了。

**这个坑的恶劣之处在于它的报错完全指向错误方向。** 它说"没登录"，你会去查 key；key 没问题，你会去查网络；网络没问题，你会去查 base url。全查一遍，全是对的。真正的原因在一个你根本不会怀疑的地方。

---

## 五、`HOME` 必须强制成 `/root`

第二个隐蔽坑。

`hdc shell` 这个环境里：

```sh
$ echo $HOME
/
```

因为你的 uid 是 0，家目录就是 `/`。

这个值会一路继承进容器。于是 claude 认为自己的家目录是 `/`，把 `.claude.json` 写到 `/.claude.json`——容器的根目录。

后果不是立刻报错，是**行为诡异**：

- 每次启动都问"是否信任这个目录"
- 明明点过"信任"，下次还问
- 换个工作目录，配置全丢
- `/work` 和 `/` 各有一份信任状态，互相打架

修法就一行，在 `cmd_inner` 里：

```sh
export HOME="${OHC_HOME:-/root}"
```

改完把已经写错位置的文件搬过去：

```sh
mv /.claude.json /root/.claude.json
```

然后手动把信任状态改成 `true`，省得每次弹窗：

```sh
sed -i 's/"hasTrustDialogAccepted": false/"hasTrustDialogAccepted": true/g' /root/.claude.json
```

---

## 六、最爽的一步：在根目录直接敲 `claude`

到这里，你得这么用：

```sh
hdc shell
/data/ohc/bin/ohc run claude -- claude
```

能用，但丑。每次都要记一条长命令。

我想要的是：`hdc shell` 进去，落在 `/`，敲 `claude`，直接起来。

**问题：`/` 是只读的。**

```sh
$ mount | grep ' / '
/dev/block/dm-2 on / type ext4 (ro,seclabel,relatime)

$ ls -l /bin
lrwxrwxrwx 1 root root 8 /bin -> /system/bin
```

`/` 挂的是 `ro`，`/bin` 是个指向只读分区的软链接。改不了。

**但是 PATH 里有个后门。**

```sh
$ echo $PATH
/vendor/python/python:/usr/local/bin:/bin:/usr/bin:/vendor/bin:/data/python/lib/python3.8/script/bin
```

看最后一项：`/data/python/lib/python3.8/script/bin`。

这个目录在 `/data` 下。`/data` 是**可写**的。而且它**本来就在 PATH 里**。

也就是说：往这个目录里丢一个叫 `claude` 的可执行文件，你在任何目录敲 `claude` 都会命中它。

不用改系统分区，不用 remount，重启不丢。

那个文件的内容，三行：

```sh
#!/bin/sh
export OHC_QUIET=1
exec /data/ohc/bin/ohc-claude "$@"
```

`OHC_QUIET=1` 是关掉运行时那些 `[ohc] 进入容器...` 的日志，不然每次启动都刷一行，很难看。

```sh
chmod 755 /data/python/lib/python3.8/script/bin/claude
```

然后：

```sh
$ cd /
$ claude
```

起来了。

> 换 ROM 的话这个 PATH 可能会变。先用 `echo $PATH` 看一眼，找里面任何一个在 `/data` 下的可写目录，把文件丢进去就行。`restore.ps1` 最后会检查这件事。

---

## 七、`-p` 模式会卡三秒

交互式没问题了，写脚本调用就发现新毛病：

```sh
$ claude -p "你好"
（等三秒）
（才出结果）
```

不是慢，是**在等 stdin**。

`-p`（print）是非交互模式，但 claude 还是会检查 stdin 有没有输入。如果 stdin 是个没关闭的管道或者终端，它就一直等到超时。

修法在包装脚本里，判断到 `-p` 或 `--print` 就重定向：

```sh
case " $* " in
    *" -p "*|*" --print "*)
        exec "$OHC" run claude -- claude "$@" < /dev/null ;;
esac
exec "$OHC" run claude -- claude "$@"
```

`< /dev/null` 给它一个立刻 EOF 的 stdin。三秒变零秒。

---

## 八、验证

一条命令搞定，我把整个检查链写成 `ohc-verify` 了：

```
$ /data/ohc/bin/ohc-verify

[1/5] 检查配置文件
  OK  /data/ohc/containers/claude/env (600)
  OK  ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
  OK  ANTHROPIC_MODEL=deepseek-flash
  OK  key 已配置 (sk-****)

[2/5] 检查容器依赖
  OK  node v22.23.4
  OK  claude 2.1.316
  OK  rg 14.1.1

[3/5] 裸测 DeepSeek 端点
  OK  HTTP 200, model=deepseek-flash

[4/5] claude 单次调用
  OK  返回正常

[5/5] 交互式 TUI
  OK  可以启动（需要真终端）
```

真跑一次：

```sh
$ cd /
$ claude -p "用一句话说明你在哪"
我的模型名为 deepseek-flash，运行在 Linux（5.10.79，bash shell）环境下，工作目录为 /work。
```

注意 `工作目录为 /work`。这不是随便说的，是它真的 `pwd` 出来的。

---

## 九、花多少钱

这是很多人真正关心的。

我用的是 DeepSeek 官方定价，输入约 ¥0.5/百万 token，输出约 ¥2/百万 token（缓存命中更低）。一次典型的编程对话，上下文 2 万 token、输出 1 千 token，成本大概**一分钱**。

对比一下：同样一段对话走 Anthropic 官方，Sonnet 是 $3/$15 每百万 token，折人民币大概 3 毛到 1 块。

**差 30 到 100 倍。**

手机上跑不跑得动？跑得动。claude 只是个客户端，所有推理在 DeepSeek 的服务器上。这台 Cortex-A55 干的活就是拼 HTTP 请求、解析 JSON、渲染终端界面。CPU 占用不到 10%。

---

## 十、坑的清单

抄一遍，配的时候对照：

| 现象 | 原因 | 修法 |
|---|---|---|
| `Not logged in` | 变量没 export | `set -a` 后再 source |
| 启动崩 / `Exec format error` | 内置 ripgrep 是 glibc | `USE_BUILTIN_RIPGREP=0` + `apk add ripgrep` |
| 每次问"是否信任目录" | `HOME=/` | `export HOME=/root` |
| 调 haiku 报 404 | 没设快模型 | `ANTHROPIC_SMALL_FAST_MODEL` 设成同一个 |
| `-p` 卡三秒 | 等 stdin | `< /dev/null` |
| 上下文窗口警告 | 模型名不认识 | 那两个 `CLAUDE_CODE_*` 变量 |
| 请求超时 | 默认超时太短 | `API_TIMEOUT_MS=600000` |
| 出不了网 | 没默认路由 | `ohc net` |

八个坑，我踩了七个半。

---

## 下一篇

claude 这条路是**花自己的钱**。虽然便宜，但还是要钱。

下一篇讲另一条路：`opencode` 接 OpenCode Zen 的**免费** DeepSeek V4.1 Flash。不用绑卡，不花钱，同一个容器里再装一个。

顺便讲一个反直觉的发现：**免费模型用裸 curl 打会返回 429，但用 opencode 客户端打就正常。** 这不是额度问题，是设计如此。

---

**代码**

```
github.com/qhc0609/oh-container
```

`etc/claude.env` 是配置模板，`bin/ohc-setkey` 是换 key 的脚本，`bin/ohc-verify` 是上面那个自检。
