# 备份与一键恢复

手机刷机 / 清除数据会把 `/data` 清空，这套容器 + claude 环境就没了。
这个目录存放**整包备份**和**一键恢复脚本**，恢复时**不需要联网安装任何东西**。

---

## 目录内容

| 文件 | 说明 |
|---|---|
| `ohc-backup.tar.gz` | 整包备份（容器运行时 + Alpine rootfs + Node + claude + opencode + 全部依赖 + 配置 + 认证） |
| `SHA256SUMS.txt` | 备份包校验值，恢复前会自动核对 |
| `restore.ps1` | **一键恢复**（刷机后用这个） |
| `backup.ps1` | 重新打包备份（环境有改动后用这个） |

---

## 刷机后怎么恢复

USB 连好手机，确认 `hdc list targets` 能看到设备，然后在 **PowerShell** 里执行：

```powershell
cd "C:\Users\Administrator\WorkBuddy AI\2026-11-02-16-21-06\oh-container\backup"
powershell -ExecutionPolicy Bypass -File .\restore.ps1
```

脚本会自动完成：

1. 定位 `hdc.exe`、检查设备连接
2. 核对备份包 SHA256
3. 确认 `/data` 是否干净（已存在则要求加 `-Force`）
4. 推送备份包到设备
5. 在设备上解压（约 550MB，1~3 分钟）
6. 修复执行权限
7. 清理设备上的临时包
8. 验证 `claude` 在 PATH 中、能打印版本
9. 真实调用一次 DeepSeek 验证（不想花 token 加 `-NoTest`）

完成后：

```powershell
hdc shell
```
```sh
claude       # DeepSeek V4.1-Flash（用你自己的 DeepSeek Key）
opencode     # OpenCode Zen 免费 DeepSeek V4.1-Flash Free
```

两个都能直接用。

---

## 备份里到底装了什么

```
/data/ohc/
├── bin/ohc, ohc-claude, ohc-setkey, ohc-verify, oc-setkey   容器运行时与工具
├── rootfs/claude/          Alpine 3.21.3
│   ├── Node 22.23.4 + claude 2.1.316 + opencode 1.19.5 + ripgrep
│   ├── root/.config/opencode/opencode.json      默认模型（免费 DeepSeek）
│   └── root/.local/share/opencode/auth.json     OpenCode Key（600 权限）
├── containers/claude/env   DeepSeek API Key、模型名、上下文窗口等配置
└── workspace/              claude / opencode 的工作目录（容器内 /work）

/data/python/lib/python3.8/script/bin/claude      PATH 里的 claude 入口
/data/python/lib/python3.8/script/bin/opencode    PATH 里的 opencode 入口
```

关键点：**Node 运行时、claude、opencode 的全部依赖都在包里**，恢复过程完全不联网，
所以哪怕刷机后手机还没连上 WiFi，也能先把环境还原。

**OpenCode 的登录状态也在包里**（`auth.json`），恢复后不需要重新登录。

---

## 环境有改动后，怎么更新备份

比如换了 API Key、升级了 claude、装了新工具：

```powershell
powershell -ExecutionPolicy Bypass -File .\backup.ps1
```

会自动重新打包、拉回 PC、重算 SHA256，并清理设备上的临时文件。

---

## 注意事项

**1. 备份包里是明文 API Key**

`containers/claude/env` 里有你的 DeepSeek Key，整个包是明文 tar.gz。
不要把这个文件传到网盘、Git 仓库或发给别人。想加密可以自己套一层，例如：

```powershell
# 加密（恢复时先用同一密码解开再跑 restore.ps1）
openssl enc -aes-256-cbc -pbkdf2 -in ohc-backup.tar.gz -out ohc-backup.tar.gz.enc
```

**2. 刷机后 hdc 需要重新授权**

第一次 `hdc list targets` 可能显示 `Unauthorized`，在手机上点"允许调试"即可。

**3. 换了不同 ROM 时注意 PATH**

`claude` 能直接敲，依赖的是设备默认 PATH 里有
`/data/python/lib/python3.8/script/bin` 这个可写目录。
如果刷的是不同厂商/版本的 ROM，这个 PATH 可能不一样——`restore.ps1` 最后会检查并提示。
真找不到时临时用 `/data/ohc/bin/ohc-claude`，或者把入口脚本放到新 PATH 里的任意可写目录。

**4. 恢复后如果 claude 报网络不可达**

容器内出网依赖设备的默认路由，OpenHarmony 的 `wlan0` 有时只有链路路由。
执行一次：

```sh
/data/ohc/bin/ohc net
```

会检测并补上默认路由（`ohc run` 也会自动做这件事）。

---

## 手动恢复（脚本出问题时的兜底）

```powershell
$hdc = "C:\Tools\HarmonyOS\toolchains\hdc.exe"
$pkg = "C:\Users\Administrator\WorkBuddy AI\2026-11-02-16-21-06\oh-container\backup\ohc-backup.tar.gz"

& $hdc list targets
& $hdc file send $pkg /data/local/tmp/ohc-backup.tar.gz
& $hdc shell "cd /data && tar -xzf /data/local/tmp/ohc-backup.tar.gz"
& $hdc shell "chmod 755 /data/ohc/bin/* /data/python/lib/python3.8/script/bin/claude"
& $hdc shell "cd / && claude --version"
```
