#!/bin/sh
# 回归测试：claude 的输出到底有没有流进终端回滚区
#
# 背景（走了三次弯路才对）：
#   1) 调大宿主控制台缓冲区 -> 没用
#   2) 容器里装 tmux 存历史 -> tmux 的 history 实测是 0，一样翻不动
#   3) 真凶：claude 2.x 默认用 fullscreen renderer，自己维护虚拟滚动视口，
#      120 行输出只把最后十几行画到屏幕上，一行都不交给终端。
#
# 解法：env 里 CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1，强制 classic renderer，
# 输出变成顺序追加，行才会真正流进 pty -> hdc -> 宿主控制台缓冲区。
#
# 本脚本在 tmux 里跑一次真 claude 并量化结果（tmux 只是测量工具：
# tmux 的 history_size 涨了，就等价于「这些行确实交给了终端」）。
#
# 用法（PC 上，会消耗一次 API 调用）：
#   hdc shell "/data/ohc/bin/ohc run claude -- /bin/sh /work/test-claude-render.sh"
#
# 预期：
#   alt=0             备用屏幕没被打开（classic renderer）
#   hist=100+         历史明显增长
#   digit_rows=120    120 行「1」全部在历史里
# 如果 hist=0 且 digit_rows=0，说明 env 里的
# CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1 没生效。

set -u
export TMUX_TMPDIR=/work/.tmux
mkdir -p "$TMUX_TMPDIR" 2>/dev/null
tmux kill-server 2>/dev/null
sleep 1

tmux new-session -d -s c -x 100 -y 30 "claude"
sleep 14
echo "--- 启动后 ---"
tmux display -p -t c 'alt=#{alternate_on} hist=#{history_size} h=#{pane_height} w=#{pane_width}'

tmux send-keys -t c '请只输出120行，每行一个数字1，不要任何其它文字'
sleep 1
tmux send-keys -t c Enter
sleep 30

echo "--- 输出完之后 ---"
tmux display -p -t c 'alt=#{alternate_on} hist=#{history_size}'
echo "--- 历史里「1」的行数 ---"
tmux capture-pane -p -t c -S -1000 2>/dev/null | grep -cE '^[[:space:]]*1[[:space:]]*$'

tmux kill-server 2>/dev/null
