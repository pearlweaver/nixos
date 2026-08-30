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
- Recurring reminders: a pending row may carry `| repeat:<token> |` where
  token is one of hourly, daily, weekly, monthly, yearly, every:<N>h/<N>d/<N>w.
  The absolute timestamp on the row is the NEXT occurrence (and the anchor
  for the cadence). When a repeating row is due it fires with normal on-time
  framing and is REWRITTEN in place with the next occurrence instead of
  being marked [x]; it never enters the missed group and is never GC'd.
  The recurrence arithmetic lives here, not in Perla — the LLM only ever
  writes the token and a first occurrence.
"""

import calendar
import fcntl
import json
import os
import re
import subprocess
import sys
import time
from contextlib import contextmanager
from datetime import datetime, timedelta

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
# Advisory flock shared with the companion daemon (perla-companion.py) so a
# daemon reminder create/cancel and this periodic rewrite never interleave.
# Same canonical path/logic — anchored under ~/.local/share/perla because the
# timer environment may not carry XDG_RUNTIME_DIR.
REMINDER_FILE_LOCK = os.path.join(
    os.path.expanduser("~/.local/share/perla"), "reminders-file.lock"
)
GC_AFTER_HOURS = 48
MISSED_THRESHOLD_MIN = 6
MAX_INDIVIDUAL = 3
STAGGER_SECONDS = 4

LINE_RE = re.compile(
    r"^- \[ \] (?P<due>[0-9T:-]+) \| id:(?P<rid>[a-f0-9]+)"
    r"(?: \| repeat:(?P<repeat>[a-zA-Z0-9:]+))?"
    r" \| (?P<text>.*)$"
)
DONE_RE = re.compile(r"^- \[x\] ([0-9T:-]+) \| id:([a-f0-9]+) \|.*delivered ([0-9T:-]+)")


@contextmanager
def reminder_lock():
    """Exclusive flock across read-modify-write of Reminders.md, shared with
    the companion daemon's mutation functions."""
    lock_dir = os.path.dirname(REMINDER_FILE_LOCK)
    os.makedirs(lock_dir, exist_ok=True)
    f = open(REMINDER_FILE_LOCK, "a+")
    try:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(f, fcntl.LOCK_UN)
        f.close()


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


def _next_day_clamped(year, month, day):
    """Calendar day clamped to the last day of the month (e.g. 31 -> Feb 28)."""
    return min(day, calendar.monthrange(year, month)[1])


