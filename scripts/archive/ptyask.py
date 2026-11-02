import os, pty, select, time, signal, re

CMD = "/data/ohc/bin/ohc run claude -- claude"
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

while time.time() - t0 < 90:
    r, _, _ = select.select([fd], [], [], 0.3)
    if r:
        try:
            d = os.read(fd, 8192)
        except (OSError, BlockingIOError):
            d = b""
        if d:
            buf += d
    else:
        # 启动后静默 8 秒，说明已经进入输入界面
        if not asked and time.time() - t0 > 8:
            send("你实际是哪个模型？只回答模型名，不要调用任何工具\r")
            asked = True
            t_ask = time.time()
        if asked and time.time() - t_ask > 45:
            break

send("\x03"); time.sleep(0.8)
try:
    send("/exit\r"); time.sleep(2)
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
print("===== 输出 =====")
print(clean[-2500:])
print("===== 字节:", len(text), "耗时: %.0fs =====" % (time.time() - t0))
