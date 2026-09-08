#!/usr/bin/env python3
"""
perla-file-mcp — a small local MCP server exposing two tools, send_file
and list_files, that let the model find and hand back existing files
from disk without needing shell/write access.

Same "thin proxy" shape as perla-view-screen-mcp.py: all the real logic
(path resolution, the search-root allowlist, staging a copy for the web
UI to serve, size limits) lives in perla-companion.py, reused by both
tiers via a local-only HTTP endpoint. This server just forwards the
call and shapes the result for the model.

Registered in BOTH opencode-t1.json and opencode-t2.json's mcp block —
sending an EXISTING file is read-only from the model's point of view
(same trust level as view_screen), so it's available in Tier 1 despite
Tier 1's blanket write/edit/bash denies. Tier 2 additionally has raw
write access and is expected to call send_file on anything it creates
that the user should receive (see AGENTS.md / Tier 2 instructions).
"""

import json
import os
import urllib.request
import urllib.error
import traceback
from datetime import datetime

from mcp.server.fastmcp import FastMCP

# Temporary diagnostic logging to a plain file — NOT stdout/stderr. MCP
# servers speak their protocol over stdio, so any stray print() to
# stdout risks corrupting the JSON-RPC message stream itself, which
# could silently break the tool call/response round-trip in exactly the
# "tool ran, model saw nothing real back" way being investigated here.
# Writing to a separate file sidesteps that risk entirely while still
# giving hard evidence of what this process actually does on each call.
_DEBUG_LOG = os.path.expanduser("~/.local/share/perla/file-mcp-debug.log")


def _debug(msg):
    try:
        os.makedirs(os.path.dirname(_DEBUG_LOG), exist_ok=True)
        with open(_DEBUG_LOG, "a") as f:
            f.write(f"[{datetime.now().isoformat()}] {msg}\n")
    except Exception:
        pass  # diagnostic logging must never itself break the tool

PERLA_COMPANION_PORT = os.environ.get("PERLA_COMPANION_PORT", "8443")
DAEMON = f"http://127.0.0.1:{PERLA_COMPANION_PORT}"

# Which tier this MCP server instance is running under (1 or 2) — set per
# tier in the Nix config (opencode-t1.json vs opencode-t2-config.nix), NOT
# inferred from anything else. Sent along with send_file so the daemon can
# record which tier's turn just staged a file, as a schema-independent
# fallback for detecting a successful send when OpenCode's tool-result
# JSON can't be parsed directly (see call_opencode / _record_staged_file
# in perla-companion.py). Defaults to 0 (untracked) if somehow unset, in
# which case the fallback simply doesn't apply for this call — send_file
# still works normally either way, this only affects the extra safety net.
try:
    PERLA_TIER = int(os.environ.get("PERLA_TIER", "0"))
except ValueError:
    PERLA_TIER = 0

LOCAL_TOKEN_FILE = os.path.expanduser("~/.config/perla/secrets/local-token")
if os.path.exists(LOCAL_TOKEN_FILE):
    with open(LOCAL_TOKEN_FILE) as f:
        LOCAL_TOKEN = f.read().strip()
else:
    LOCAL_TOKEN = "local-only-no-remote-exposure"

mcp = FastMCP("perla-file")


