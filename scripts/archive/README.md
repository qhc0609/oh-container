# 实验脚本存档

这里放的是搭建过程中**真实用过**的一次性探测脚本，原样保留，没有整理。

价值不在"能直接跑"，而在**它们记录了当时是怎么问出答案的**。

| 前缀 / 名字 | 用来干什么 |
|---|---|
| `probe.sh` `arch.sh` `pathprobe.sh` `writable.sh` `lsroot.sh` | 摸清设备：架构、PATH、哪些目录可写、根目录长什么样 |
| `nstest.sh` `ns2.sh` | 探测 namespace 支持，就是在这里发现 `unshare -p` 返回 EINVAL |
| `net.sh` `route.sh` `oc-net.sh` | 抓默认路由缺失的问题 |
| `envcheck.sh` `checkcfg.sh` `catcfg.sh` `findcfg.sh` `findenv.sh` | 排查 claude 读不到环境变量 |
| `home.sh` `migrate-home.sh` `fix-trust.sh` | 处理 `HOME=/` 污染和信任目录 |
| `pty*.py` | 用 pty 假装真终端，验证 claude / opencode 的 TUI 能起来 |
| `oc-*.sh` | opencode 认证、免费模型、429 报错的排查过程 |
| `trim-oc.sh` `trim-final.sh` `clean-cache.sh` `cleanup*.sh` | 瘦身：删 glibc 二进制、清 npm 缓存 |
| `verifytar.sh` `backup-probe.sh` `do-backup.sh` | 备份打包与校验 |
| `strings.sh` | 从 297MB 的 claude 二进制里 grep 出隐藏环境变量 |

**别拿这些当正式脚本用。** 正式的运行时在 `bin/`，部署用根目录的 `deploy.ps1`，
备份恢复用 `backup/` 下的两个 `.ps1`。

这些脚本里有几处写死了当时设备上的绝对路径（`/data/local/tmp`、`/data/ohc` 等），
换设备需要改。
