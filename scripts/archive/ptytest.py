import os, pty, select, time, signal, sys, re

CMD = "/data/ohc/bin/ohc run claude -- claude"

pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/sh", ["/bin/sh", "-c", CMD])

out = b""
t0 = time.time()
deadline = 60
while time.time() - t0 < deadline:
    r, _, _ = select.select([fd], [], [], 0.5)
    if r:
        try:
            d = os.read(fd, 4096)
        except OSError:
            break
        if not d:
            break
        out += d
    # 真正的 TUI 标志：出现 Welcome / tips / 输入框提示
    if b"Welcome" in out or b"? for shortcuts" in out or b"Claude Code v" in out:
        time.sleep(1)
        break

try:
    os.kill(pid, signal.SIGKILL)
except Exception:
    pass
try:
    os.waitpid(pid, 0)
except Exception:
    pass

text = out.decode("utf-8", "replace")
clean = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b[\(\)][A-Z0-9]|\x1b[=>]", "", text)
clean = re.sub(r"[ \t]{3,}", " ", clean)
clean = re.sub(r"\n{3,}", "\n\n", clean)
print("===== pty 输出 =====")
print(clean[:2500])
print("===== 原始字节数:", len(text), " 耗时: %.1fs" % (time.time() - t0), "=====")
