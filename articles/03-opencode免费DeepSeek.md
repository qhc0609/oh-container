# 03｜白嫖 DeepSeek V4.1 Flash：在手机上装 opencode 的免费模式

> 系列第三篇。同一个容器，再装一个 AI 客户端，这次不花钱。
> 代码：`qhc0609/oh-container`

---

先说结论，省得你看完才发现不适用：

**opencode 里的 DeepSeek V4.1 Flash 免费，是真的免费。不用绑卡，不用充值，不扣钱。**

**但它不是"随便用都免费"。**

你需要一个 OpenCode 账号的 API Key，形如 `oc_sk_...`。这个 key 不是 DeepSeek 的，是 OpenCode 的。免费额度是 OpenCode 的网关在兜，它在前面替你付钱，你在后面白用。

想清楚这个前提，剩下的都好办。

---

## 一、为什么值得装第二个

上一篇配好的 `claude` 已经能用了，为什么还要 `opencode`？

三个理由。

**第一，免费。** claude 那条路走的是你自己的 DeepSeek key，虽然便宜（一次对话一分钱），但还是要钱。opencode 的免费档一分不花。

**第二，不冲突。** 两个装在同一个容器里，共用同一个 Node，共用同一个工作目录 `/work`。想省钱就敲 `opencode`，想用 claude 的完整工具链就敲 `claude`。

**第三，互为备份。** 哪天 DeepSeek 官方接口抽风，或者你的 key 额度用完了，`opencode` 还能顶上。反过来也一样。

---

## 二、装

进容器：

```sh
/data/ohc/bin/ohc shell claude
```

一条命令：

```sh
npm install -g opencode-ai
```

等两三分钟。装完确认：

```sh
$ opencode --version
1.19.5
```

---

## 三、先去拿一个 key

浏览器打开：

```
https://opencode.ai/console
```

注册（邮箱就行，不用信用卡），然后生成 API Key。

生成的 key 长这样：

```
oc_sk_xxxxxxxxxxxx__yyyyyyyyyyyyyyyyyyyyyyyyyyyy
```

（`oc_sk_` 前缀 + 一段随机串，中间两个下划线。别照抄，这是格式示意。）

**这个 key 跟 DeepSeek 的 `sk-...` 完全不是一个东西。** 别混。

---

## 四、认证：别用交互式登录

opencode 官方让你跑 `opencode auth login`，然后选 provider、粘 key。在手机上，这个交互式流程会因为 TUI 和终端尺寸的问题卡住。

直接写文件，一步到位。

opencode 的认证信息存在这里：

```
/root/.local/share/opencode/auth.json
```

容器内路径。内容：

```json
{"opencode":{"type":"api","key":"oc_sk_你的key"}}
```

一条命令写进去（在宿主上执行，不用进容器）：

```sh
F=/data/ohc/rootfs/claude/root/.local/share/opencode/auth.json
mkdir -p "$(dirname "$F")"
printf '{"opencode":{"type":"api","key":"%s"}}\n' "oc_sk_你的key" > "$F"
chmod 600 "$F"
```

验证：

```sh
$ /data/ohc/bin/ohc run claude -- opencode auth list
opencode
● 1 credential
```

看到 `1 credential` 就成了。

---

## 五、模型名：这里有个大坑

网上教程（包括一些 AI 自己写的）会告诉你模型叫：

```
opencode/deepseek-v4-flash-free      ← 错的
```

不对。

正确的名字是：

```
opencode/deepseek-v4.1-flash-free
```

区别在 `v4` 和 `v4.1` 之间那个点。

写错的后果是：

```
Error: Model not found: opencode/deepseek-v4-flash-free
```

或者更气人的——它不报错，直接静默回落到一个付费模型，然后你发现账单上有钱。

**怎么确认自己没写错？**

```sh
$ /data/ohc/bin/ohc run claude -- opencode models | grep -i deepseek
opencode/deepseek-v4.1-flash
opencode/deepseek-v4.1-flash-free
opencode/deepseek-v4-pro
```

`opencode models` 会列出所有可用模型。带 `-free` 后缀的才是免费的。

---

## 六、配置文件

在容器里设成默认，省得每次都指定：

