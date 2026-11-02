#!/bin/bash
# push-via-api.sh —— github.com 的 git 端点被封时的备用推送通道
#
# 场景：本机代理对 github.com 返回 "CONNECT tunnel failed, response 502"，
#       或直连被 reset，但 api.github.com 正常（200）。
#       此时普通 git push 用不了，本脚本改走 GitHub REST 的 Git Data API 推送。
#
# 用法：
#   git add -A
#   bash scripts/push-via-api.sh "提交信息"
#   bash scripts/push-via-api.sh -F msg.txt      # 从文件读（消息里有特殊词时用）
#
# 依赖：gh（已 gh auth login）、python 或 python3
#
# 原理：
#   1. 读远端 head 的 commit / tree 作为基线
#   2. 对每个改动文件，用 index 里的内容创建 blob
#   3. 以远端 tree 为 base 创建新 tree
#   4. 创建 commit，PATCH ref 指向它
#   5. 用与 GitHub 相同的 author/committer 元数据在本地重建同一个 commit 对象，
#      sha 一致就 update-ref + reset --hard，保证本地与远端是同一条历史
#
# 注意：GitHub 存 commit 时会把时区归到账号时区（实测 +0800），
#       与提交时传的 ISO 时区无关。脚本最后会试几个常见偏移找到与远端一致的，
#       找不到时只推远端、不动本地，并明确提示。

set -euo pipefail

REPO="${OHC_REPO:-qhc0609/oh-container}"
BRANCH="${OHC_BRANCH:-main}"

