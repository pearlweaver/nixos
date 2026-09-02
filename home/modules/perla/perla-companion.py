#!/usr/bin/env python3
"""
Perla backend daemon — the single brain for ALL surfaces (local hotkey/voice
via perla.sh, and remote phone access via Tailscale).

This replaces the old split between perla.sh (which used to talk to OpenCode
directly and keep its own session file) and perla-companion.py (which only
served the phone). Now there is exactly ONE process holding session state,
so a Tier 1 conversation started from your phone is the same OpenCode
session you continue from the laptop hotkey — and vice versa. Only two
sessions exist, ever: Tier 1 and Tier 2. Not one per surface.

perla.sh is now a thin local client: it captures mic audio, handles hotkey/
dmenu integration, and speaks responses locally — but it calls THIS daemon's
HTTP API instead of talking to OpenCode or Obsidian directly.

Local calls (from perla.sh, on 127.0.0.1) are trusted by virtue of being on
the machine and use a fixed local token. Remote calls (from the phone, over
Tailscale) go through the gate-password -> session-token flow as before.
"""

import base64
import fcntl
import getpass
import json
import os
import random
import re
import shlex
import signal
import subprocess
import tempfile
import time
import uuid
from contextlib import contextmanager
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
import threading

# ---------------------------------------------------------------------------
# Config from environment (set by systemd unit / perla.env)
# ---------------------------------------------------------------------------
PORT = int(os.environ.get("PERLA_COMPANION_PORT", "8443"))
HOST = os.environ.get("PERLA_COMPANION_HOST", "127.0.0.1")
PERLA_NAME = os.environ.get("PERLA_NAME", "Perla")
PERLA_MODEL = os.environ.get("PERLA_MODEL", "opencode/deepseek-v4-flash-free")
PERLA_VOICE = os.environ.get("PERLA_VOICE", "en_US-libritts_r-medium")
PERLA_VAULT = os.environ.get("PERLA_VAULT", os.path.expanduser("~/Documents/Obsidian/PerlaNew"))
PERLA_PERSONA = os.environ.get("PERLA_PERSONA", os.path.expanduser("~/.config/perla/persona.md"))
PERLA_AVATAR = os.environ.get("PERLA_AVATAR", os.path.expanduser("~/.config/perla/profile.jpg"))
PERLA_WHISPER_MODEL = os.environ.get("PERLA_WHISPER_MODEL", "tiny")
PERLA_WHISPER_LANG = os.environ.get("PERLA_WHISPER_LANG", "en")
PERLA_AUDIO_DIR = os.environ.get("PERLA_AUDIO_DIR", os.path.expanduser("~/.local/share/perla-audio"))
PERLA_SCREENSHOT_DIR = os.environ.get("PERLA_SCREENSHOT_DIR", os.path.expanduser("~/.local/share/perla-screenshots"))
PERLA_AUDIO_INPUT = os.environ.get("PERLA_AUDIO_INPUT", "")
SERVER_PORT_T1 = int(os.environ.get("PERLA_SERVER_PORT_T1", "13101"))
SERVER_PORT_T2 = int(os.environ.get("PERLA_SERVER_PORT_T2", "13102"))
ELEVATION_DURATION = int(os.environ.get("PERLA_ELEVATION_DURATION", "300"))  # 5 minutes
GATE_PASSWORD = os.environ.get("PERLA_GATE_PASSWORD", "")

SECRETS_DIR = os.path.expanduser("~/.config/perla/secrets")


def read_secret(name):
    """Read a sops-decrypted secret file."""
    path = os.path.join(SECRETS_DIR, name)
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except FileNotFoundError:
        print(f"WARNING: secret not found at {path}", flush=True)
        return None


def _load_tokens():
    """Read (or re-read) secret tokens from disk. Called at startup and on SIGHUP."""
    global LOCAL_TOKEN, ELEVATE_TOKEN
    ELEVATE_TOKEN = read_secret("elevate-token")
    # Fixed local token so perla.sh (running as the same user, on 127.0.0.1)
    # doesn't have to go through the gate-password flow meant for remote/phone
    # access. This never leaves the machine and is not the same secret as
    # ELEVATE_TOKEN or the phone gate password.
    LOCAL_TOKEN = read_secret("local-token") or "local-only-no-remote-exposure"
    print(f"Tokens loaded (LOCAL_TOKEN={'set' if LOCAL_TOKEN != 'local-only-no-remote-exposure' else 'fallback'})", flush=True)


_load_tokens()
signal.signal(signal.SIGHUP, lambda *_: _load_tokens())


# ---------------------------------------------------------------------------
# Session token store (server-issued short-lived tokens, for REMOTE callers)
# ---------------------------------------------------------------------------
SESSION_TTL = int(os.environ.get("PERLA_SESSION_TTL", "86400"))  # 24 hours


class SessionTokenStore:
    """Manages short-lived session tokens issued after gate authentication."""

    def __init__(self):
        self._tokens = {}
        self._elevated = set()
        self._elevation_expiry = {}
        self._lock = threading.Lock()

    def create(self):
        token = uuid.uuid4().hex
        with self._lock:
            self._tokens[token] = time.time() + SESSION_TTL
        return token

    def validate(self, token):
        if token == LOCAL_TOKEN:
            return True
        with self._lock:
            expiry = self._tokens.get(token)
            if expiry is None:
                return False
            if time.time() > expiry:
                del self._tokens[token]
                self._elevated.discard(token)
                self._elevation_expiry.pop(token, None)
                return False
            return True

    def elevate(self, token):
        with self._lock:
            if token not in self._tokens:
                return False
            self._elevated.add(token)
            self._elevation_expiry[token] = time.time() + ELEVATION_DURATION
            return True

    def is_elevated(self, token):
        with self._lock:
            if token not in self._elevated:
                return False
            expiry = self._elevation_expiry.get(token, 0)
            if time.time() > expiry:
                self._elevated.discard(token)
                self._elevation_expiry.pop(token, None)
                return False
            return True

    def elevation_remaining(self, token):
        with self._lock:
            expiry = self._elevation_expiry.get(token, 0)
            return max(0, int(expiry - time.time()))


session_tokens = SessionTokenStore()


# ---------------------------------------------------------------------------
# OpenCode session management — THE unification point.
# Exactly one session per tier, shared by every surface (local + remote).
# ---------------------------------------------------------------------------
class SessionManager:
    def __init__(self):
        self._sessions = {}         # tier -> session_id
        self._persona_injected = set()
        self._lock = threading.Lock()

    def _server_port(self, tier):
        return SERVER_PORT_T1 if tier == 1 else SERVER_PORT_T2

    def _server_alive(self, tier):
        port = self._server_port(tier)
        try:
            result = subprocess.run(
                ["curl", "-sf", "--connect-timeout", "2", "-m", "3",
                 f"http://127.0.0.1:{port}/global/health"],
                capture_output=True, timeout=5
            )
            return result.returncode == 0
        except Exception:
            return False

    def _start_server(self, tier):
        port = self._server_port(tier)
        print(f"Starting OpenCode server (Tier {tier}, port {port})...", flush=True)
        if tier == 1:
            subprocess.Popen(
                [os.path.expanduser("~/.local/bin/perla-t1-server")],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True
            )
        else:
            # Tier 2 = full mode, from its own isolated config dir
            # (perla-t2-server provisions it with opencode-t2.json), exactly
            # like Tier 1 — never the user's interactive opencode config.
            subprocess.Popen(
                [os.path.expanduser("~/.local/bin/perla-t2-server"), str(port)],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True
            )
        for i in range(15):
            time.sleep(1)
            if self._server_alive(tier):
                print(f"Tier {tier} server ready.", flush=True)
                return True
        print(f"WARNING: Tier {tier} server did not start in time.", flush=True)
        return False

    def get_session(self, tier):
        with self._lock:
            if tier in self._sessions:
                sid = self._sessions[tier]
                if self._session_alive(tier, sid):
                    return sid
            sid = self._create_session(tier)
            self._sessions[tier] = sid
            self._persona_injected.discard(tier)
            return sid

    def _session_alive(self, tier, sid):
        port = self._server_port(tier)
        try:
            result = subprocess.run(
                ["curl", "-sf", "--connect-timeout", "3", "-m", "5",
                 f"http://127.0.0.1:{port}/session/{sid}"],
                capture_output=True, timeout=10
            )
            return result.returncode == 0
        except Exception:
            return False

    def _create_session(self, tier):
        port = self._server_port(tier)
        if not self._server_alive(tier):
            if not self._start_server(tier):
                return None
        try:
            result = subprocess.run(
                ["curl", "-sf", "--connect-timeout", "3", "-m", "10",
                 "-X", "POST", f"http://127.0.0.1:{port}/session",
                 "-H", "Content-Type: application/json",
                 "-d", '{"title":"perla"}'],
                capture_output=True, text=True, timeout=15
            )
            data = json.loads(result.stdout)
            return data["id"]
        except Exception as e:
            print(f"ERROR: failed to create session (tier {tier}): {e}", flush=True)
            return None

    def should_inject_persona(self, tier):
        with self._lock:
            return tier not in self._persona_injected

    def mark_persona_injected(self, tier):
        with self._lock:
            self._persona_injected.add(tier)


session_mgr = SessionManager()


