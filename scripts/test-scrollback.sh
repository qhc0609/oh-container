#!/bin/sh
# 回归测试：为什么「装了 tmux 还是翻不动」
#
# 背景：claude 启动时会发 ESC[?1049h 切到备用屏幕。备用屏幕按设计没有回滚历史，
# tmux 尊重这个切换，于是 claude 的输出一行都进不了 history——history-limit
# 调到 5 万也是空的，屏幕上永远只剩最后一屏。
#
# 本脚本用同一段载荷（切备用屏幕 -> 喷 200 行 -> 切回）跑两遍：
#   1) tmux -f /dev/null   = 默认配置，alternate-screen on  -> 历史应为 0
#   2) 本机 /root/.tmux.conf = alternate-screen off          -> 历史应为 177
#      177 = 200 - 24 + 1，即除当前可见的 24 行外，其余全部进了历史
#
# 用法（PC 上）：
#   hdc shell "/data/ohc/bin/ohc run claude -- /bin/sh /work/test-scrollback.sh"
# 预期输出：
#   默认 tmux（alternate-screen on）      history_size=0    LINE_rows=24
#   本机 .tmux.conf（alternate-screen off） history_size=177  LINE_rows=200

set -u
export TMUX_TMPDIR=/work/.tmux
mkdir -p "$TMUX_TMPDIR" 2>/dev/null

PAY=/tmp/alt-payload.sh
cat > "$PAY" <<'EOF'
printf '\033[?1049h'
i=1
while [ "$i" -le 200 ]; do
    echo "LINE$i"
    i=$((i + 1))
done
sleep 4
printf '\033[?1049l'
EOF

run_case() {
    _label=$1
    _conf=$2
    tmux kill-server 2>/dev/null
    if [ -n "$_conf" ]; then
        _tm="tmux -f $_conf"
    else
        _tm="tmux"
    fi
    $_tm new-session -d -s probe "sh $PAY" 2>/dev/null
    sleep 2
    _h=$($_tm display-message -p -t probe '#{history_size}' 2>/dev/null)
    _l=$($_tm capture-pane -p -t probe -S -500 2>/dev/null | grep -c '^LINE')
    echo "$_label  history_size=${_h:-?}  LINE_rows=${_l:-?}"
    tmux kill-server 2>/dev/null
}

echo "tmux $(tmux -V 2>/dev/null | sed 's/^tmux //')   socket=$TMUX_TMPDIR"
echo "配置里的值：$(grep 'alternate-screen' /root/.tmux.conf 2>/dev/null | tr -d '\r')"
run_case "默认 tmux（alternate-screen on）        " /dev/null
run_case "本机 .tmux.conf（alternate-screen off）" ""