`/root/.config/opencode/opencode.json`

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode/deepseek-v4.1-flash-free"
}
```

写到宿主上对应位置：

```sh
D=/data/ohc/rootfs/claude/root/.config/opencode
mkdir -p "$D"
cat > "$D/opencode.json" <<'EOF'
{ "$schema": "https://opencode.ai/config.json", "model": "opencode/deepseek-v4.1-flash-free" }
EOF
```

这两个文件（`opencode.json` 和 `auth.json`）都在 rootfs 里，**会被打进备份**。刷机恢复后不用重新登录——这一点在第四篇里很关键。

---

## 七、`opencode run` 会卡死

配好之后先试单次调用：

```sh
$ /data/ohc/bin/ohc run claude -- opencode run "你好"
（输出 init...）
（卡住，不动了）
```

不是死了，是**在等 stdin**。

`opencode run` 是非交互模式，但它还是读 stdin。通过 `hdc shell` 执行时，stdin 是个没有 EOF 的管道，它就永远等下去。

这个坑比 claude 那个更狠——claude 是等三秒超时，opencode 是**真的永远等**。我第一次遇到时以为程序挂了，杀了重跑三次，每次都在同一个地方停。

修法一样，`< /dev/null`：

```sh
/data/ohc/bin/ohc run claude -- opencode run "你好" < /dev/null
```

在 PATH 入口脚本里做掉这件事，`device-bin/opencode`：

```sh
#!/bin/sh
export OHC_QUIET=1
if [ "$1" = "run" ]; then
    exec /data/ohc/bin/ohc run claude -- opencode "$@" < /dev/null
fi
exec /data/ohc/bin/ohc run claude -- opencode "$@"
```

只有 `run` 子命令加 `< /dev/null`。交互式 TUI 不能加，加了终端就没了。

---

## 八、裸 curl 打免费模型，会 429

这是最有意思的一个发现。

我一开始想验证"免费模型是不是真免费"，就用 curl 直接打 OpenCode 的接口：

```sh
curl -s https://opencode.ai/zen/v1/messages \
  -H "x-api-key: oc_sk_..." \
  -d '{"model":"opencode/deepseek-v4.1-flash-free", ...}'