# ---------------------------------------------------------------------------
# Tier 0 — direct dispatch, bypasses the LLM entirely.
# Moved here (from perla.sh) so BOTH local and remote callers get the
# shortcut, and so it can run before any OpenCode call regardless of
# which surface the request came from.
# ---------------------------------------------------------------------------
def get_screen_lock_state():
    """Determine whether the screen is currently locked, using
    systemd-logind's LockedHint — the same mechanism every lock path goes
    through (Noctalia's lock keybind, idle timeout, or a manual
    `loginctl lock-session`), regardless of which triggered it.

    Returns "locked", "unlocked", or "unknown" (fail-safe: unknown is
    treated as locked by the caller, since a false negative here would
    mean silently exposing a screenshot of a locked or suspended machine).

    Runs `loginctl list-sessions` first rather than relying on
    $XDG_SESSION_ID, since perla-companion runs as a systemd --user
    service and isn't guaranteed to inherit that variable the way an
    interactive login shell would.
    """
    try:
        whoami = subprocess.run(
            ["whoami"], capture_output=True, text=True, timeout=5
        ).stdout.strip()
        if not whoami:
            return "unknown"

        sessions = subprocess.run(
            ["loginctl", "list-sessions", "--no-legend"],
            capture_output=True, text=True, timeout=5
        )
        if sessions.returncode != 0:
            return "unknown"

        session_ids = []
        for line in sessions.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[2] == whoami:
                session_ids.append(parts[0])

        if not session_ids:
            return "unknown"

        # Only the ACTIVE session's LockedHint matters when we can identify
        # it. Checking every session for this user unconditionally (the old
        # behavior) produced false positives whenever a stale/background
        # session (a leftover display-manager session, a spare TTY, etc.)
        # happened to carry LockedHint=yes while the real foreground session
        # was unlocked.
        #
        # "Active" isn't populated consistently across all compositor/login
        # setups (some manually-launched Wayland sessions outside a display
        # manager don't set it the way GNOME/logind expects), so this also
        # accepts State=active as an equivalent signal, and only degrades to
        # the old any-session check as a last resort — not straight to
        # "unknown" — since on single-session desktops (the common case)
        # that old check was already correct.
        active_results = []  # (locked_hint, is_active) per session, for fallback
        saw_active_session = False
        for sid in session_ids:
            # Query each property SEPARATELY. `loginctl show-session` with
            # multiple -p flags and --value prints the values sorted
            # alphabetically by property name (Active, LockedHint, State) —
            # NOT in the order requested — so parsing one combined call by
            # position silently swapped the fields and mis-detected an
            # unlocked screen as locked. Individual -p --value calls are
            # unambiguous.
            locked_hint = subprocess.run(
                ["loginctl", "show-session", sid, "-p", "LockedHint", "--value"],
                capture_output=True, text=True, timeout=5
            ).stdout.strip()
            active_prop = subprocess.run(
                ["loginctl", "show-session", sid, "-p", "Active", "--value"],
                capture_output=True, text=True, timeout=5
            ).stdout.strip()
            state_prop = subprocess.run(
                ["loginctl", "show-session", sid, "-p", "State", "--value"],
                capture_output=True, text=True, timeout=5
            ).stdout.strip()
            is_active = active_prop == "yes" or state_prop == "active"
            active_results.append((locked_hint == "yes", is_active))
            if not is_active:
                continue
            saw_active_session = True
            if locked_hint == "yes":
                return "locked"

        if saw_active_session:
            return "unlocked"

        # Couldn't positively identify an active session on this setup —
        # fall back to: locked if ANY session for this user reports
        # LockedHint=yes, unlocked otherwise. Less precise than the
        # active-session check above, but still better than an automatic
        # "unknown" refusal on setups where Active/State never resolve.
        if any(locked_hint for locked_hint, _ in active_results):
            return "locked"
        if active_results:
            return "unlocked"

        return "unknown"
    except Exception as e:
        print(f"WARNING: lock state check failed: {e}", flush=True)
        return "unknown"


def capture_screenshot():
    """Take a full-screen screenshot via grim, after confirming the
    session isn't locked or (as a side effect of the check above)
    unreachable. Returns (path, error) — path is None on failure, error
    is a short user-facing string explaining why.
    """
    lock_state = get_screen_lock_state()
    if lock_state in ("locked", "unknown"):
        return None, (
            "Can't grab a screenshot right now — the screen's locked."
            if lock_state == "locked"
            else "Can't confirm the screen isn't locked, so I'm not grabbing a screenshot."
        )

    os.makedirs(PERLA_SCREENSHOT_DIR, exist_ok=True)
    shot_id = str(uuid.uuid4())
    path = os.path.join(PERLA_SCREENSHOT_DIR, f"{shot_id}.png")

    try:
        result = subprocess.run(
            ["grim", path], capture_output=True, timeout=10
        )
        if result.returncode != 0 or not os.path.exists(path):
            stderr = result.stderr.decode(errors="replace").strip()
            print(f"ERROR: grim failed: {stderr}", flush=True)
            return None, "Couldn't capture the screen — grim failed."
        return path, None
    except FileNotFoundError:
        return None, "grim isn't installed — can't capture the screen."
    except subprocess.TimeoutExpired:
        return None, "Screen capture timed out."
    except Exception as e:
        print(f"ERROR: capture_screenshot failed: {e}", flush=True)
        return None, "Something went wrong capturing the screen."


# ---------------------------------------------------------------------------
# System actions — the fixed allowlist the system_action MCP tool can
# trigger. There is deliberately NO keyword/phrase matching anywhere here:
# an action only ever runs because the model called the tool with an
# explicit action name, so nothing in the spoken/texted message can match
# accidentally. (The old tier0 pre-LLM dispatcher fired on substrings —
# "block" locked the screen, "commute" muted audio, "sleep well" suspended
# the machine.) Execution happens in this daemon, not in the MCP server, so
# it reuses the user-session environment the daemon already runs in
# (Wayland/Noctalia bus, PipeWire, user systemd bus).
# ---------------------------------------------------------------------------
SYSTEM_ACTIONS = ("lock", "shutdown", "restart", "suspend", "mute", "unmute",
                  "open_app", "open_folder")

# Normalized app name -> (launch args, stable systemd-run unit name).
# "unlock" is deliberately absent from the allowlist. This map is the fast
# path; open_app ALSO resolves any installed app from its .desktop file
# (see resolve_app_target below), so the model is never limited to these.
APP_LAUNCH = {
    "firefox": (["firefox"], "perla-firefox"),
    "browser": (["firefox"], "perla-firefox"),
    "terminal": (["kitty"], "perla-terminal"),
    "kitty": (["kitty"], "perla-terminal"),
    "code": (["codium"], "perla-code"),
    "codium": (["codium"], "perla-code"),
    "editor": (["codium"], "perla-code"),
}
APP_LABELS = "firefox (browser), terminal, code (editor) — or any installed app by name"


