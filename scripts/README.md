# scripts/

搭建与维护用的脚本。

| 文件 | 用途 | 什么时候用 |
|---|---|---|
| `check-namespace.sh` | 探测设备的 namespace 能力、内核版本、挂载点、SELinux 状态 | **换设备第一步**。先跑它看能不能做容器，再决定要不要往下走 |
| `test-deepseek.sh` | 直接打 DeepSeek 的 Anthropic 兼容端点，验 key 和网络通不通 | key 换了、或者怀疑"是不是网络问题"时 |
| `push-via-api.sh` | github.com 的 git 端点被封时，改走 GitHub REST Git Data API 推送 | `git push` 报 `CONNECT tunnel failed, response 502` 或直连 `Connection was reset` 时 |
| `archive/` | 搭建过程中的 50+ 个一次性探测脚本，原样留档 | 一般不用；想知道某个坑当初是怎么探出来的，去这里翻 |

## push-via-api.sh 用法

```sh
git add -A
bash scripts/push-via-api.sh "提交信息"
```

它做的事：

1. 读远端 head 的 commit / tree 作为基线
2. 对每个改动文件，用 index 里的内容建 blob
3. 以远端 tree 为 base 建新 tree
4. 建 commit，PATCH ref 指向它
5. 用与 GitHub 相同的 author/committer 元数据在本地重建同一个 commit 对象，
   sha 一致就 `update-ref` + `reset --hard`，保证本地和远端是同一条历史

两个实测坑（脚本里已经处理掉了）：

- **GitHub 存 commit 时会把时区归到它自己的账号时区**（本机实测一次是 `+0800`、一次是 `+0000`），
  跟提交时传的 ISO 字符串里写的时区无关。所以脚本最后会试探一组常见偏移，逐个算 sha 对比。
- **远端建的 tree 对象本地不存在**，直接 `git reset --hard` 会报
  `fatal: unable to read tree (...)`。要先 `git write-tree` 用 index 物化出同 sha 的 tree。

依赖：`gh`（已 `gh auth login`）、`python` 或 `python3`。
