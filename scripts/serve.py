#!/usr/bin/env python3
#
# @description Serve a directory over HTTP, instantly (python http.server)
# @usage tiss serve [--port 8000] [--dir .] [--bind 127.0.0.1]
# @example tiss serve
# @example tiss serve --port 9000 --dir ./dist
# @needs python3
#
# The one-liner you always half-remember, made a command: share build
# output, test a static site, hand a file to a teammate. Binds loopback
# by default — pass --bind 0.0.0.0 deliberately to expose it.
#
import http.server
import socketserver
import sys


def main():
    args = sys.argv[1:]
    port, directory, bind = 8000, ".", "127.0.0.1"

    while args:
        a = args.pop(0)
        if a in ("-h", "--help", "help"):
            print("usage: tiss serve [--port 8000] [--dir .] [--bind 127.0.0.1]", file=sys.stderr)
            sys.exit(0)
        elif a == "--port":
            port = int(args.pop(0))
        elif a == "--dir":
            directory = args.pop(0)
        elif a == "--bind":
            bind = args.pop(0)
        else:
            print(f"serve: unknown argument {a}", file=sys.stderr)
            sys.exit(2)

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=directory, **kw)

        def log_message(self, fmt, *a):  # requests to stderr, stdout stays clean
            print(f"{self.address_string()} {fmt % a}", file=sys.stderr)

    class Server(socketserver.TCPServer):
        allow_reuse_address = True  # instant restarts, no TIME_WAIT sulk

    with Server((bind, port), Handler) as httpd:
        print(f"serving {directory} at http://{bind}:{port}/ (ctrl-c to stop)", file=sys.stderr)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped.", file=sys.stderr)


if __name__ == "__main__":
    main()