def run_detached(cmd_list, unit):
    subprocess.Popen(
        ["systemd-run", "--user", f"--unit={unit}"] + cmd_list,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


PERLA_COMPANION_UNIT = os.environ.get("PERLA_COMPANION_UNIT", "perla-companion.service")


def restart_self_delayed(delay_seconds=1.0):
    """Restart the perla-companion systemd --user service from a background
    thread, after a short delay. The delay matters: this is called from
    inside an HTTP request handler answering /api/internal/restart, and the
    HTTP response for that request must actually reach the client before
    systemctl kills this same process — restarting synchronously in the
    handler would cut the connection before the client ever sees a reply.
    `systemctl --user restart` on the unit currently running this process is
    safe to call from within that same process: systemd stops the old cgroup
    and starts a fresh one: it does not require the caller to survive.
    """
    def _do_restart():
        time.sleep(delay_seconds)
        try:
            subprocess.Popen(
                ["systemctl", "--user", "restart", PERLA_COMPANION_UNIT],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception as e:
            print(f"ERROR: failed to trigger companion restart: {e}", flush=True)

    threading.Thread(target=_do_restart, daemon=True).start()


# --- Desktop-file resolution for open_app ----------------------------------
# open_app is not limited to the alias map: ANY installed app can be opened
# by name. The resolver reads the standard applications dirs, so anything
# the user installed shows up automatically. It still never passes free-form
# input to a shell — it only ever runs the Exec line from an installed
# .desktop file, detached (setsid-ish via systemd-run), same as the aliases.
#
# NixOS does not populate /usr/share/applications (no FHS /usr merge by
# default) — that's why those two paths are nearly always empty here, and
# why open_app previously failed to resolve ANY app, not just uncommon
# ones. On NixOS, .desktop files instead live under two profile locations:
#   - home-manager packages (home.packages): symlinked into the user's Nix
#     profile — /etc/profiles/per-user/<user>/share/applications with
#     home-manager's useUserPackages, or ~/.nix-profile/share/applications
#     / ~/.local/state/nix/profile/share/applications otherwise, depending
#     on which profile mechanism is active.
#   - environment.systemPackages: symlinked into the activated system
#     profile at /run/current-system/sw/share/applications.
# All of these are included below; ~/.local and /usr paths are kept too as
# harmless fallbacks (e.g. non-NixOS testing, or a future FHS-compat env) —
# scan_desktop_apps() already skips any directory that doesn't exist.
DESKTOP_SCAN_DIRS = (
    # Home-manager profile (per-user activation, useUserPackages = true)
    f"/etc/profiles/per-user/{getpass.getuser()}/share/applications",
    # Home-manager profile (classic ~/.nix-profile symlink)
    os.path.expanduser("~/.nix-profile/share/applications"),
    # Home-manager profile (newer `nix profile` state directory)
    os.path.expanduser("~/.local/state/nix/profile/share/applications"),
    # System-wide packages (environment.systemPackages), current generation
    "/run/current-system/sw/share/applications",
    # Non-NixOS / FHS fallbacks — harmless if absent
    os.path.expanduser("~/.local/share/applications"),
    "/usr/local/share/applications",
    "/usr/share/applications",
)

_FIELD_CODE_RE = re.compile(r"%[A-Za-z]")


def desktop_dir_override():
    env = os.environ.get("PERLA_DESKTOP_DIRS", "").strip()
    return tuple(d for d in env.split(":") if d) if env else None


def field_strip(exec_line):
    """Remove .desktop field codes (%U, %F, %f, …) and collapse %% -> %,
    leaving a bare launchable command line."""
    out = re.sub(r"%%", "\0", exec_line)
    out = _FIELD_CODE_RE.sub("", out)
    return out.replace("\0", "%")


def desktop_unit(label):
    """Stable systemd-run unit name derived from an arbitrary app label."""
    slug = re.sub(r"[^a-z0-9]+", "-", label.lower()).strip("-")
    return "perla-app-" + (slug[:50] or "app")


def parse_desktop_file(path):
    """Minimal .desktop parser. Returns {name, exec, type, nodisplay,
    hidden} from the [Desktop Entry] section (localized Name keys are
    ignored — the plain Name wins), or None if malformed/lacking a Name."""
    fields = {}
    in_desktop_entry = False
    try:
        with open(path, "r", errors="replace") as f:
            for line in f:
                line = line.rstrip("\r\n")
                if not line:
                    continue
                if line.startswith("["):
                    in_desktop_entry = line.strip() == "[Desktop Entry]"
                    continue
                if not in_desktop_entry or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                value = value.strip()
                if key == "Name":
                    fields["name"] = value
                elif key == "Exec":
                    fields["exec"] = value
                elif key == "Type":
                    fields["type"] = value
                elif key == "NoDisplay":
                    fields["nodisplay"] = value.lower() == "true"
                elif key == "Hidden":
                    fields["hidden"] = value.lower() == "true"
    except OSError:
        return None
    if not fields.get("name"):
        return None
    return fields


def scan_desktop_apps():
    """Map lowercased app Name -> (display Name, raw Exec) for every
    installed .desktop launcher: Type=Application (absent defaults to
    Application per the spec), not Hidden, not NoDisplay, with an Exec.
    PERLA_DESKTOP_DIRS (colon-separated; replaces the standard dirs
    entirely) exists only for tests."""
    dirs = desktop_dir_override() or DESKTOP_SCAN_DIRS
    apps = {}
    for directory in dirs:
        try:
            entries = os.listdir(directory)
        except OSError:
            continue
        for filename in entries:
            if not filename.endswith(".desktop"):
                continue
            info = parse_desktop_file(os.path.join(directory, filename))
            if not info:
                continue
            if (info.get("type", "Application") != "Application"
                    or info.get("nodisplay") or info.get("hidden")):
                continue
            exec_line = (info.get("exec") or "").strip()
            if not exec_line:
                continue
            apps[info["name"].strip().lower()] = (info["name"].strip(), exec_line)
    return apps


def resolve_app_target(target):
    """Resolve an app name to a detached launch — (display label, command
    list, systemd-run unit), or None if nothing matches. Known aliases win
    instantly; otherwise installed apps are matched by exact Name, then
    exact Exec basename ("vlc" -> its player), then best case-insensitive
    substring against Name (shortest label wins, so "spot" -> Spotify).
    The returned command is the desktop Exec with field codes stripped and
    tokenized — no shell is ever involved."""
    query = (target or "").strip().lower()
    if not query:
        return None
    if query in APP_LAUNCH:
        cmd, unit = APP_LAUNCH[query]
        return (query, cmd, unit)
    apps = scan_desktop_apps()
    match = None
    if query in apps:
        match = apps[query]
    if match is None:
        for key, (label, exec_line) in apps.items():
            if os.path.basename(exec_line.split(" ", 1)[0]).lower() == query:
                match = (label, exec_line)
                break
    if match is None:
        best_key, best = "", None
        for key, (label, exec_line) in apps.items():
            if query in key or key in query:
                if best is None or len(key) < len(best_key):
                    best_key, best = key, (label, exec_line)
        if best is not None:
            match = best
    if match is None:
        return None
    label, exec_line = match
    cmd = shlex.split(field_strip(exec_line))
    if not cmd:
        return None
    return (label, cmd, desktop_unit(label))


def execute_system_action(action, target=None):
    """Execute one allowlisted system action. Returns (ok, message) — errors
    are phrased so the model can relay them to the user as-is. `target` is
    only meaningful for open_app / open_folder."""
    action = (action or "").strip().lower()
    if action not in SYSTEM_ACTIONS:
        return False, (
            f"'{action}' isn't a system action I'm allowed to run. I can: "
            "lock, shutdown, restart, suspend, mute, unmute, "
            f"open_app ({APP_LABELS}), open_folder."
        )

    def run(cmd, timeout=5):
        subprocess.run(cmd, timeout=timeout)

    try:
        if action == "lock":
            run(["noctalia", "msg", "session", "lock"])
            return True, "Locked."
        if action == "unmute":
            run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"])
            return True, "Unmuted."
        if action == "mute":
            run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1"])
            return True, "Muted."
        if action == "suspend":
            run(["systemctl", "suspend"])
            return True, "Suspending."
        if action == "shutdown":
            run(["systemctl", "poweroff"])
            return True, "Shutting down."
        if action == "restart":
            run(["systemctl", "reboot"])
            return True, "Restarting."
        if action == "open_app":
            name = (target or "").strip().lower()
            if not name:
                return False, "open_app needs an app name."
            resolved = resolve_app_target(name)
            if resolved is None:
                return False, (
                    f"I couldn't find an app called '{name}' on this system. "
                    f"I can open: {APP_LABELS}."
                )
            label, cmd, unit = resolved
            run_detached(cmd, unit)
            return True, f"Opening {label}."
        if action == "open_folder":
            path = (target or "").strip()
            if not path:
                return False, "open_folder needs a folder path."
            run_detached(["xdg-open", path], "perla-open-folder")
            return True, f"Opening {path}."
    except Exception as e:
        print(f"ERROR: system action '{action}' failed: {e}", flush=True)
        return False, f"Couldn't run '{action}' — try again."

    return False, f"Couldn't run '{action}'."


# ---------------------------------------------------------------------------
# Core functions
# ---------------------------------------------------------------------------
def read_persona():
    try:
        with open(PERLA_PERSONA, "r") as f:
            return f.read()
    except FileNotFoundError:
        return f"IMPORTANT — Your name is {PERLA_NAME}. You are NOT opencode."


def model_part():
    provider, model = PERLA_MODEL.split("/", 1)
    return {"providerID": provider, "modelID": model}


MAX_IMAGE_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_IMAGES_PER_MESSAGE = 6  # MiMo-V2.5 has no documented hard per-request
# image cap — images are tokenized into the 1M-token context window like
# any other input, so the real constraint is context budget, not a fixed
# count. 6 is a practical UI/UX ceiling (payload size, upload time,
# review time before sending), not a model limitation.
_UPLOAD_MIME_EXT = {"image/png": ".png", "image/jpeg": ".jpg"}


def decode_upload_image(data_url, filename=None):
    """Decode a client-supplied image data URL into a temp file in
    PERLA_SCREENSHOT_DIR. Returns (path, error); path is None on error.
    The caller feeds path to call_opencode and then deletes it — an upload
    only ever lives on disk long enough to be sent. The 15-minute screenshot
    sweep is a safety net if a path ever leaks.
    """
    if not isinstance(data_url, str) or not data_url.startswith("data:"):
        return None, "image must be a base64 data: URL"
    m = re.match(r"^data:([^;,]+);base64,(.*)$", data_url, re.S)
    if not m:
        return None, "image must be base64-encoded"
    mime, b64 = m.group(1), m.group(2).strip()
    if mime not in _UPLOAD_MIME_EXT:
        return None, f"unsupported image type: {mime} (use png or jpeg)"
    try:
        raw = base64.b64decode(b64, validate=True)
    except (ValueError, TypeError):
        return None, "image data is not valid base64"
    if len(raw) > MAX_IMAGE_UPLOAD_BYTES:
        return None, "image too large (max 10MB)"
    os.makedirs(PERLA_SCREENSHOT_DIR, exist_ok=True)
    path = os.path.join(
        PERLA_SCREENSHOT_DIR,
        f"upload-{uuid.uuid4().hex}{_UPLOAD_MIME_EXT[mime]}",
    )
    with open(path, "wb") as f:
        f.write(raw)
    return path, None


def decode_upload_images(data_urls):
    """Plural form of decode_upload_image for multi-image messages.
    Returns (paths, error). On any single failure, every path already
    decoded earlier in the batch is cleaned up and (None, error) is
    returned — an all-or-nothing batch is simpler to reason about for
    the caller than a partial list with holes."""
    if not isinstance(data_urls, list) or not data_urls:
        return None, "images must be a non-empty list"
    if len(data_urls) > MAX_IMAGES_PER_MESSAGE:
        return None, f"too many images (max {MAX_IMAGES_PER_MESSAGE} per message)"
    paths = []
    for data_url in data_urls:
        path, error = decode_upload_image(data_url)
        if error:
            for p in paths:
                try:
                    os.unlink(p)
                except OSError:
                    pass
            return None, error
        paths.append(path)
    return paths, None


def call_opencode(sid, port, text, tier, image_path=None):
    """Send a message to OpenCode. If image_path is given, attaches it as
    one or more file parts alongside the text part — mimo-v2.5-free (the
    deployed model per perla-config.nix) accepts multi-image input
    natively; the model tokenizes each image into its context window
    like any other input, so there's no fixed per-message image count to
    enforce here beyond MAX_IMAGES_PER_MESSAGE (checked earlier, at
    upload time). image_path may be a single path string (backward
    compatible with existing callers) or a list of paths. The request
    body is piped over stdin rather than passed as a curl argv string,
    since inlined base64 images can be large enough to risk hitting OS
    argument-length limits as a single -d argument.
    """
    if session_mgr.should_inject_persona(tier):
        persona = read_persona()
        text = (
            f"ATTENTION — Read and follow these rules for your identity and behavior:\n\n"
            f"{persona}\n\n"
            f"Now respond to the user:\n\n"
            f"{text}"
        )
        session_mgr.mark_persona_injected(tier)

    parts = [{"type": "text", "text": text}]

    if image_path:
        image_paths = [image_path] if isinstance(image_path, str) else list(image_path)
        for path in image_paths:
            try:
                with open(path, "rb") as f:
                    encoded = base64.b64encode(f.read()).decode("ascii")
                ext = os.path.splitext(path)[1].lower()
                mime = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}.get(ext, "image/png")
                parts.append({
                    "type": "file",
                    "mime": mime,
                    "filename": os.path.basename(path),
                    "url": f"data:{mime};base64,{encoded}",
                })
            except Exception as e:
                print(f"ERROR: failed to read image for OpenCode: {e}", flush=True)
                # Skip this one image rather than failing the whole
                # request — Perla will just not have that particular
                # image to look at, but still sees the rest plus the text.

    body = json.dumps({
        "parts": parts,
        "model": model_part()
    })

    try:
        result = subprocess.run(
            ["curl", "-sf", "--connect-timeout", "5", "-m", "300",
             "-X", "POST", f"http://127.0.0.1:{port}/session/{sid}/message",
             "-H", "Content-Type: application/json",
             "-d", "@-"],
            input=body, capture_output=True, text=True, timeout=310
        )
        if result.returncode != 0:
            return "OpenCode server error — try again.", False, False, False

        data = json.loads(result.stdout)
        response_text = " ".join(
            p.get("text", "") for p in data.get("parts", []) if p.get("type") == "text"
        )
        tool_used = any(p.get("type") == "tool" for p in data.get("parts", []))

        obsidian_writes = {
            "obsidian_write_note", "obsidian_patch_note", "obsidian_append_to_note",
            "obsidian_replace_in_note", "obsidian_manage_tags", "obsidian_delete_note",
            "obsidian_manage_frontmatter",
            "create_reminder", "cancel_reminder",
        }
        obsidian_write = any(
            p.get("tool", "") in obsidian_writes
            for p in data.get("parts", []) if p.get("type") == "tool"
        )

        # The view_screen MCP tool returns the screenshot to the MODEL as an
        # image part, but that image is consumed inside the OpenCode session
        # and never reaches the user. When the model used it, signal the
        # caller (process_message) so it captures a matching screenshot and
        # ships it to the UI, so the user actually SEES the picture — not
        # just perla's text description of it. OpenCode names MCP tools as
        # "<server>_<tool>", so the view-screen server's tool shows up as
        # "view-screen_view_screen" — match on the ending to cover that and
        # any bare "view_screen". Matched case-insensitively and against
        # both "tool" and "toolName" (seen used interchangeably across
        # OpenCode server versions) since a naming-scheme mismatch here
        # silently drops the image with no error anywhere in the pipeline.
        tool_parts = [p for p in data.get("parts", []) if p.get("type") == "tool"]
        tool_names = [p.get("tool") or p.get("toolName") or "" for p in tool_parts]
        view_screen_used = any(
            name.lower().endswith("view_screen") for name in tool_names
        )

        return response_text or "(no response)", tool_used, obsidian_write, view_screen_used

    except subprocess.TimeoutExpired:
        return "Request timed out — the AI took too long to respond.", False, False, False
    except Exception as e:
        print(f"ERROR: call_opencode failed: {e}", flush=True)
        return "Failed to reach Perla's brain.", False, False, False


def generate_tts(text):
    """Generate TTS audio file, return path or None."""
    voice_dir = os.path.expanduser("~/.local/share/piper-tts/voices")
    voice_file = os.path.join(voice_dir, f"{PERLA_VOICE}.onnx")
    if not os.path.exists(voice_file):
        print(f"WARNING: voice file not found at {voice_file}", flush=True)
        return None

    os.makedirs(PERLA_AUDIO_DIR, exist_ok=True)
    audio_id = str(uuid.uuid4())
    audio_path = os.path.join(PERLA_AUDIO_DIR, f"{audio_id}.mp3")

    try:
        proc = subprocess.run(
            ["bash", "-c",
             f"echo {shlex.quote(text)} | "
             f"piper --model {shlex.quote(voice_file)} --output-raw --length-scale 1.1 | "
             f"ffmpeg -y -f s16le -ar 22050 -ac 1 -i - {shlex.quote(audio_path)} 2>/dev/null"],
            capture_output=True, timeout=30
        )
        if proc.returncode == 0 and os.path.exists(audio_path):
            return audio_path
    except Exception as e:
        print(f"ERROR: TTS generation failed: {e}", flush=True)
    return None


def speak_locally(text):
    """Play TTS directly through local speakers — used for local hotkey/
    voice callers so audio doesn't need to round-trip as a file URL."""
    voice_dir = os.path.expanduser("~/.local/share/piper-tts/voices")
    voice_file = os.path.join(voice_dir, f"{PERLA_VOICE}.onnx")
    if not os.path.exists(voice_file):
        print(f"WARNING: voice file not found at {voice_file}", flush=True)
        return False
    try:
        subprocess.run(
            ["bash", "-c",
             f"echo {shlex.quote(text)} | "
             f"piper --model {shlex.quote(voice_file)} --output-raw --length-scale 1.1 | "
             f"pw-play --rate=22050 --channels=1 --format=s16 --raw -"],
            timeout=60
        )
        return True
    except Exception as e:
        print(f"ERROR: local speak failed: {e}", flush=True)
        return False


def transcribe_audio(audio_path):
    """Transcribe audio file using whisper-cli. Used for BOTH local voice
    (perla.sh posts captured audio here) and phone voice — STT now lives
    in exactly one place instead of being duplicated in perla.sh."""
    model_dir = os.path.expanduser("~/.local/share/whisper-cpp/models")
    model_file = os.path.join(model_dir, f"ggml-{PERLA_WHISPER_MODEL}.bin")
    os.makedirs(model_dir, exist_ok=True)

    if not os.path.exists(model_file):
        print(f"Downloading whisper model {PERLA_WHISPER_MODEL}...", flush=True)
        subprocess.run(
            ["curl", "-L",
             f"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{PERLA_WHISPER_MODEL}.bin",
             "-o", model_file],
            timeout=120
        )

    try:
        result = subprocess.run(
            ["whisper-cli", "--model", model_file, "--file", audio_path,
             "--language", PERLA_WHISPER_LANG],
            capture_output=True, text=True, timeout=60
        )
        return result.stdout.strip() or ""
    except Exception as e:
        print(f"ERROR: transcription failed: {e}", flush=True)
        return ""


def log_request(input_text, response, tier, tool_used, source="remote"):
    """Log to Obsidian vault. `source` distinguishes local vs remote in the
    log so you can tell which surface a conversation came from."""
    tier_label = f"Tier {tier} ({source})"
    if tool_used:
        log_dir = os.path.join(PERLA_VAULT, "Command Log")
    else:
        log_dir = os.path.join(PERLA_VAULT, "Conversations")

    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, f"{datetime.now().strftime('%Y-%m-%d')}.md")

    try:
        with open(log_file, "a") as f:
            f.write(f"## {datetime.now().strftime('%H:%M')} — {tier_label}\n")
            f.write(f"- **Input:** {input_text}\n")
            f.write(f"- **Response:** {response}\n\n")
    except Exception as e:
        print(f"ERROR: logging failed: {e}", flush=True)


