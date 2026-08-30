#!/usr/bin/env python3
"""
perla-system-action-mcp — a small local MCP server exposing ONE tool,
system_action, through which Perla can run a fixed allowlist of system
actions (lock, shutdown, restart, suspend, mute, unmute, open_app,
open_folder).

Why this exists: system actions used to be triggered by keyword matching
in perla-companion.py BEFORE the model ever saw the message (a "tier0"
fast path). Substring heuristics fired on unrelated words — "code block"
locked the screen, "commute" muted audio. By making the action an explicit
tool the MODEL decides to call, nothing in the text can trigger an action
unless the model deliberately invokes it.

The server does NOT execute anything itself. It calls perla-companion's
local-only endpoint POST /api/internal/system-action, which owns the
allowlist and runs the commands in the daemon's user-session environment
(Wayland/Noctalia bus, PipeWire, user systemd bus). Registered in
opencode-t1.json as a local MCP server, same shape as the view-screen and
reminders MCP servers.
"""

import json
import os
import urllib.request
import urllib.error

from mcp.server.fastmcp import FastMCP

PERLA_COMPANION_PORT = os.environ.get("PERLA_COMPANION_PORT", "8443")
DAEMON = f"http://127.0.0.1:{PERLA_COMPANION_PORT}"

LOCAL_TOKEN_FILE = os.path.expanduser("~/.config/perla/secrets/local-token")
if os.path.exists(LOCAL_TOKEN_FILE):
    with open(LOCAL_TOKEN_FILE) as f:
        LOCAL_TOKEN = f.read().strip()
else:
    LOCAL_TOKEN = "local-only-no-remote-exposure"

mcp = FastMCP("perla-system-action")


@mcp.tool()
def system_action(action: str, target: str | None = None) -> str:
    """Run exactly one allowlisted system action on the user's computer.

    Call this when the user asks you to physically affect their machine, and
    NOT otherwise — there is no other way for a command to run, and nothing
    runs automatically from the words they type or say.

    `action` is one of:
      - "lock" — lock the screen.
      - "shutdown" — power off the computer.
      - "restart" — reboot the computer.
      - "suspend" — put the computer to sleep.
      - "mute" — mute audio output.
      - "unmute" — unmute audio output.
      - "open_app" — open an application; `target` is the app name. Known
        shortcuts: firefox (also "browser"), terminal (also "kitty"), code
        (also "editor" / "codium"). Any OTHER installed app works too —
        give its name exactly as the user said it (e.g. "Spotify", "vlc",
        "LibreOffice Writer") and it's resolved from its installed
        launcher. Only ever LAUNCHES the app; it does not let you run
        arbitrary commands. An unmatched name returns an error listing
        what you can open — do not invent app names.
      - "open_folder" — open a folder in the file manager; `target` is the
        path (e.g. "~/Documents"). This opens the folder in the file
        manager and does NOT grant you access to read or edit its contents.

    There is deliberately no "unlock" action — unlocking stays manual.

    Returns a short confirmation (e.g. "Locked."), or an error message to
    relay to the user as-is (e.g. an unknown action or app name).
    """
    req = urllib.request.Request(
        DAEMON + "/api/internal/system-action",
        method="POST",
        headers={
            "Authorization": f"Bearer {LOCAL_TOKEN}",
            "Content-Type": "application/json",
        },
        data=json.dumps({"action": action, "target": target}).encode(),
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            body = json.loads(res.read())
    except urllib.error.URLError as e:
        return f"Couldn't reach the system-action service: {e}"
    except Exception as e:
        return f"Something went wrong asking for the system action: {e}"

    if body.get("ok"):
        return body.get("message") or f"Ran {action}."
    return body.get("error", f"Couldn't run {action}.")


if __name__ == "__main__":
    mcp.run()