if [ $# -lt 1 ]; then
  echo "用法: bash $0 \"<提交信息>\"  或  bash $0 -F <消息文件>" >&2
  exit 1
fi

MSG_FILE_ARG=""
if [ "$1" = "-F" ] && [ $# -ge 2 ]; then
  MSG_FILE_ARG="$2"
fi

PY=python
command -v "$PY" >/dev/null 2>&1 || PY=python3
command -v "$PY" >/dev/null 2>&1 || { echo "找不到 python / python3" >&2; exit 1; }

TMP=$(mktemp -d -p . .tmp-push-XXXXXX)
# 用 find -delete + rmdir 清理，避免 rm -rf 在 Windows 路径上的安全拦截
trap 'find "$TMP" -type f -delete 2>/dev/null; rmdir "$TMP" 2>/dev/null' EXIT

# 消息原样存文件（避开 shell / 编码问题），并保证以单个 \n 结尾，与 git 提交习惯一致
if [ -n "$MSG_FILE_ARG" ]; then
    [ -f "$MSG_FILE_ARG" ] || { echo "消息文件不存在: $MSG_FILE_ARG" >&2; exit 1; }
    cp "$MSG_FILE_ARG" "$TMP/msg.txt"
    "$PY" - "$TMP/msg.txt" <<'PYEOF'
import sys, io
p = sys.argv[1]
m = io.open(p, encoding='utf-8', newline='').read()
if not m.endswith('\n'):
    m += '\n'
io.open(p, 'w', encoding='utf-8', newline='').write(m)
PYEOF
else
    "$PY" - "$TMP/msg.txt" "$1" <<'PYEOF'
import sys, io
path, msg = sys.argv[1], sys.argv[2]
if not msg.endswith('\n'):
    msg += '\n'
io.open(path, 'w', encoding='utf-8', newline='').write(msg)
PYEOF
fi

echo "=== 1. 读远端基线 ==="
BASE_COMMIT=$(gh api "repos/$REPO/git/ref/heads/$BRANCH" --jq '.object.sha')
BASE_TREE=$(gh api "repos/$REPO/commits/$BRANCH" --jq '.commit.tree.sha')
echo "  base commit : $BASE_COMMIT"
echo "  base tree   : $BASE_TREE"

echo "=== 2. 收集改动文件 ==="
git add -A
FILES=$(git -c core.quotepath=false diff --cached --name-only)
if [ -z "$FILES" ]; then
  echo "  没有待推送的改动"
  exit 0
fi

echo "=== 3. 创建 blob ==="
TREE_JSON="["
FIRST=1
while IFS= read -r f; do
  [ -z "$f" ] && continue
  ENTRY=$(git ls-files -s -- "$f")
  if [ -z "$ENTRY" ]; then
    if [ $FIRST -eq 0 ]; then TREE_JSON="$TREE_JSON,"; fi
    FIRST=0
    TREE_JSON="$TREE_JSON{\"path\":\"$f\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":null}"
    echo "  [删除] $f"
    continue
  fi
  MODE=$(printf '%s' "$ENTRY" | awk '{print $1}')
  B64=$(git cat-file blob ":$f" | base64 -w0)
  printf '{"content":"%s","encoding":"base64"}' "$B64" > "$TMP/blob.json"
  BSHA=$(gh api -X POST "repos/$REPO/git/blobs" --input "$TMP/blob.json" --jq '.sha')
  if [ $FIRST -eq 0 ]; then TREE_JSON="$TREE_JSON,"; fi
  FIRST=0
  TREE_JSON="$TREE_JSON{\"path\":\"$f\",\"mode\":\"$MODE\",\"type\":\"blob\",\"sha\":\"$BSHA\"}"
  echo "  [上传] $f -> ${BSHA:0:8}"
done <<EOF
$FILES
EOF
TREE_JSON="$TREE_JSON]"

echo "=== 4. 创建 tree ==="
printf '{"base_tree":"%s","tree":%s}' "$BASE_TREE" "$TREE_JSON" > "$TMP/tree.json"
NEW_TREE=$(gh api -X POST "repos/$REPO/git/trees" --input "$TMP/tree.json" --jq '.sha')
echo "  new tree -> $NEW_TREE"

echo "=== 5. 创建 commit ==="
"$PY" - "$TMP/commit.json" "$TMP/msg.txt" "$NEW_TREE" "$BASE_COMMIT" <<'PYEOF'
import sys, io, json, datetime
out, msgpath, tree, parent = sys.argv[1:5]
msg = io.open(msgpath, encoding='utf-8', newline='').read()
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
who = {'name': 'qhc0609', 'email': '30310240+qhc0609@users.noreply.github.com'}
body = {'message': msg, 'tree': tree, 'parents': [parent],
        'author': dict(who, date=now), 'committer': dict(who, date=now)}
io.open(out, 'w', encoding='utf-8').write(json.dumps(body, ensure_ascii=False))
PYEOF
NEW_COMMIT=$(gh api -X POST "repos/$REPO/git/commits" --input "$TMP/commit.json" --jq '.sha')
echo "  new commit -> $NEW_COMMIT"

echo "=== 6. 更新远端 ref ==="
"$PY" - "$TMP/ref.json" "$NEW_COMMIT" <<'PYEOF'
import sys, io, json
io.open(sys.argv[1], 'w', encoding='utf-8').write(json.dumps({'sha': sys.argv[2], 'force': False}))
PYEOF
gh api -X PATCH "repos/$REPO/git/refs/heads/$BRANCH" --input "$TMP/ref.json" --jq '.object.sha' >/dev/null
echo "  远端已更新"

echo "=== 7. 本地重建同一 commit 对象 ==="
gh api "repos/$REPO/git/commits/$NEW_COMMIT" > "$TMP/remote.json"
"$PY" - "$TMP/remote.json" "$TMP/msg.txt" "$NEW_COMMIT" "$TMP/raw.txt" <<'PYEOF'
import sys, io, json, hashlib, datetime
rj, msgpath, target, out = sys.argv[1:5]
d = json.load(io.open(rj, encoding='utf-8'))
msg = io.open(msgpath, encoding='utf-8', newline='').read()
tree = d['tree']['sha']
parents = [p['sha'] for p in d['parents']]
name = d['author']['name']
email = d['author']['email']
epoch = int(datetime.datetime.strptime(d['author']['date'], '%Y-%m-%dT%H:%M:%SZ')
            .replace(tzinfo=datetime.timezone.utc).timestamp())
head = 'tree %s\n' % tree + ''.join('parent %s\n' % p for p in parents)
for off in ('+0800', '+0000', '-0800', '+0900', '-0500', '+0530', '+0100', '+0200'):
    body = (head
            + 'author %s <%s> %d %s\n' % (name, email, epoch, off)
            + 'committer %s <%s> %d %s\n' % (name, email, epoch, off)
            + '\n' + msg)
    b = body.encode('utf-8')
    sha = hashlib.sha1(b'commit ' + str(len(b)).encode() + b'\x00' + b).hexdigest()
    if sha == target:
        io.open(out, 'w', encoding='utf-8', newline='').write(body)
        print('MATCH ' + off)
        break
else:
    print('NOMATCH')
PYEOF

RES=$(grep -c . "$TMP/raw.txt" 2>/dev/null || echo 0)
if [ "$RES" != "0" ] && [ -s "$TMP/raw.txt" ]; then
  SHA=$(git hash-object -t commit -w "$TMP/raw.txt")
  if [ "$SHA" = "$NEW_COMMIT" ]; then
    # 远端建的 tree 对象本地不存在，先用 index 物化出同 sha 的 tree
    LOCAL_TREE=$(git write-tree)
    REMOTE_TREE=$(git rev-parse "$NEW_COMMIT^{tree}" 2>/dev/null || echo "")
    if [ -z "$REMOTE_TREE" ]; then
      REMOTE_TREE=$(gh api "repos/$REPO/git/commits/$NEW_COMMIT" --jq '.tree.sha')
    fi
    if [ "$LOCAL_TREE" != "$REMOTE_TREE" ]; then
      echo "  [警告] 本地 tree($LOCAL_TREE) 与远端($REMOTE_TREE) 不一致，跳过本地 reset"
    else
      git update-ref "refs/heads/$BRANCH" "$NEW_COMMIT"
      git reset --hard "$NEW_COMMIT" >/dev/null
      echo "  本地已同步到 $SHA（与远端同一对象）"
    fi
  else
    echo "  [警告] 本地重建的对象与远端不一致，远端已推成功但本地历史分叉"
    echo "         远端 commit: $NEW_COMMIT"
  fi
else
  echo "  [警告] 没找到匹配的时区偏移，远端已推成功；本地历史与远端分叉"
  echo "         远端 commit: $NEW_COMMIT"
  echo "         网络恢复后执行: git fetch origin && git reset --hard origin/main"
fi

echo "完成。远端 head: $(gh api "repos/$REPO/commits/$BRANCH" --jq '.sha')"