HISTORY_HEADER_RE = re.compile(
    r"^##\s+(\d{2}:\d{2})\s+—\s+Tier\s+(\d+)\s*\(([^)]*)\)\s*$"
)
HISTORY_INPUT_RE = re.compile(r"^-\s+\*\*Input:\*\*\s?(.*)$")
HISTORY_RESPONSE_RE = re.compile(r"^-\s+\*\*Response:\*\*\s?(.*)$")


def list_history_days():
    """Union of dates that have a log file in either Conversations/ or
    Command Log/, newest first. Filenames are expected as YYYY-MM-DD.md."""
    date_re = re.compile(r"^(\d{4}-\d{2}-\d{2})\.md$")
    days = set()
    for folder in ("Conversations", "Command Log"):
        dir_path = os.path.join(PERLA_VAULT, folder)
        try:
            for fname in os.listdir(dir_path):
                m = date_re.match(fname)
                if m:
                    days.add(m.group(1))
        except FileNotFoundError:
            continue
    return sorted(days, reverse=True)


def _parse_log_file(path):
    """Parse a single day's log file (Conversations or Command Log schema)
    into a list of {time, tier, source, input, response} dicts. Tolerant
    of malformed/legacy lines — skips anything that doesn't match."""
    entries = []
    try:
        with open(path, "r") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        return entries

    current = None
    pending_field = None  # "input" or "response", for multi-line continuation
    pending_blanks = 0    # blank lines inside the block (paragraph breaks)

    def flush():
        if current is not None and (current["input"] or current["response"]):
            entries.append(current)

    for line in lines:
        header_m = HISTORY_HEADER_RE.match(line)
        if header_m:
            flush()
            time_str, tier_str, source = header_m.groups()
            current = {
                "time": time_str,
                "tier": int(tier_str),
                "source": source.strip(),
                "input": "",
                "response": "",
            }
            pending_field = None
            pending_blanks = 0
            continue

        if current is None:
            continue

        input_m = HISTORY_INPUT_RE.match(line)
        if input_m:
            current["input"] = input_m.group(1)
            pending_field = "input"
            pending_blanks = 0
            continue

        response_m = HISTORY_RESPONSE_RE.match(line)
        if response_m:
            current["response"] = response_m.group(1)
            pending_field = "response"
            pending_blanks = 0
            continue

        if line.strip() == "":
            # Blank lines inside a multi-line block are paragraph breaks,
            # NOT the end of the block. Buffer them and only commit if the
            # block keeps going; a structural line (header/Input/Response)
            # or EOF drops the buffer.
            if pending_field in ("input", "response"):
                pending_blanks += 1
            continue

        # Continuation line of a multi-line input/response block.
        if pending_field in ("input", "response"):
            if pending_blanks:
                current[pending_field] += "\n" * pending_blanks
                pending_blanks = 0
            current[pending_field] = (current[pending_field] + "\n" + line).rstrip()

    flush()
    return entries


