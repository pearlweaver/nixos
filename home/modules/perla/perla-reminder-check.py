#!/usr/bin/env python3
"""
perla-reminder-check — scans Reminders.md for due reminders and fires them
UNPROMPTED (no active conversation needed): voice via the daemon's local
speak endpoint + a desktop notification.

Runs on a systemd timer (every 5 min) — standalone from perla.sh and the
daemon's request/response cycle, since nothing "requests" a reminder firing.

Delivery rules:
- On-time and missed reminders are tracked as separate groups.
- Missed = the daemon/timer couldn't have run on time (machine was
  asleep/off through the due time) — different, honest framing, not just
  "reminder for X" repeated.
- If a group has <=3 reminders due in the same tick, each is spoken +
  notified individually, staggered a few seconds apart so they don't
  overlap into a wall of noise.
- If a group has >3, they're summarized into ONE spoken/notified message
  ("5 reminders are due — X, Y, Z, and 2 more") rather than firing five
  separate interruptions back to back.
- Missed group fires before on-time group if both are non-empty in the
  same tick (chronological sense — catch up on the past before the present).
"""

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime

CONFIG_FILE = os.path.expanduser("~/.config/perla/perla.env")


def load_env():
    """Minimal .env-style loader so this doesn't need python-dotenv."""
    env = dict(os.environ)
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                v = v.strip().strip('"').strip("'")
                env.setdefault(k, v)
    return env


ENV = load_env()
PERLA_NAME = ENV.get("PERLA_NAME", "Perla")
PERLA_VAULT = ENV.get("PERLA_VAULT", os.path.expanduser("~/Documents/Obsidian/PerlaNew"))
COMPANION_PORT = ENV.get("PERLA_COMPANION_PORT", "8443")
DAEMON = f"http://127.0.0.1:{COMPANION_PORT}"

LOCAL_TOKEN_FILE = os.path.expanduser("~/.config/perla/secrets/local-token")
if os.path.exists(LOCAL_TOKEN_FILE):
    with open(LOCAL_TOKEN_FILE) as f:
        LOCAL_TOKEN = f.read().strip()
else:
    LOCAL_TOKEN = "local-only-no-remote-exposure"

REMINDERS_FILE = os.path.join(PERLA_VAULT, "Reminders.md")
LOCK_FILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "perla", "reminder-check.lock")
GC_AFTER_HOURS = 48
MISSED_THRESHOLD_MIN = 6
MAX_INDIVIDUAL = 3
STAGGER_SECONDS = 4

LINE_RE = re.compile(r"^- \[ \] ([0-9T:-]+) \| id:([a-f0-9]+) \| (.*)$")
DONE_RE = re.compile(r"^- \[x\] ([0-9T:-]+) \| id:([a-f0-9]+) \|.*delivered ([0-9T:-]+)")


def log(msg):
    print(f"[perla-reminder-check] {msg}", file=sys.stderr, flush=True)


def notify(title, body):
    try:
        subprocess.run(["notify-send", "-a", PERLA_NAME, title, body], timeout=5)
    except Exception as e:
        log(f"WARNING: notify-send failed: {e}")


def speak(text):
    try:
        subprocess.run(
            ["curl", "-sf", "--connect-timeout", "3", "-m", "60",
             "-X", "POST", f"{DAEMON}/api/speak-local",
             "-H", "Content-Type: application/json",
             "-H", f"Authorization: Bearer {LOCAL_TOKEN}",
             "-d", json.dumps({"text": text})],
            timeout=65, capture_output=True
        )
    except Exception as e:
        log(f"WARNING: speak-local call failed: {e}")


def parse_ts(ts):
    try:
        return datetime.fromisoformat(ts).timestamp()
    except ValueError:
        return None


