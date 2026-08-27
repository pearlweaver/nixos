#!/usr/bin/env python3
"""Regression test for the view_screen MCP deadlock.

The bug: perla-companion uses a single-threaded HTTPServer, and /api/text
blocks that single thread in the whole OpenCode round-trip (up to 300s). When
the model then calls the view_screen MCP tool mid-message, the tool's POST to
/api/internal/screenshot must be served by that SAME single thread — which is
already busy answering the very message that triggered the tool. The screenshot
request starves behind the LLM call and the MCP client times out.

This test wedges the daemon with a deliberately incomplete HTTP request (the
stand-in for a /api/text handler that's blocked on the LLM), then asserts that
/api/internal/screenshot still responds promptly and returns real image data.

    Before fix (single-threaded): the screenshot endpoint starves -> PASS fails.
    After fix (ThreadingHTTPServer): it's served concurrently -> PASS.

Run against a live daemon:  python3 check_view_screen_concurrency.py
"""
import json
import os
import socket
import threading
import time
import urllib.error
import urllib.request

PORT = os.environ.get("PERLA_COMPANION_PORT", "8443")
URL = f"http://127.0.0.1:{PORT}/api/internal/screenshot"
TOKEN_FILE = os.path.expanduser("~/.config/perla/secrets/local-token")
TOKEN = open(TOKEN_FILE).read().strip()
HOLD_S = 8
CLIENT_TIMEOUT_S = 4
MAX_OK_ELAPSED_S = 3.5


def wedge(hold_s):
    s = socket.create_connection(("127.0.0.1", int(PORT)), timeout=5)
    # Send an HTTP request that never completes (no terminating blank line) —
    # the single-threaded server blocks reading this connection, exactly like
    # a /api/text handler blocked on a long LLM round-trip would.
    s.sendall(b"POST /api/text HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n")
    time.sleep(hold_s)
    s.close()


t = threading.Thread(target=wedge, args=(HOLD_S,))
t.start()
time.sleep(0.7)  # give the wedge time to be accepted

start = time.time()
try:
    req = urllib.request.Request(
        URL, method="POST",
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Length": "0"},
        data=b"",
    )
    with urllib.request.urlopen(req, timeout=CLIENT_TIMEOUT_S) as res:
        body = json.loads(res.read())
    elapsed = time.time() - start
    ok = res.status == 200 and elapsed < MAX_OK_ELAPSED_S and "image_base64" in body
    print(
        f"{'PASS' if ok else 'FAIL'}: screenshot endpoint during concurrent "
        f"request status={res.status} elapsed={elapsed:.2f}s "
        f"base64_len={len(body.get('image_base64', ''))}"
    )
except Exception as e:
    elapsed = time.time() - start
    print(
        f"FAIL: screenshot endpoint starved during concurrent request — "
        f"{e} after {elapsed:.2f}s"
    )
finally:
    t.join(timeout=HOLD_S + 2)