def get_history_for_day(date_str):
    """Merge Conversations/{date}.md and Command Log/{date}.md, sorted by
    time. `date_str` must already be validated as YYYY-MM-DD by the caller."""
    entries = []
    for folder in ("Conversations", "Command Log"):
        path = os.path.join(PERLA_VAULT, folder, f"{date_str}.md")
        entries.extend(_parse_log_file(path))

    entries.sort(key=lambda e: e["time"])
    return entries


# ---------------------------------------------------------------------------
# Reminders — view-only read of Reminders.md for the companion UI.
# Same file/schema perla-reminder-check.py already owns; this is read-only.
# ---------------------------------------------------------------------------
REMINDER_PENDING_RE = re.compile(
    r"^-\s\[\s\]\s([0-9T:-]+)\s\|\sid:([a-f0-9]+)"
    r"(?:\s\|\srepeat:([a-zA-Z0-9:]+))?"
    r"\s\|\s(.*)$"
)
REMINDER_DUE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$")
REMINDER_DONE_RE = re.compile(
    r"^-\s\[x\]\s([0-9T:-]+)\s\|\sid:([a-f0-9]+)\s\|\s(.*?)\s\(delivered\s([0-9T:-]+)(,\smissed)?\)\s*$"
)


def get_reminders():
    """Parse Reminders.md into three buckets: pending (not yet due, or due
    but not yet processed by the checker), missed (delivered late), and
    delivered (delivered on time). Sorted by due time within each bucket."""
    reminders_file = os.path.join(PERLA_VAULT, "Reminders.md")
    pending, missed, delivered = [], [], []

    try:
        with open(reminders_file, "r") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        return {"pending": [], "missed": [], "delivered": []}

    now_iso = datetime.now().isoformat(timespec="minutes")

    for line in lines:
        m = REMINDER_PENDING_RE.match(line)
        if m:
            due, rid, repeat_token, text = m.groups()
            pending.append({
                "id": rid,
                "due": due,
                "repeat": repeat_token,
                "text": text.strip(),
                "overdue": due <= now_iso,
            })
            continue

        m = REMINDER_DONE_RE.match(line)
        if m:
            due, rid, text, delivered_ts, missed_suffix = m.groups()
            entry = {
                "id": rid,
                "due": due,
                "text": text,
                "delivered": delivered_ts,
            }
            if missed_suffix:
                missed.append(entry)
            else:
                delivered.append(entry)
            continue
        # Lines that don't match either pattern (headers, blank lines,
        # malformed entries) are silently skipped — read-only, tolerant.

    pending.sort(key=lambda e: e["due"])
    missed.sort(key=lambda e: e["due"], reverse=True)
    delivered.sort(key=lambda e: e["due"], reverse=True)

    return {"pending": pending, "missed": missed, "delivered": delivered}


# ---------------------------------------------------------------------------
# Reminders — mutations (create/cancel) backing the reminders MCP tool.
# The row format is identical to what the checker writes/reads
# (perla-reminder-check.py validates the same lines with its own regex), and
# get_reminders() above parses exactly the rows these functions produce, so
# the web view and the delivery job keep working with MCP-created reminders.
# A shared flock serializes these mutations against the checker's periodic
# rewrite of the same file.
# ---------------------------------------------------------------------------

# Advisory lock shared with perla-reminder-check.py. Anchored under
# ~/.local/share/perla (matching perla-audio / perla-screenshots) rather than
# XDG_RUNTIME_DIR because the checker runs from a systemd timer whose
# environment may not carry XDG_RUNTIME_DIR — both processes resolve the
# same canonical path for the same user.
REMINDER_FILE_LOCK = os.path.join(
    os.path.expanduser("~/.local/share/perla"), "reminders-file.lock"
)
REPEAT_TOKEN_RE = re.compile(r"^every:(\d+)([hdw])$")
_REPEAT_TOKENS = {"hourly", "daily", "weekly", "monthly", "yearly"}


@contextmanager
def reminder_lock():
    """Hold an exclusive flock across a read-modify-write of Reminders.md so
    daemon mutations and the checker's rewrite never interleave."""
    lock_dir = os.path.dirname(REMINDER_FILE_LOCK)
    os.makedirs(lock_dir, exist_ok=True)
    f = open(REMINDER_FILE_LOCK, "a+")
    try:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(f, fcntl.LOCK_UN)
        f.close()


def _valid_repeat(token):
    """Normalize a repeat token to exactly what the checker understands, or
    return None. Callers ask whether the trimmed/lowercased token is valid;
    an empty value means 'no repeat' (None is also None, meaning one-shot)."""
    if not token:
        return None
    t = token.strip().lower()
    if t in _REPEAT_TOKENS:
        return t
    m = REPEAT_TOKEN_RE.match(t)
    if m and int(m.group(1)) >= 1:
        return t
    return None


def _read_reminders_raw():
    path = os.path.join(PERLA_VAULT, "Reminders.md")
    try:
        with open(path, "r") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def _unique_reminder_id(existing_lines):
    used = {
        m.group(2) for line in existing_lines
        for m in [REMINDER_PENDING_RE.match(line)] if m
    }
    while True:
        rid = "".join(random.choice("0123456789abcdef") for _ in range(4))
        if rid not in used:
            return rid


def _append_reminder(text, due, repeat=None):
    """Create a reminder row. Returns (True, id) on success, or (False,
    human-readable error). Caller (the MCP tool) surfaces the error to the
    model, which passes it back to the user as-is."""
    text = (text or "").strip()
    if not text:
        return False, "Reminder text is empty."
    try:
        datetime.fromisoformat(due)
    except (TypeError, ValueError):
        return False, (
            f"Couldn't parse due '{due}' — expected YYYY-MM-DDTHH:MM "
            "(local time), e.g. 2026-08-30T18:00."
        )
    if not REMINDER_DUE_RE.match((due or "").strip()):
        return False, (
            f"Due must be a full timestamp in YYYY-MM-DDTHH:MM form "
            "(local time), e.g. 2026-08-30T18:00 — got '{due}'."
        )
    repeat_token = _valid_repeat(repeat)
    if repeat and repeat_token is None:
        return False, (
            f"Unknown repeat '{repeat}' — use hourly, daily, weekly, "
            "monthly, yearly, or every:Nh / every:Nd / every:Nw."
        )

    with reminder_lock():
        raw = _read_reminders_raw()
        lines = raw.splitlines()
        rid = _unique_reminder_id(lines)
        segment = f" | repeat:{repeat_token}" if repeat_token else ""
        row = f"- [ ] {due} | id:{rid}{segment} | {text}"
        if not raw:
            raw = "# Reminders\n"
        elif not raw.endswith("\n"):
            raw += "\n"
        path = os.path.join(PERLA_VAULT, "Reminders.md")
        with open(path, "w") as f:
            f.write(raw + row + "\n")
    return True, rid