```

返回：

```json
{"type":"error","error":{"type":"FreeUsageLimitError","message":"..."}}
```

HTTP 429。

第一反应：额度用完了？可我一次都没调过。

换个付费模型，同样的 curl，200。

**所以不是额度问题。**

原因在 OpenCode 的设计：**免费模型只能通过 opencode 官方客户端调用。**

它要校验请求的 User-Agent、会话指纹、客户端版本，确认你是真的在用它的客户端。裸 curl 打过去，它认不出你，直接拒。

换句话说，免费额度是给"真实用户"的，不是给脚本刷的。

这个设计挺聪明。对我们来说就一条结论：

> **别想着绕过 opencode 客户端直接调免费模型。用 opencode 就好。**

顺便，这也解释了为什么网上那些"用 OpenAI SDK 白嫖 opencode 免费模型"的教程全是假的。

---

## 九、202MB 的垃圾

装完发现 rootfs 大了 400MB。查一下：

```sh
$ du -sh /usr/local/lib/node_modules/opencode-ai/node_modules/* | sort -h | tail -5
208M  opencode-linux-arm64-musl
202M  opencode-linux-arm64
58M   ...
```

**两份原生二进制。**

一份 musl（Alpine 用的），一份 glibc（Debian/Ubuntu 用的）。npm 不管你在哪个系统上装，两份都给你。

Alpine 是 musl，glibc 那份永远跑不起来，纯占地方。

删之前先确认剩下的能跑：

```sh
$ opencode --version
1.19.5          # 有输出，说明 musl 那份正常

$ rm -rf /usr/local/lib/node_modules/opencode-ai/node_modules/opencode-linux-arm64

$ opencode --version
1.19.5          # 还是正常，确认删对了
```

省 202MB。

顺手清 npm 缓存，那玩意儿会涨到 484MB：

```sh
npm cache clean --force
rm -rf /root/.npm
```

两刀下去，rootfs 从 1.0G 掉到 839M。

---

## 十、现在在根目录敲 `opencode` 就能用

跟 claude 一模一样的套路。设备 PATH 里那个可写目录：

```sh
cat > /data/python/lib/python3.8/script/bin/opencode <<'EOF'
#!/bin/sh
export OHC_QUIET=1
if [ "$1" = "run" ]; then
    exec /data/ohc/bin/ohc run claude -- opencode "$@" < /dev/null
fi
exec /data/ohc/bin/ohc run claude -- opencode "$@"
EOF
chmod 755 /data/python/lib/python3.8/script/bin/opencode
```

然后：

```powershell
hdc shell
```
```sh
$ cd /
$ opencode
```

TUI 起来。

```
$ opencode run "用一句话说明你在哪"
我在 OpenCode Zen 网关上运行 deepseek-v4.1-flash-free，工作目录 /work。
```

---

## 十一、免费档的边界

说清楚，别到时候骂我。

**速率限制。** 免费档有 RPM 限制，密集使用会排队或者 429。正常聊天写代码够用，拿它跑批量任务会撞墙。

**不是无限。** OpenCode 随时可能调整免费策略。这套配置的价值在于：**接口变了，你只要改一行 `opencode.json` 里的模型名**，别的东西都不用动。

**数据政策。** 官方模型页给 `DeepSeek V4.1 Flash Free` 标的是 **zero-retention provider**，意思是不留存你的请求内容。这是免费档里少见的待遇，但别拿它传公司代码。

**重度使用怎么办？** 两条路：转 OpenCode Go 订阅，或者换回 `claude` 走自己的 DeepSeek key。我自己的用法是：日常问答用 opencode（免费），需要跑长任务、要它读大量文件的时候用 claude（花自己的钱，但可控）。

---

## 十二、两个客户端对比

| | `claude` | `opencode` |
|---|---|---|
| 后端 | DeepSeek 官方 `/anthropic` | OpenCode Zen 网关 |
| 模型 | `deepseek-flash` | `opencode/deepseek-v4.1-flash-free` |
| 花钱 | 自己的 DeepSeek key，约 ¥0.5/百万 token 输入 | 免费 |
| 要什么 | DeepSeek API Key (`sk-`) | OpenCode 账号 Key (`oc_sk_`) |
| 工具链 | 完整（读文件、改文件、跑命令、子 agent） | 完整 |
| 速率 | 按你的余额 | 有免费档限流 |
| 稳定性 | 官方接口 | 网关，偶尔抖动 |
| 装在哪 | rootfs | 同一个 rootfs |
| 认证文件 | `containers/claude/env` | `root/.local/share/opencode/auth.json` |

两个都装，加起来占 839MB。手机存储够的话，没有理由只装一个。

---

## 十三个坑的清单

| 现象 | 原因 | 修法 |
|---|---|---|
| `Model not found` | 模型名写成 `v4-flash-free` | 是 `v4.1-flash-free` |
| `run` 卡住不动 | 等 stdin | `< /dev/null` |
| 裸 curl 429 | 免费模型只认官方客户端 | 用 `opencode`，别绕 |
| rootfs 暴涨 400MB | 装了 glibc + musl 两份 | 删 `opencode-linux-arm64` |
| `auth list` 是空的 | auth.json 位置或格式错 | `root/.local/share/opencode/auth.json` |
| 交互式 TUI 起不来 | 不是真终端 | 必须 `hdc shell` 交互进来 |

---

## 下一篇

到这儿，两个 AI 都能在手机上跑了。

但有个问题一直悬着：**这一切都在 `/data` 里。刷机、恢复出厂设置、清除数据，全没。**

我实测过——`rm -rf /data/ohc` 之后，839MB 的环境、两个 AI、所有配置和登录状态，全归零。

下一篇讲怎么把它救回来：834MB 整包备份，**56 秒一条命令还原，全程不联网**。

包括两个反直觉的坑：`tar` 不能打包 socket 文件；PowerShell 5.1 读没有 BOM 的 UTF-8 会当 ANSI 处理，中文字符串全变问号。

---

**代码**

```
github.com/qhc0609/oh-container
```

`etc/opencode.json` 是配置模板，`bin/oc-setkey` 是换 key 的脚本。
