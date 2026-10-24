"""Tiny local site for plugin-sandbox-tests (S192): sets cookies, echoes the Cookie header, redirects.
Prints its port on the first line, then serves until killed."""
import http.server, sys, urllib.parse


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = dict(urllib.parse.parse_qsl(url.query))
        if url.path == "/set":
            # /set?name=value[&persist=1]
            self.send_response(200)
            for name, value in q.items():
                if name == "persist":
                    continue
                age = "; Max-Age=3600" if q.get("persist") else ""
                self.send_header("Set-Cookie", f"{name}={value}; Path=/{age}")
            self.end_headers()
            self.wfile.write(b"ok")
        elif url.path == "/echo":
            self.send_response(200)
            self.end_headers()
            self.wfile.write((self.headers.get("Cookie") or "").encode())
        elif url.path == "/redir":
            self.send_response(302)
            self.send_header("Location", q.get("to", "/echo"))
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
