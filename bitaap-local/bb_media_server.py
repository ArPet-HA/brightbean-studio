"""Media-only public endpoint for BrightBean Studio (so Meta can fetch images).

Serves GET/HEAD for files under BrightBean's media folder at /media/<path>.
No directory listings, nothing outside the media folder, nothing else of the app.
"""
import mimetypes
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

MEDIA_ROOT = os.path.realpath(sys.argv[1])
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8001


class Handler(BaseHTTPRequestHandler):
    def _resolve(self):
        path = unquote(urlparse(self.path).path)
        if not path.startswith("/media/"):
            return None
        target = os.path.realpath(os.path.join(MEDIA_ROOT, path[len("/media/"):]))
        if not target.startswith(MEDIA_ROOT + os.sep) or not os.path.isfile(target):
            return None
        return target

    def _serve(self, body):
        target = self._resolve()
        if not target:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", mimetypes.guess_type(target)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(os.path.getsize(target)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if body:
            with open(target, "rb") as f:
                self.wfile.write(f.read())

    def do_GET(self):
        self._serve(True)

    def do_HEAD(self):
        self._serve(False)


if __name__ == "__main__":
    print(f"Serving {MEDIA_ROOT} at port {PORT}/media/", flush=True)
    ThreadingHTTPServer((os.environ.get("BIND", "127.0.0.1"), PORT), Handler).serve_forever()
