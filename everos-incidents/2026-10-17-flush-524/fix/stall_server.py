# Test-only "silent upstream": accepts HTTP connections on 127.0.0.1:39999,
# answers GET /v1/models (so magpie can list a model) and never answers anything else.
import socket, threading, time, json
MODELS = json.dumps({"object":"list","data":[{"id":"stall","object":"model"}]}).encode()
def handle(c):
    try:
        data = c.recv(65536)
        if data.startswith(b"GET") and b"/models" in data.split(b"\r\n")[0]:
            c.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(MODELS) + MODELS)
            c.close(); return
        print(time.strftime("%H:%M:%S"), "holding", data.split(b"\r\n")[0], flush=True)
        time.sleep(600)
    except Exception as e:
        print("err", e, flush=True)
    finally:
        c.close()
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 39999)); s.listen(50)
print("listening", flush=True)
while True:
    c, _ = s.accept(); threading.Thread(target=handle, args=(c,), daemon=True).start()