def _cancel_reminder(rid):
    """Remove a single pending reminder by id. Returns (True, message) on
    success, or (False, human-readable error). Other rows are untouched."""
    rid = (rid or "").strip()
    with reminder_lock():
        lines = _read_reminders_raw().splitlines()
        kept, found = [], False
        for line in lines:
            m = REMINDER_PENDING_RE.match(line)
            if m and m.group(2) == rid:
                found = True
                continue
            kept.append(line)
        if not found:
            return False, f"No pending reminder with id '{rid}'."
        while kept and kept[-1] == "":
            kept.pop()
        content = "\n".join(kept)
        if content:
            content += "\n"
        if not content:
            content = "# Reminders\n"
        path = os.path.join(PERLA_VAULT, "Reminders.md")
        with open(path, "w") as f:
            f.write(content)
    return True, f"Cancelled reminder {rid}."


def log_memory_mismatch(input_text, response, tier, source="remote"):
    log_dir = os.path.join(PERLA_VAULT, "Review")
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, "memory-mismatches.md")
    try:
        with open(log_file, "a") as f:
            f.write(f"## {datetime.now().strftime('%Y-%m-%d %H:%M')} — Tier {tier} ({source})\n")
            f.write(f"- **Input:** {input_text}\n")
            f.write(f"- **Response:** {response}\n\n")
    except Exception as e:
        print(f"ERROR: memory mismatch logging failed: {e}", flush=True)


def is_memory_worthy(text):
    lower = text.lower().replace("'", "")
    keywords = [
        "remember", "prefer", "preference", "task", "note this", "important",
        "store", "save", "record", "reminder", "dont forget", "dont ever forget",
    ]
    return any(k in lower for k in keywords)


def is_destructive(text):
    lower = text.lower()
    destructive_patterns = [
        r"\bdelete\b", r"\brm\b", r"\bremove\b",
        r"\boverwrite\b", r"\bwrite\b.*\bfile\b",
        r"\bsudo\b", r"\bsystemctl\b", r"\breboot\b", r"\bshutdown\b",
        r"\bformat\b", r"\bkill\b", r"\bpkill\b",
    ]
    return any(re.search(p, lower) for p in destructive_patterns)


def is_screen_vision_request(text):
    """Phrases that mean 'look at my screen and tell me about it' — these
    need the LLM (to actually describe/reason about the image), so they go
    to the model with a screenshot attached. Deliberately distinct from the
    screenshot-capture path (view_screen MCP tool), which just returns the
    raw image with no description."""
    lower = text.lower()
    vision_phrases = (
        "what's on my screen", "whats on my screen",
        "what am i looking at", "what is on my screen",
        "describe my screen", "describe what's on my screen",
        "can you see my screen", "look at my screen",
        "what do you see on my screen", "explain what's on my screen",
        "explain whats on my screen", "tell me what's on my screen",
        "tell me whats on my screen", "what's happening on my screen",
    )
    return any(p in lower for p in vision_phrases)


def process_message(message, tier, source, confirm=False, user_image_paths=None):
    """The single entrypoint every surface funnels through: OpenCode, then
    logging. Returns (response_text, tool_used, confirm_required,
    confirm_action, image_path). image_path is None except for two cases —
    a screen-vision request (captured screenshot sent alongside the model's
    description), or when the model used the view_screen MCP tool (whose
    screenshot only reaches the model, so a fresh one is captured to show
    the user). When the user attaches their own image(s)
    (user_image_paths), they win over screen capture, are sent to the model
    instead, and the temp files are removed afterwards. System actions are
    not matched by keywords in the text — the model triggers them
    explicitly via the system_action MCP tool, so there is no accidental
    keyword self-triggering."""

    vision_image_path = None
    if user_image_paths:
        # Explicit attachment(s) take precedence: the user wants those
        # images analyzed, not a fresh screen grab.
        pass
    else:
        # Screen vision — needs the model to actually look at and describe
        # the image, so it goes through the normal OpenCode call below with
        # an image part attached. Available at every tier, same as screenshot
        # capture, since it uses the same lock-safe capture_screenshot() and
        # carries no elevated privilege. (Direct system actions are NOT
        # matched by keywords here — the model triggers them deliberately
        # via the system_action MCP tool.)
        if is_screen_vision_request(message):
            vision_image_path, capture_error = capture_screenshot()
            if capture_error:
                log_request(message, capture_error, tier, False, source=source)
                return capture_error, False, False, None, None

    attach_paths = user_image_paths if user_image_paths else ([vision_image_path] if vision_image_path else None)

    try:
        if tier == 2 and is_destructive(message) and not confirm:
            return (
                "About to execute a potentially destructive action. Confirm?",
                False, True, message, None
            )

        sid = session_mgr.get_session(tier)
        if not sid:
            return "OpenCode server unavailable.", False, False, None, None

        port = SERVER_PORT_T1 if tier == 1 else SERVER_PORT_T2
        response_text, tool_used, obsidian_write, view_screen_used = call_opencode(
            sid, port, message, tier, image_path=attach_paths
        )

        log_request(message, response_text, tier, tool_used, source=source)

        if is_memory_worthy(message) and not obsidian_write:
            log_memory_mismatch(message, response_text, tier, source=source)
            print("WARNING: memory-worthy input with no Obsidian write detected", flush=True)

        # When the model used the view_screen MCP tool, it saw the screenshot
        # but the user didn't — that tool returns the image to the model only,
        # consumed inside the OpenCode session. Capture a matching screenshot
        # so the UI can show the user the actual picture (same serving path as
        # the fixed-phrase vision path below). The model already got its own
        # copy from the MCP tool, so this one is only for display, not re-sent
        # to OpenCode.
        display_image_path = vision_image_path
        if display_image_path is None and view_screen_used and not user_image_paths:
            display_image_path, capture_error = capture_screenshot()
            if capture_error:
                print(f"WARNING: view_screen display capture failed: {capture_error}", flush=True)

        # image_path returned to the caller is the CAPTURED screenshot (which
        # the web UI re-serves via /api/screenshot); user uploads are instead
        # echoed client-side from their data URLs, so nothing to re-serve.
        return response_text, tool_used, False, None, display_image_path
    finally:
        if user_image_paths:
            for p in user_image_paths:
                try:
                    os.unlink(p)
                except OSError:
                    pass


