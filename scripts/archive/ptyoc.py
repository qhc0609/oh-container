import os, pty, select, time, signal, re

CMD = "cd / && opencode"
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/sh", ["/bin/sh", "-c", CMD])
os.set_blocking(fd, False)

buf = b""
t0 = time.time()
asked = False
t_ask = 0

def send(s):
    try:
        os.write(fd, s.encode() if isinstance(s, str) else s)
    except Exception:
        pass

while time.time() - t0 < 120:
    r, _, _ = select.select([fd], [], [], 0.3)
    if r:
        try:
            d = os.read(fd, 8192)
        except (OSError, BlockingIOError):
            d = b""
        if d:
            buf += d
    else:
        # TUI 起来后（静默 12 秒）发一个问题
        if not asked and time.time() - t0 > 12:
            send("Reply with exactly: OC_TUI_OK\r")
            asked = True
            t_ask = time.time()
        if asked and time.time() - t_ask > 50:
            break

send("\x03"); time.sleep(0.5)
send("\x03"); time.sleep(0.5)
try:
    send("/exit\r"); time.sleep(1)
except Exception:
    pass
try:
    os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
except Exception:
    pass

text = buf.decode("utf-8", "replace")
clean = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b[\(\)][A-Z0-9]|\x1b[=>]", "", text)
clean = re.sub(r"[ \t]{3,}", " ", clean)
clean = re.sub(r"\n{3,}", "\n\n", clean)
print("===== 输出（末尾 2200 字符）=====")
print(clean[-2200:])
print("===== 字节:", len(text), "耗时: %.0fs =====" % (time.time() - t0))