def _post(endpoint, payload):
    _debug(f"_post called: endpoint={endpoint} payload={payload}")
    req = urllib.request.Request(
        DAEMON + endpoint,
        method="POST",
        headers={
            "Authorization": f"Bearer {LOCAL_TOKEN}",
            "Content-Type": "application/json",
        },
        data=json.dumps(payload).encode("utf-8"),
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            raw = res.read()
            _debug(f"_post got HTTP {res.status}, body={raw!r}")
            return json.loads(raw), None
    except urllib.error.URLError as e:
        _debug(f"_post URLError: {e}")
        return None, f"Couldn't reach the file service: {e}"
    except Exception as e:
        _debug(f"_post Exception: {e}\n{traceback.format_exc()}")
        return None, f"Something went wrong contacting the file service: {e}"


@mcp.tool()
def send_file(query: str):
    """Find an existing file on the user's computer and send it to them
    through the chat (it will appear as a downloadable file in their
    conversation, both live and in History).

    IMPORTANT: this tool NEVER opens, reads, parses, or looks at the
    file's contents — it only locates the file on disk and copies its
    raw bytes so the user can download it. This works for EVERY file
    type without exception, including PDFs, images, spreadsheets,
    archives, or anything else. You do not need to be able to "read" or
    "process" a file type to send it — those are unrelated capabilities.
    If the user asks you to send a file, call this tool regardless of
    its extension; never refuse a send_file request by saying you can't
    read/process/open that file type, since this tool doesn't need to.

    `query` can be:
      - an exact filename, e.g. "invoice.pdf"
      - a path relative to Perla's default files folder, e.g.
        "reports/q3.xlsx"
      - an absolute path (e.g. "~/Documents/notes.pdf" or
        "/home/user/Documents/notes.pdf") — still only works if that
        path falls under Perla's default files folder or one of the
        allowed extra folders (Downloads, Documents, Pictures)
      - a partial/fuzzy name if you're not sure of the exact filename,
        e.g. "invoice" or "vacation photo"

    Search is restricted to Perla's default files folder plus a small
    set of common folders (Downloads, Documents, Pictures) — it cannot
    reach arbitrary paths on the system.

    Behavior:
      - Exactly one match: the file is staged and sent immediately —
        the return value's "ok" will be true with an "id" and
        "filename". Just tell the user you're sending it; you do not
        need to do anything else, and you should NOT describe, quote,
        or summarize the file's contents (you never saw them).
      - Zero or multiple matches: nothing is sent ("ok" will be false).
        You get back a list of candidate filenames (or an empty list)
        instead — read that list to the user and ask which one they
        meant, or say that none were found. Do NOT guess and call this
        again with a made-up exact name; ask the user to clarify using
        the actual candidate names returned. If it comes back empty
        for a path you were fairly confident about, the most likely
        explanations are a typo in the filename or the file simply not
        existing at that location — say so plainly rather than
        inventing a different reason.
    """
    _debug(f"send_file() ENTRY: query={query!r} PERLA_TIER={PERLA_TIER}")
    try:
        if not query or not query.strip():
            _debug("send_file() empty query, returning early")
            return json.dumps({"ok": False, "error": "No filename given."})

        result, error = _post("/api/internal/send-file", {"query": query, "tier": PERLA_TIER})
        if error:
            _debug(f"send_file() returning error result: {error}")
            return json.dumps({"ok": False, "error": error})
        out = json.dumps(result)
        _debug(f"send_file() returning success: {out}")
        return out
    except Exception as e:
        _debug(f"send_file() UNCAUGHT EXCEPTION: {e}\n{traceback.format_exc()}")
        return json.dumps({"ok": False, "error": f"Internal error in send_file: {e}"})


@mcp.tool()
def list_files(directory: str = ""):
    """List files in Perla's default files folder (or a subfolder of
    it). Use this when the user asks what files they have, or to help
    you figure out the exact name of a file before calling send_file —
    for example if send_file returned no matches and you want to browse
    instead of guessing again.

    `directory` is optional — omit it to list the top level of the
    default files folder. If given, it must be a relative subfolder
    path under the default folder (e.g. "reports"), not an absolute
    path outside it.
    """
    result, error = _post("/api/internal/list-files", {"dir": directory or None})
    if error:
        return json.dumps({"ok": False, "error": error})
    return json.dumps(result)


if __name__ == "__main__":
    _debug(f"=== perla-file-mcp STARTED, pid={os.getpid()}, PERLA_TIER={PERLA_TIER}, DAEMON={DAEMON} ===")
    mcp.run()
