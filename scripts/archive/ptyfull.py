import os, pty, select, time, signal, sys, re

CMD = "/data/ohc/bin/ohc run claude -- claude"

pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/sh", ["/bin/sh", "-c", CMD])

os.set_blocking(fd, False)
buf = b""
sent = set()
question_sent = False
t_ask = 0
t0 = time.time()
last_data = time.time()

def send(s):
    try:
        os.write(fd, s.encode() if isinstance(s, str) else s)
    except Exception as e:
        print("write err", e)

def low(b):
    x = re.sub(rb"\x1b\[[0-9;?]*[a-zA-Z]", b"", b).lower()
    return re.sub(rb"\s+", b"", x)   # 去掉所有空白，终端渲染会把空格吃掉

while time.time() - t0 < 120:
    r, _, _ = select.select([fd], [], [], 0.3)
    if r:
        try:
            d = os.read(fd, 8192)
        except (OSError, BlockingIOError):
            d = b""
        if d:
            buf += d
            last_data = time.time()
            l = low(buf)
            # 1) 主题选择
            if b"welcometoclaudecode" in l and "theme" not in sent:
                time.sleep(1.2); send("\r"); sent.add("theme")
            # 2) "Press Enter to continue"
            if b"pressentertocontinue" in l and "cont" not in sent:
                time.sleep(1.2); send("\r"); sent.add("cont")
            # 3) 信任目录：默认是 No,exit，必须下移一格再回车
            if (b"yes,itrustthisfolder" in l or b"quicksafetycheck" in l) and "trust" not in sent:
                time.sleep(1.2)
                send("\x1b[B")   # 方向键下 -> Yes, I trust this folder
                time.sleep(0.4)
                send("\r")
                sent.add("trust")
    else:
        # 4) 静默 6 秒后提问
        if not question_sent and "trust" in sent and time.time() - last_data > 6:
            send("你是什么模型？一句话回答，不要调用工具\r")
            question_sent = True
            t_ask = time.time()
        if question_sent and time.time() - t_ask > 45:
            break
        if time.time() - t0 > 115:
            break

try:
    send("\x03"); time.sleep(0.6); send("/exit\r"); time.sleep(1.2)
    os.kill(pid, signal.SIGKILL)
except Exception:
    pass
try:
    os.waitpid(pid, 0)
except Exception:
    pass

text = buf.decode("utf-8", "replace")
clean = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b[\(\)][A-Z0-9]|\x1b[=>]", "", text)
clean = re.sub(r"[ \t]{3,}", " ", clean)
clean = re.sub(r"\n{3,}", "\n\n", clean)
print("===== 交互会话输出（末尾 3500 字符）=====")
print(clean[-3500:])
print("===== 总字节:", len(text), " 耗时: %.0fs =====" % (time.time() - t0))