def deliver_group(items, missed):
    """items: list of (due_ts, rid, text, overdue_min). Speaks/notifies
    either individually (<=3) or as one summary (>3). Returns list of
    (rid, delivered_iso, missed) for the caller to mark in the file."""
    if not items:
        return []

    delivered = []
    now_iso = datetime.now().isoformat(timespec="minutes")

    if len(items) <= MAX_INDIVIDUAL:
        for i, (due_ts, rid, text, overdue_min) in enumerate(items):
            if missed:
                spoken = f"Hey — I missed this earlier while you were away, but you'd asked me to remind you: {text}"
                title = f"{PERLA_NAME} (missed reminder)"
                body = f"You asked to be reminded of this at {due_ts} — I couldn't reach you then: {text}"
            else:
                spoken = f"Hey, reminder: {text}"
                title = PERLA_NAME
                body = text

            log(f"Firing reminder {rid} ({'missed' if missed else 'on-time'}): {text}")
            notify(title, body)
            speak(spoken)
            delivered.append((rid, now_iso, missed))

            if i < len(items) - 1:
                time.sleep(STAGGER_SECONDS)
    else:
        preview = [text for (_, _, text, _) in items[:3]]
        remaining = len(items) - 3
        summary_list = ", ".join(preview)
        count = len(items)

        if missed:
            spoken = (
                f"Hey — while you were away I missed {count} reminders. "
                f"{summary_list}, and {remaining} more."
            )
            title = f"{PERLA_NAME} (missed {count} reminders)"
            body = f"{summary_list}, and {remaining} more."
        else:
            spoken = (
                f"You've got {count} reminders due right now — "
                f"{summary_list}, and {remaining} more."
            )
            title = f"{PERLA_NAME} ({count} reminders due)"
            body = f"{summary_list}, and {remaining} more."

        log(f"Firing summary for {count} {'missed' if missed else 'on-time'} reminders.")
        notify(title, body)
        speak(spoken)

        for (_, rid, _, _) in items:
            delivered.append((rid, now_iso, missed))

    return delivered


def main():
    os.makedirs(os.path.dirname(LOCK_FILE), exist_ok=True)

    # Simple lock file so overlapping ticks (slow TTS + next 5-min fire)
    # can't double-process. Not using flock module to keep this dependency-
    # free; PID-check is good enough for a 5-minute-interval job.
    if os.path.exists(LOCK_FILE):
        try:
            with open(LOCK_FILE) as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)  # raises if not running
            log("Another check is already running, skipping this tick.")
            return
        except (ValueError, ProcessLookupError, PermissionError):
            pass  # stale lock, proceed

    with open(LOCK_FILE, "w") as f:
        f.write(str(os.getpid()))

    try:
        _run()
    finally:
        try:
            os.remove(LOCK_FILE)
        except FileNotFoundError:
            pass


def _run():
    if not os.path.exists(REMINDERS_FILE):
        return

    with open(REMINDERS_FILE) as f:
        lines = f.read().splitlines()

    now = time.time()
    on_time_items = []
    missed_items = []
    kept_lines = []
    due_line_indices = {}  # rid -> original line index, for rewriting

    for idx, line in enumerate(lines):
        m = LINE_RE.match(line)
        if m:
            due_ts, rid, text = m.groups()
            due_epoch = parse_ts(due_ts)
            if due_epoch is not None and now >= due_epoch:
                overdue_min = (now - due_epoch) / 60
                due_line_indices[rid] = (idx, due_ts, text)
                if overdue_min >= MISSED_THRESHOLD_MIN:
                    missed_items.append((due_ts, rid, text, overdue_min))
                else:
                    on_time_items.append((due_ts, rid, text, overdue_min))
                continue  # don't keep as-is; will be replaced below
        kept_lines.append((idx, line))

    if not on_time_items and not missed_items:
        # Still run GC pass even if nothing fired this tick.
        _garbage_collect(lines)
        return

    # Missed group first (catch up on the past), then on-time.
    delivered = []
    delivered += deliver_group(missed_items, missed=True)
    delivered += deliver_group(on_time_items, missed=False)

    delivered_map = {rid: (ts, missed) for rid, ts, missed in delivered}

    # Rebuild file: kept lines as-is, plus rewritten delivered lines,
    # in original order.
    new_lines = [None] * len(lines)
    for idx, line in kept_lines:
        new_lines[idx] = line
    for rid, (idx, due_ts, text) in due_line_indices.items():
        delivered_ts, missed = delivered_map[rid]
        suffix = ", missed" if missed else ""
        new_lines[idx] = f"- [x] {due_ts} | id:{rid} | {text} (delivered {delivered_ts}{suffix})"

    final_lines = [l for l in new_lines if l is not None]
    _garbage_collect_and_write(final_lines)


def _garbage_collect(lines):
    _garbage_collect_and_write(lines)


def _garbage_collect_and_write(lines):
    now = time.time()
    kept = []
    dropped = 0
    for line in lines:
        m = DONE_RE.match(line)
        if m:
            _, rid, delivered_ts = m.groups()
            delivered_epoch = parse_ts(delivered_ts)
            if delivered_epoch is not None and (now - delivered_epoch) / 3600 >= GC_AFTER_HOURS:
                dropped += 1
                continue
        kept.append(line)

    if dropped:
        log(f"GC: dropped {dropped} old delivered reminder(s).")

    with open(REMINDERS_FILE, "w") as f:
        f.write("\n".join(kept) + ("\n" if kept else ""))


if __name__ == "__main__":
    main()