def _next_occurrence(due_dt, token, now_dt):
    """Compute the next occurrence strictly after `now_dt` for a repeat row.

    `due_dt` is the first-occurrence timestamp written to Reminders.md and is
    the recurrence anchor. Clock-anchored tokens (daily/weekly/monthly/yearly)
    hold a fixed wall-clock time; period-anchored ones (hourly, every:) hold a
    fixed phase from `due_dt`. Returns None for unknown tokens.
    """
    token = token.lower()
    anchor = due_dt.replace(second=0, microsecond=0)

    if token in ("hourly", "every:1h"):
        period = timedelta(hours=1)
    elif token.startswith("every:"):
        m = re.fullmatch(r"every:(\d+)([hdw])", token)
        if m is None or int(m.group(1)) < 1:
            return None
        factor = {"h": 3600, "d": 86400, "w": 604800}[m.group(2)]
        period = timedelta(seconds=factor * int(m.group(1)))
    elif token == "daily":
        nxt = now_dt.replace(hour=anchor.hour, minute=anchor.minute, second=0, microsecond=0)
        while nxt <= now_dt:
            nxt += timedelta(days=1)
        return nxt
    elif token == "weekly":
        nxt = now_dt.replace(hour=anchor.hour, minute=anchor.minute, second=0, microsecond=0)
        nxt += timedelta(days=(anchor.weekday() - nxt.weekday()) % 7)
        while nxt <= now_dt:
            nxt += timedelta(days=7)
        return nxt
    elif token == "monthly":
        nxt = now_dt.replace(hour=anchor.hour, minute=anchor.minute, second=0, microsecond=0)
        nxt = nxt.replace(day=_next_day_clamped(nxt.year, nxt.month, anchor.day))
        while nxt <= now_dt:
            ny, nm = (nxt.year + 1, 1) if nxt.month == 12 else (nxt.year, nxt.month + 1)
            nxt = nxt.replace(year=ny, month=nm, day=_next_day_clamped(ny, nm, anchor.day))
        return nxt
    elif token == "yearly":
        nxt = now_dt.replace(
            hour=anchor.hour, minute=anchor.minute, second=0, microsecond=0,
            month=anchor.month, day=_next_day_clamped(now_dt.year, anchor.month, anchor.day),
        )
        while nxt <= now_dt:
            y = nxt.year + 1
            nxt = nxt.replace(year=y, day=_next_day_clamped(y, anchor.month, anchor.day))
        return nxt
    else:
        return None

    nxt = anchor + period
    while nxt <= now_dt:
        nxt += period
    return nxt


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

    with reminder_lock():
        with open(REMINDERS_FILE) as f:
            lines = f.read().splitlines()

        now = time.time()
        now_iso = datetime.now().isoformat(timespec="minutes")
        on_time_items = []
        missed_items = []
        kept_lines = []
        due_line_indices = {}  # rid -> (idx, due_ts, text)  -> rewritten as [x]
        reschedule_map = {}    # rid -> (idx, due_ts, repeat_token, text) -> rewritten as next [ ]

        for idx, line in enumerate(lines):
            m = LINE_RE.match(line)
            if m:
                due_ts = m.group("due")
                rid = m.group("rid")
                repeat_token = m.group("repeat")
                text = (m.group("text") or "").strip()
                due_epoch = parse_ts(due_ts)
                if due_epoch is not None and now >= due_epoch:
                    overdue_min = (now - due_epoch) / 60
                    if repeat_token:
                        # Repeats always fire with the normal on-time framing —
                        # the "missed while you were away" fanfare would repeat
                        # every period. The checker reschedules the row.
                        on_time_items.append((due_ts, rid, text, overdue_min))
                        reschedule_map[rid] = (idx, due_ts, repeat_token, text)
                        continue
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

        missed_rids = {rid for (_, rid, _, _) in missed_items}

        # Rebuild file: kept lines as-is, plus rewritten delivered lines,
        # in original order. All inside the lock so a concurrent daemon
        # create/cancel can't interleave with this rewrite. Delivered stamps
        # use this tick's now_iso (delivery itself happens below, after the
        # lock is released — never hold the flock across TTS/sleeps).
        new_lines: list[str | None] = [None] * len(lines)
        for idx, line in kept_lines:
            new_lines[idx] = line
        for rid, (idx, due_ts, text) in due_line_indices.items():
            suffix = ", missed" if rid in missed_rids else ""
            new_lines[idx] = f"- [x] {due_ts} | id:{rid} | {text} (delivered {now_iso}{suffix})"
        for rid, (idx, due_ts, repeat_token, text) in reschedule_map.items():
            next_dt = _next_occurrence(
                datetime.fromisoformat(due_ts), repeat_token, datetime.now()
            )
            if next_dt is None:
                # Unknown token — can't reschedule safely; one-shot fallback.
                log(f"WARNING: unknown repeat token '{repeat_token}' on {rid}, treating as one-shot.")
                new_lines[idx] = f"- [x] {due_ts} | id:{rid} | {text} (delivered {now_iso})"
                continue
            next_ts = next_dt.strftime("%Y-%m-%dT%H:%M")
            log(f"Rescheduling reminder {rid} ({repeat_token}) to {next_ts}.")
            new_lines[idx] = f"- [ ] {next_ts} | id:{rid} | repeat:{repeat_token} | {text}"

        final_lines = [l for l in new_lines if l is not None]
        _garbage_collect_and_write(final_lines)

    # Missed group first (catch up on the past), then on-time.
    if missed_items:
        deliver_group(missed_items, missed=True)
    if on_time_items:
        deliver_group(on_time_items, missed=False)


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
