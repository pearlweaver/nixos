#!/usr/bin/env python3
"""
perla-view-screen-mcp — a small local MCP server exposing exactly one
tool, view_screen, that lets the model decide for itself when it needs
to look at the user's screen to answer a question.

Why this exists as a separate MCP server rather than a plain OpenCode
custom tool (.opencode/tools/): as of writing, custom tools can only
return strings — they cannot return image content to the model. MCP
tools can. See https://github.com/anomalyco/opencode/issues/9539.

This server does NOT reimplement screenshot capture or lock-detection.
It calls perla-companion's existing local-only endpoint
(POST /api/internal/screenshot), which reuses the exact same
capture_screenshot() function already used by the tier0 "send me a
screenshot" command and the fixed-phrase vision path. This keeps the
lock/standby safety check defined in exactly one place, regardless of
which of the three surfaces triggers a capture.

Registered in opencode-t1.json (and Tier 2's config) as a local MCP
server, same shape as perla-obsidian-mcp, so the model can call it from
either tier.
"""

import base64
import json
import os
import sys
import urllib.request
import urllib.error

from mcp.server.fastmcp import FastMCP, Image

PERLA_COMPANION_PORT = os.environ.get("PERLA_COMPANION_PORT", "8443")
DAEMON = f"http://127.0.0.1:{PERLA_COMPANION_PORT}"

LOCAL_TOKEN_FILE = os.path.expanduser("~/.config/perla/secrets/local-token")
if os.path.exists(LOCAL_TOKEN_FILE):
    with open(LOCAL_TOKEN_FILE) as f:
        LOCAL_TOKEN = f.read().strip()
else:
    LOCAL_TOKEN = "local-only-no-remote-exposure"

mcp = FastMCP("perla-view-screen")


@mcp.tool()
def view_screen():
    """Look at what is currently on the user's screen right now.

    Call this whenever answering the user's question requires seeing
    their screen — for example if they ask what something on screen
    says, what app or window is open, what song or video is playing,
    whether something looks right, or anything else that depends on
    the current visual state of their display. Do not call this for
    questions that have nothing to do with the screen's contents.

    Returns the current screenshot as an image, or a short text
    explanation if the screen can't be captured right now (for example
    if the screen is locked).
    """
    req = urllib.request.Request(
        DAEMON + "/api/internal/screenshot",
        method="POST",
        headers={"Authorization": f"Bearer {LOCAL_TOKEN}", "Content-Length": "0"},
        data=b"",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            body = json.loads(res.read())
    except urllib.error.URLError as e:
        return f"Couldn't reach the screen-capture service: {e}"
    except Exception as e:
        return f"Something went wrong asking for the screenshot: {e}"

    if "error" in body:
        # e.g. "the screen's locked" — pass the daemon's own message
        # through unchanged rather than inventing a different one.
        return body["error"]

    if "image_base64" not in body:
        return "Screenshot service returned an unexpected response."

    try:
        raw = base64.b64decode(body["image_base64"])
    except Exception as e:
        return f"Couldn't decode the screenshot: {e}"

    return Image(data=raw, format="png")


if __name__ == "__main__":
    mcp.run()
