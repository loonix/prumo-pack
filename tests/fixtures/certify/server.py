#!/usr/bin/env python3
"""Stand-in for a live site, used by tests/test_certify.sh.

Serves tests/fixtures/certify/site/ for GET and a tiny fake API:

  GET  /health          200 {"db": "ok"}
  GET  /api/private     401 (no session)
  POST /api/items       400 unless the JSON body has price_cents > 0, then 201;
                        401 when the X-Api-Key header is present and wrong

Binds 127.0.0.1 on a free port and writes the port to the file given as the
only argument, so the test knows where to point the certifier.
"""
import http.server
import json
import os
import sys

SITE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "site")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=SITE, **kwargs)

    def log_message(self, *args):
        pass

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self.reply(200, {"db": "ok"})
        if self.path == "/api/private":
            return self.reply(401, {"error": "no session"})
        return super().do_GET()

    def do_POST(self):
        if self.path != "/api/items":
            return self.reply(404, {"error": "not found"})
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        key = self.headers.get("X-Api-Key")
        if key is not None and key != "right-key":
            return self.reply(401, {"error": "bad key"})
        try:
            data = json.loads(raw or b"{}")
        except ValueError:
            return self.reply(400, {"error": "invalid json"})
        if not isinstance(data, dict) or not isinstance(data.get("price_cents"), int) \
                or data["price_cents"] <= 0:
            return self.reply(400, {"error": "price must be positive"})
        return self.reply(201, {"id": 1})


def main():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(sys.argv[1] + ".tmp", "w") as fh:
        fh.write(str(server.server_address[1]))
    os.replace(sys.argv[1] + ".tmp", sys.argv[1])
    server.serve_forever()


if __name__ == "__main__":
    main()
