import os, pty, select, time, signal, re

CMD = "cd / && claude"
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

while time.time() - t0 < 80:
    r, _, _ = select.select([fd], [], [], 0.3)
    if r:
        try:
            d = os.read(fd, 8192)
        except (OSError, BlockingIOError):
            d = b""
        if d:
            buf += d
    else:
        if not asked and time.time() - t0 > 10:
            send("只回答两个字：可用\r")
            asked = True
            t_ask = time.time()
        if asked and time.time() - t_ask > 35:
            break

send("\x03"); time.sleep(0.8); send("/exit\r"); time.sleep(1.5)
try:
    os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
except Exception:
    pass

text = buf.decode("utf-8", "replace")
clean = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b[\(\)][A-Z0-9]|\x1b[=>]", "", text)
clean = re.sub(r"[ \t]{3,}", " ", clean)
clean = re.sub(r"\n{3,}", "\n\n", clean)
print("===== 输出 =====")
print(clean[-1800:])
print("===== 字节:", len(text), "耗时: %.0fs =====" % (time.time() - t0))