# ---------------------------------------------------------------------------
# HTTP Handler
# ---------------------------------------------------------------------------
class CompanionHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass

    def send_json(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path, content_type):
        try:
            with open(path, "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except FileNotFoundError:
            self.send_error(404)

    def check_auth(self):
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            token = auth[7:]
            if session_tokens.validate(token):
                return True
            if ELEVATE_TOKEN and token == ELEVATE_TOKEN:
                return True
        self.send_json(401, {"error": "unauthorized"})
        return False

    def get_source(self):
        """Local (perla.sh, using LOCAL_TOKEN) vs remote (phone, gated
        session token) — used only for logging/labelling, not permissions."""
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer ") and auth[7:] == LOCAL_TOKEN:
            return "local"
        return "remote"

    def get_effective_tier(self, requested_tier=None):
        """Local callers (perla.sh) may explicitly request a tier — trusted
        outright since they're on 127.0.0.1 with the local token.

        Remote callers (phone/browser) may also request a tier explicitly
        now that the UI has separate Tier 1 / Tier 2 chats:
          - tier 1 is always honored (dropping privilege is free)
          - tier 2 is honored only if the session is currently elevated
          - no explicit tier falls back to the old implicit behavior
            (elevated -> 2, otherwise -> 1) for backward compatibility
        Returns (tier, error) — error is None on success, or a short
        string the caller should surface instead of silently reassigning
        the tier.
        """
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer ") and auth[7:] == LOCAL_TOKEN and requested_tier in (1, 2):
            return requested_tier, None

        if auth.startswith("Bearer "):
            token = auth[7:]
            elevated = session_tokens.validate(token) and session_tokens.is_elevated(token)
            if requested_tier == 1:
                return 1, None
            if requested_tier == 2:
                if elevated:
                    return 2, None
                return None, "Tier 2 requires Full Mode — elevate first."
            # No explicit tier requested: old implicit behavior.
            return (2 if elevated else 1), None

        return 1, None

    def read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length > 0 else b""

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/health":
            self.send_json(200, {"status": "ok"})
            return

        if path == "/api/avatar":
            # Unauthenticated by design: the browser's <link rel="icon">
            # and the pre-gate lock screen both need to load this before
            # any auth token exists, and a profile picture isn't sensitive
            # vault/conversation data — same trust tier as /api/health.
            if os.path.exists(PERLA_AVATAR):
                ext = os.path.splitext(PERLA_AVATAR)[1].lower()
                content_type = {
                    ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
                    ".png": "image/png", ".webp": "image/webp",
                    ".gif": "image/gif",
                }.get(ext, "application/octet-stream")
                self.send_file(PERLA_AVATAR, content_type)
            else:
                self.send_error(404)
            return

        if path == "/manifest.webmanifest":
            # PWA metadata for install-to-home-screen. Unauthenticated (same
            # trust tier as /api/avatar) — it just names the palette and the
            # avatar icon; no session data. Reuses profile.jpg as the icon so
            # no extra assets need to ship.
            ext = ""
            if os.path.exists(PERLA_AVATAR):
                ext = os.path.splitext(PERLA_AVATAR)[1].lower()
            icon_type = {
                ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
                ".webp": "image/webp", ".gif": "image/gif",
            }.get(ext, "image/png")
            manifest = {
                "name": "Perla",
                "short_name": "Perla",
                "start_url": "/",
                "display": "standalone",
                "background_color": "#17131a",
                "theme_color": "#17131a",
                "icons": [{
                    "src": "/api/avatar",
                    "sizes": "any",
                    "type": icon_type,
                }],
            }
            payload = json.dumps(manifest).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/manifest+json")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)
            return

        if path.startswith("/api/audio/"):
            if not self.check_auth():
                return
            filename = os.path.basename(path)
            if not re.match(r'^[0-9a-f-]+\.mp3$', filename):
                self.send_error(400)
                return
            audio_path = os.path.join(PERLA_AUDIO_DIR, filename)
            self.send_file(audio_path, "audio/mpeg")
            return

        if path.startswith("/api/screenshot/"):
            if not self.check_auth():
                return
            filename = os.path.basename(path)
            if not re.match(r'^[0-9a-f-]+\.png$', filename):
                self.send_error(400)
                return
            screenshot_path = os.path.join(PERLA_SCREENSHOT_DIR, filename)
            self.send_file(screenshot_path, "image/png")
            return

        if path == "/api/history/days":
            if not self.check_auth():
                return
            try:
                days = list_history_days()
            except Exception as e:
                print(f"ERROR: listing history days failed: {e}", flush=True)
                self.send_json(500, {"error": "failed to list history"})
                return
            self.send_json(200, {"days": days})
            return

        if path == "/api/history/day":
            if not self.check_auth():
                return
            qs = parse_qs(parsed.query)
            date_str = (qs.get("date") or [""])[0]
            if not re.match(r'^\d{4}-\d{2}-\d{2}$', date_str):
                self.send_json(400, {"error": "invalid or missing date (expected YYYY-MM-DD)"})
                return
            try:
                entries = get_history_for_day(date_str)
            except Exception as e:
                print(f"ERROR: reading history for {date_str} failed: {e}", flush=True)
                self.send_json(500, {"error": "failed to read history"})
                return
            self.send_json(200, {"date": date_str, "entries": entries})
            return

        if path == "/api/session/check":
            # Cheap, side-effect-free: just confirms the caller's bearer
            # token is still valid. check_auth() already sends the 401
            # itself when the token's dead, so a 200 here IS the "session
            # is fine" signal — the hamburger menu's "Check Session" button
            # calls this and only needs to look at the status code.
            if not self.check_auth():
                return
            self.send_json(200, {"ok": True})
            return

        if path == "/api/reminders":
            if not self.check_auth():
                return
            try:
                reminders = get_reminders()
            except Exception as e:
                print(f"ERROR: reading reminders failed: {e}", flush=True)
                self.send_json(500, {"error": "failed to read reminders"})
                return
            self.send_json(200, reminders)
            return

        if path == "/":
            html_path = os.path.join(
                os.path.expanduser("~/.config/perla"),
                "perla-companion.html"
            )
            self.send_file(html_path, "text/html")
            return

        self.send_error(404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/gate":
            self.handle_gate()
            return

        if path != "/api/health" and not self.check_auth():
            return

        if path == "/api/text":
            self.handle_text()
            return

        if path == "/api/voice":
            self.handle_voice()
            return

        if path == "/api/elevate":
            self.handle_elevate()
            return

        if path == "/api/speak-local":
            self.handle_speak_local()
            return

        if path == "/api/internal/restart":
            self.handle_internal_restart()
            return

        if path == "/api/internal/screenshot":
            self.handle_internal_screenshot()
            return

        if path == "/api/internal/system-action":
            self.handle_internal_system_action()
            return

        if path == "/api/reminders":
            self.handle_reminders_post()
            return

        if path == "/api/quick-action":
            self.handle_quick_action()
            return

        self.send_error(404)

    def handle_gate(self):
        try:
            body = json.loads(self.read_body())
        except (json.JSONDecodeError, ValueError):
            self.send_json(400, {"error": "invalid JSON"})
            return

        password = body.get("password", "")
        if not GATE_PASSWORD or password != GATE_PASSWORD:
            self.send_json(401, {"error": "invalid password"})
            return

        token = session_tokens.create()
        self.send_json(200, {"token": token, "expires_in": SESSION_TTL})

    def handle_text(self):
        try:
            body = json.loads(self.read_body())
        except (json.JSONDecodeError, ValueError):
            self.send_json(400, {"error": "invalid JSON"})
            return

        message = body.get("message", "").strip()
        # `images` (a list) is the current field; `image` (a single data
        # URL) is kept working for any older client that hasn't switched
        # to multi-image yet.
        images_field = body.get("images")
        if images_field is None and body.get("image"):
            images_field = [body.get("image")]
        if not message and not images_field:
            self.send_json(400, {"error": "empty message"})
            return

        user_image_paths = None
        if images_field:
            user_image_paths, upload_error = decode_upload_images(images_field)
            if upload_error:
                self.send_json(400, {"error": upload_error, "message": message})
                return
            if not message:
                # Image-only send: give the model something to do with it.
                message = (
                    "Analyze this image." if len(user_image_paths) == 1
                    else f"Analyze these {len(user_image_paths)} images."
                )

        confirm = body.get("confirm", False)
        requested_tier = body.get("tier")  # local callers (perla.sh) may pass this
        source = self.get_source()
        tier, tier_error = self.get_effective_tier(requested_tier)
        if tier_error:
            if user_image_paths:
                for p in user_image_paths:
                    try:
                        os.unlink(p)
                    except OSError:
                        pass
            self.send_json(403, {"error": tier_error})
            return

        response_text, tool_used, confirm_required, action, image_path = process_message(
            message, tier, source, confirm=confirm, user_image_paths=user_image_paths
        )

        if confirm_required:
            self.send_json(200, {
                "text": response_text,
                "confirm_required": True,
                "action": action,
            })
            return

        audio_url = None
        # Only generate a downloadable audio file for REMOTE callers (phone
        # plays it through the browser). Local callers (perla.sh) get audio
        # played directly through /api/speak-local instead, so we don't
        # burn TTS twice for the same response.
        if source == "remote":
            audio_path = generate_tts(response_text)
            audio_url = f"/api/audio/{os.path.basename(audio_path)}" if audio_path else None

        image_url = f"/api/screenshot/{os.path.basename(image_path)}" if image_path else None

        self.send_json(200, {
            "text": response_text, "audio": audio_url, "tier": tier, "image": image_url,
        })

    def handle_voice(self):
        content_type = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in content_type:
            self.send_json(400, {"error": "expected multipart/form-data"})
            return

        boundary = None
        for part in content_type.split(";"):
            part = part.strip()
            if part.startswith("boundary="):
                boundary = part[9:].strip('"')
                break

        if not boundary:
            self.send_json(400, {"error": "no boundary in Content-Type"})
            return

        raw = self.read_body()
        audio_data = self._parse_multipart_audio(raw, boundary)

        if not audio_data:
            self.send_json(400, {"error": "no audio field in form data"})
            return

        tier_field = self._parse_multipart_field(raw, boundary, "tier")
        requested_tier = None
        if tier_field:
            try:
                requested_tier = int(tier_field.decode().strip())
            except ValueError:
                requested_tier = None

        tmp = tempfile.NamedTemporaryFile(suffix=".webm", delete=False)
        tmp.write(audio_data)
        tmp.close()

        try:
            transcript = transcribe_audio(tmp.name)
        finally:
            os.unlink(tmp.name)

        if not transcript:
            self.send_json(200, {
                "transcript": "",
                "text": "I couldn't understand the audio. Could you try again?",
                "audio": None
            })
            return

        source = self.get_source()
        tier, tier_error = self.get_effective_tier(requested_tier)
        if tier_error:
            self.send_json(403, {"error": tier_error, "transcript": transcript})
            return

        response_text, tool_used, confirm_required, action, image_path = process_message(
            transcript, tier, source, confirm=False
        )

        audio_url = None
        if source == "remote":
            audio_path = generate_tts(response_text)
            audio_url = f"/api/audio/{os.path.basename(audio_path)}" if audio_path else None

        image_url = f"/api/screenshot/{os.path.basename(image_path)}" if image_path else None

        self.send_json(200, {
            "transcript": transcript,
            "text": response_text,
            "audio": audio_url,
            "confirm_required": confirm_required,
            "action": action,
            "tier": tier,
            "image": image_url,
        })

    def handle_speak_local(self):
        """Local-only: speak text directly through this machine's speakers.
        Used by perla.sh instead of round-tripping an audio file."""
        if self.get_source() != "local":
            self.send_json(403, {"error": "local only"})
            return
        try:
            body = json.loads(self.read_body())
        except (json.JSONDecodeError, ValueError):
            self.send_json(400, {"error": "invalid JSON"})
            return
        text = body.get("text", "").strip()
        if not text:
            self.send_json(400, {"error": "empty text"})
            return
        ok = speak_locally(text)
        self.send_json(200, {"spoken": ok})

    def handle_internal_restart(self):
        """Restart the perla-companion daemon itself. Deliberately gated on
        normal check_auth() (any valid session, local or remote) rather than
        the stricter local-only check used by system_action/screenshot —
        this is a service-level admin action reachable from the hamburger
        menu on any surface (including phone), not a machine-level action
        like locking the screen or opening an app. It is, however, always
        unconditional: the button has no "is a restart actually needed?"
        logic — clicking it restarts the service, full stop. That check
        belongs to /api/session/check instead, as a separate deliberate step.

        The actual restart is deferred a moment (see restart_self_delayed)
        so this response reaches the client before the process is killed.
        """
        restart_self_delayed()
        self.send_json(200, {"ok": True, "message": "Restarting companion service..."})

    def handle_internal_screenshot(self):
        """Local-only: capture a screenshot and return it as base64, for
        the view_screen MCP tool (perla-view-screen-mcp.py) to call. Reuses
        the exact same lock-safe capture_screenshot() used by the
        vision-phrase path, so the lock/standby check is defined in exactly
        one place regardless of which surface (the vision phrase, or the
        model calling view_screen on its own) triggers a capture."""
        if self.get_source() != "local":
            self.send_json(403, {"error": "local only"})
            return
        path, error = capture_screenshot()
        if error:
            self.send_json(200, {"error": error})
            return
        try:
            with open(path, "rb") as f:
                encoded = base64.b64encode(f.read()).decode("ascii")
        except Exception as e:
            print(f"ERROR: reading captured screenshot failed: {e}", flush=True)
            self.send_json(500, {"error": "Captured the screen but couldn't read it back."})
            return
        self.send_json(200, {"image_base64": encoded, "mime": "image/png"})

    def handle_internal_system_action(self):
        """Local-only: run one allowlisted system action, backing the
        system_action MCP tool. Execution lives here (in the daemon's
        user-session environment) rather than in the MCP server, so the
        invocation semantics are exactly the daemon's. There is no
        keyword/phrase matching anywhere — a command runs only because the
        model called the tool with an explicit action name."""
        if self.get_source() != "local":
            self.send_json(403, {"error": "local only"})
            return
        try:
            body = json.loads(self.read_body())
        except (json.JSONDecodeError, ValueError):
            self.send_json(400, {"error": "invalid JSON"})
            return
        ok, detail = execute_system_action(body.get("action"), body.get("target"))
        self.send_json(200, {
            "ok": ok,
            "error": None if ok else detail,
            "message": detail if ok else None,
        })

    def handle_reminders_post(self):
        """Local-only: create/cancel/list reminders, backing the reminders
        MCP tool. Same local-token surface as /api/internal/screenshot. All
        reminder rows flow through _append_reminder/_cancel_reminder so the
        schema contract stays in exactly one place."""
        if self.get_source() != "local":
            self.send_json(403, {"error": "local only"})
            return
        try:
            body = json.loads(self.read_body())
        except (json.JSONDecodeError, ValueError):
            self.send_json(400, {"error": "invalid JSON"})
            return

        action = body.get("action")
        if action == "create":
            ok, detail = _append_reminder(
                body.get("text", ""), body.get("due", ""), body.get("repeat")
            )
            self.send_json(200, {
                "ok": ok,
                "id": detail if ok else None,
                "error": None if ok else detail,
            })
            return
        if action == "cancel":
            ok, detail = _cancel_reminder(body.get("id", ""))
            self.send_json(200, {
                "ok": ok,
                "id": detail if ok else None,
                "error": None if ok else detail,
            })
            return
        if action == "list":
            reminders = get_reminders()
            self.send_json(200, {"ok": True, "pending": reminders.get("pending", [])})
            return
        self.send_json(400, {"error": f"unknown action '{action}'"})

    def handle_quick_action(self):
        """Deterministic, no-LLM action dispatch backing the web UI's Quick
        Actions panel. This exists because the model was unreliable about
        actually calling its own MCP tools (view_screen especially) on
        casual phrasing — sometimes confabulating a plausible-sounding
        answer instead of looking. Rather than continuing to fight
        prompt-following for actions that don't need any judgment ("show me
        my screen" has exactly one correct behavior), this endpoint removes
        the model from the loop entirely: tap a button, run the fixed
        action, done — no chance of a hallucinated non-answer.

        Gated by the normal check_auth() this request already passed in
        do_POST (any valid session, local or remote/phone), NOT the
        stricter local-only check used by /api/internal/* — this is meant
        to be reachable from the phone's hamburger menu too, same trust
        tier as /api/internal/restart.

        `screenshot` and `list_reminders` are handled directly here since
        they aren't part of the system_action allowlist. Every other action
        name is passed straight through to execute_system_action(), so the
        allowlist, validation, and error messages stay defined in exactly
        one place (shared with the system_action MCP tool) rather than
        being duplicated here.
        """
        try:
            body = json.loads(self.read_body())
        except (json.JSONDecodeError, ValueError):
            self.send_json(400, {"error": "invalid JSON"})
            return

        action = (body.get("action") or "").strip().lower()
        target = body.get("target")
        source = self.get_source()

        if action == "screenshot":
            path, error = capture_screenshot()
            if error:
                self.send_json(200, {"ok": False, "error": error, "image": None})
                return
            image_url = f"/api/screenshot/{os.path.basename(path)}"
            log_request("[Quick Action: screenshot]", "(screenshot)", tier=0, tool_used=False, source=source)
            self.send_json(200, {"ok": True, "error": None, "image": image_url})
            return

        if action == "list_reminders":
            reminders = get_reminders()
            self.send_json(200, {"ok": True, "error": None, "reminders": reminders})
            return

        if action not in SYSTEM_ACTIONS:
            self.send_json(400, {
                "ok": False,
                "error": f"'{action}' isn't a recognized quick action.",
            })
            return

        ok, detail = execute_system_action(action, target)
        log_request(f"[Quick Action: {action}" + (f" {target}" if target else "") + "]",
                    detail, tier=0, tool_used=False, source=source)
        self.send_json(200, {
            "ok": ok,
            "error": None if ok else detail,
            "message": detail if ok else None,
        })

    def _parse_multipart_field(self, raw, boundary, field_name):
        """Extract a single named field's raw bytes from multipart form
        data. Returns None if the field isn't present."""
        boundary_bytes = boundary.encode()
        parts = raw.split(b"--" + boundary_bytes)
        for part in parts:
            if b"Content-Disposition" not in part:
                continue
            header_end = part.find(b"\r\n\r\n")
            if header_end == -1:
                continue
            header = part[:header_end].decode(errors="replace")
            if f'name="{field_name}"' not in header:
                continue
            body = part[header_end + 4:]
            if body.endswith(b"\r\n"):
                body = body[:-2]
            return body
        return None

    def _parse_multipart_audio(self, raw, boundary):
        return self._parse_multipart_field(raw, boundary, "audio")

    def handle_elevate(self):
        if not ELEVATE_TOKEN:
            self.send_json(403, {"error": "elevation not configured"})
            return

        try:
            body = json.loads(self.read_body())
        except (json.JSONDecodeError, ValueError):
            self.send_json(400, {"error": "invalid JSON"})
            return

        token = body.get("token", "")
        if token != ELEVATE_TOKEN:
            self.send_json(403, {"error": "invalid elevation token"})
            return

        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            self.send_json(401, {"error": "no session token"})
            return

        session_token = auth[7:]
        if not session_tokens.validate(session_token):
            self.send_json(401, {"error": "invalid session token"})
            return

        if session_tokens.elevate(session_token):
            self.send_json(200, {
                "tier": 2,
                "expires_in": ELEVATION_DURATION
            })
        else:
            self.send_json(500, {"error": "failed to elevate"})


# ---------------------------------------------------------------------------
# Audio / screenshot cleanup threads
# ---------------------------------------------------------------------------
def cleanup_old_files(directory, max_age_seconds, check_interval=300):
    while True:
        time.sleep(check_interval)
        now = time.time()
        try:
            for f in os.listdir(directory):
                path = os.path.join(directory, f)
                if os.path.isfile(path) and now - os.path.getmtime(path) > max_age_seconds:
                    os.unlink(path)
        except FileNotFoundError:
            pass  # directory not created yet — nothing to clean
        except Exception as e:
            print(f"ERROR: cleanup failed for {directory}: {e}", flush=True)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    os.makedirs(PERLA_AUDIO_DIR, exist_ok=True)
    os.makedirs(PERLA_SCREENSHOT_DIR, exist_ok=True)

    if not GATE_PASSWORD:
        print("FATAL: PERLA_GATE_PASSWORD not set. Exiting.", flush=True)
        return

    threading.Thread(
        target=cleanup_old_files, args=(PERLA_AUDIO_DIR, 3600), daemon=True
    ).start()
    # Screenshots are more sensitive than TTS audio (a live picture of the
    # desktop) — kept for a shorter window, just long enough to view/replay
    # in the chat before being wiped.
    threading.Thread(
        target=cleanup_old_files, args=(PERLA_SCREENSHOT_DIR, 900), daemon=True
    ).start()

    # ThreadingHTTPServer, NOT HTTPServer: /api/text blocks its thread in the
    # whole OpenCode round-trip (call_opencode, up to 300s). If the model then
    # calls the view_screen MCP tool mid-message, that tool's POST to
    # /api/internal/screenshot must be served concurrently — a single-threaded
    # server would starve it behind the very message it's helping to answer,
    # and the MCP client would time out. SessionTokenStore/SessionManager are
    # already mutex-guarded, and captures write unique files, so threading is
    # safe here.
    server = ThreadingHTTPServer((HOST, PORT), CompanionHandler)
    print(f"Perla companion listening on {HOST}:{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Shutting down.", flush=True)
        server.server_close()


if __name__ == "__main__":
    main()
