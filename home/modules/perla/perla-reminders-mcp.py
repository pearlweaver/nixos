#!/usr/bin/env python3
"""
perla-reminders-mcp — a small local MCP server exposing reminder tools
(create_reminder, list_reminders, cancel_reminder) to Perla in Tier 1.

Why this exists instead of having Perla append to Reminders.md directly:
the file lives at the vault ROOT (outside the Tier-1 "You CAN write to
Conversations/, Memory/Short-Term/, Command Log/" allowlist in AGENTS.md),
so voice/quick replies have repeatedly either refused to write it or
pretended to. An explicit MCP tool makes reminder creation a supported,
first-class action in the tier.

This server does NOT reimplement the reminder schema or storage. It calls
perla-companion's local-only endpoint POST /api/reminders, which owns all
row validation/writing via _append_reminder/_cancel_reminder and shares a
file lock with perla-reminder-check. That keeps:
  - the row format contract in exactly one place (the daemon),
  - the web view (get_reminders) and the delivery job parsing the same rows.

Registered in opencode-t1.json as a local MCP server, same shape as
perla-view-screen-mcp.
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

mcp = FastMCP("perla-reminders")


def _post(payload):
    req = urllib.request.Request(
        DAEMON + "/api/reminders",
        method="POST",
        headers={
            "Authorization": f"Bearer {LOCAL_TOKEN}",
            "Content-Type": "application/json",
        },
        data=json.dumps(payload).encode(),
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            return json.loads(res.read())
    except urllib.error.URLError as e:
        return {"ok": False, "error": f"Couldn't reach the reminder service: {e}"}
    except Exception as e:
        return {"ok": False, "error": f"Something went wrong with the reminder service: {e}"}


@mcp.tool()
def create_reminder(due: str, text: str, repeat: str | None = None) -> str:
    """Create a reminder for the user. This is the ONLY supported way to add
    a reminder — do not try to write to Reminders.md yourself.

    Args:
        due: Absolute local timestamp in YYYY-MM-DDTHH:MM form (minute
            precision, no timezone suffix, local clock time). Work this out
            from the user's phrasing: "in 20 minutes" → current time + 20
            minutes; "at 6pm" → today (or tomorrow if already past) at 18:00.
        text: The thing being reminded, phrased as the thing itself
            ("Call the dentist"), not a meta-description ("reminder about
            the dentist"). This is what gets spoken back to the user later.
        repeat: Optional recurrence token, used EXACTLY (lowercase):
            "hourly", "daily", "weekly", "monthly", "yearly", or
            "every:Nh" / "every:Nd" / "every:Nw" (N ≥ 1). For recurring
            reminders the `due` must be the FIRST occurrence (the anchor);
            the delivery job computes every later occurrence. One-shot
            reminders: omit repeat.

    Returns a short confirmation including the new id, or an error message
    to relay to the user as-is (e.g. an unparseable due timestamp).
    """
    body = _post({"action": "create", "due": due, "text": text, "repeat": repeat})
    if body.get("ok"):
        return f"Created reminder {body['id']} for {due}."
    return body.get("error", "Reminder creation failed.")


@mcp.tool()
def list_reminders() -> str:
    """List the user's pending reminders, newest-scheduled first is fine but
    due-order is what they usually want — just summarize them conversationally.

    Returns each pending reminder's id, due time, repeat token (if any), and
    text. Use this when the user asks what reminders they have, what's due,
    etc. Distinguish nothing that's not in the list — there are no other
    reminder stores.
    """
    body = _post({"action": "list"})
    if not body.get("ok"):
        return body.get("error", "Couldn't list reminders.")
    pending = body.get("pending", [])
    if not pending:
        return "No pending reminders."
    lines = []
    for r in pending:
        repeat = r.get("repeat")
        repeat_part = f" (repeat: {repeat})" if repeat else ""
        lines.append(f"- id:{r['id']} at {r['due']}{repeat_part}: {r['text']}")
    return "\n".join(lines)


@mcp.tool()
def cancel_reminder(id: str) -> str:
    """Cancel a pending reminder by its id (a short hex string from
    create_reminder or list_reminders). Use when the user wants to remove or
    turn off a reminder. Only pending reminders can be cancelled — a reminder
    already delivered today stays in the file for the day's history.

    Args:
        id: The reminder's id, e.g. "ab12".

    Returns a confirmation, or an error if no pending reminder has that id.
    """
    body = _post({"action": "cancel", "id": id})
    if body.get("ok"):
        return body.get("id", f"Cancelled reminder {id}.")
    return body.get("error", f"Couldn't cancel reminder {id}.")


if __name__ == "__main__":
    mcp.run()