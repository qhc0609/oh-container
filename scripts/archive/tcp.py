import socket, ssl, sys
try:
    s = socket.create_connection(("api.deepseek.com", 443), timeout=10)
    ctx = ssl.create_default_context()
    ss = ctx.wrap_socket(s, server_hostname="api.deepseek.com")
    print("TLS_OK", ss.version(), ss.getpeercert().get("subject"))
    ss.close()
except Exception as e:
    print("TLS_FAIL", type(e).__name__, e)
