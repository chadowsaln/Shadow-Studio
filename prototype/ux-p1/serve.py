#!/usr/bin/env python3
"""Serve the prototype with caching disabled, so edits show up on reload.

    python3 prototype/ux-p1/serve.py [port]
"""

import functools
import http.server
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, max-age=0")
        super().end_headers()

    def log_message(self, fmt: str, *args) -> None:  # quieter console
        sys.stderr.write("%s\n" % (fmt % args))


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8137
    handler = functools.partial(Handler, directory=ROOT)
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as httpd:
        print(f"prototype on http://127.0.0.1:{port}/index.html")
        httpd.serve_forever()


if __name__ == "__main__":
    main()
