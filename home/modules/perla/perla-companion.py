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

import json
import os
import re
import shlex
import signal
import subprocess
import tempfile
import time
import uuid
from datetime import datetime
from http import HTTPStatus
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
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
PERLA_WHISPER_MODEL = os.environ.get("PERLA_WHISPER_MODEL", "tiny")
PERLA_WHISPER_LANG = os.environ.get("PERLA_WHISPER_LANG", "en")
PERLA_AUDIO_DIR = os.environ.get("PERLA_AUDIO_DIR", os.path.expanduser("~/.local/share/perla-audio"))
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
            subprocess.Popen(
                ["opencode", "serve", "--port", str(port)],
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
def tier0_dispatch(text):
    """Try to handle text as a direct system action. Returns response
    string if handled, None if not a tier0 command."""
    lower = text.lower()

    def run_detached(cmd_list, unit):
        subprocess.Popen(
            ["systemd-run", "--user", f"--unit={unit}"] + cmd_list,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    try:
        if "open firefox" in lower:
            run_detached(["firefox"], "perla-firefox")
            return "Opening Firefox."
        if "open terminal" in lower:
            run_detached(["kitty"], "perla-kitty")
            return "Opening a terminal."
        if "open code" in lower:
            run_detached(["codium"], "perla-codium")
            return "Opening the editor."
        if "lock" in lower:
            subprocess.run(["noctalia", "msg", "session", "lock"], timeout=5)
            return "Locked."
        if "unmute" in lower:
            subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"], timeout=5)
            return "Unmuted."
        if "mute" in lower:
            subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1"], timeout=5)
            return "Muted."
        if "screenshot" in lower:
            path = os.path.expanduser(f"~/Pictures/Screenshots/{int(time.time())}.png")
            subprocess.run(["grim", path], timeout=10)
            return "Screenshot taken."
        if "suspend" in lower or "sleep" in lower:
            subprocess.run(["systemctl", "suspend"], timeout=5)
            return "Suspending."
    except Exception as e:
        print(f"ERROR: tier0 dispatch failed: {e}", flush=True)
        return None

    return None


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


def call_opencode(sid, port, text, tier):
    if session_mgr.should_inject_persona(tier):
        persona = read_persona()
        text = (
            f"ATTENTION — Read and follow these rules for your identity and behavior:\n\n"
            f"{persona}\n\n"
            f"Now respond to the user:\n\n"
            f"{text}"
        )
        session_mgr.mark_persona_injected(tier)

    body = json.dumps({
        "parts": [{"type": "text", "text": text}],
        "model": model_part()
    })

    try:
        result = subprocess.run(
            ["curl", "-sf", "--connect-timeout", "5", "-m", "300",
             "-X", "POST", f"http://127.0.0.1:{port}/session/{sid}/message",
             "-H", "Content-Type: application/json",
             "-d", body],
            capture_output=True, text=True, timeout=310
        )
        if result.returncode != 0:
            return "OpenCode server error — try again.", False, False

        data = json.loads(result.stdout)
        response_text = " ".join(
            p.get("text", "") for p in data.get("parts", []) if p.get("type") == "text"
        )
        tool_used = any(p.get("type") == "tool" for p in data.get("parts", []))

        obsidian_writes = {
            "obsidian_write_note", "obsidian_patch_note", "obsidian_append_to_note",
            "obsidian_replace_in_note", "obsidian_manage_tags", "obsidian_delete_note",
            "obsidian_manage_frontmatter",
        }
        obsidian_write = any(
            p.get("tool", "") in obsidian_writes
            for p in data.get("parts", []) if p.get("type") == "tool"
        )

        return response_text or "(no response)", tool_used, obsidian_write

    except subprocess.TimeoutExpired:
        return "Request timed out — the AI took too long to respond.", False, False
    except Exception as e:
        print(f"ERROR: call_opencode failed: {e}", flush=True)
        return "Failed to reach Perla's brain.", False, False


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


def process_message(message, tier, source, confirm=False):
    """The single entrypoint every surface funnels through: tier0 check,
    then OpenCode, then logging. Returns (response_text, tool_used,
    confirm_required, confirm_action)."""

    # Tier 0 direct dispatch — bypasses the LLM entirely, same for every surface.
    tier0_response = tier0_dispatch(message)
    if tier0_response is not None:
        log_request(message, tier0_response, 0, True, source=source)
        return tier0_response, True, False, None

    if tier == 2 and is_destructive(message) and not confirm:
        return (
            "About to execute a potentially destructive action. Confirm?",
            False, True, message
        )

    sid = session_mgr.get_session(tier)
    if not sid:
        return "OpenCode server unavailable.", False, False, None

    port = SERVER_PORT_T1 if tier == 1 else SERVER_PORT_T2
    response_text, tool_used, obsidian_write = call_opencode(sid, port, message, tier)

    log_request(message, response_text, tier, tool_used, source=source)

    if is_memory_worthy(message) and not obsidian_write:
        log_memory_mismatch(message, response_text, tier, source=source)
        print("WARNING: memory-worthy input with no Obsidian write detected", flush=True)

    return response_text, tool_used, False, None


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
        """Local callers may explicitly request a tier (perla.sh already
        knows if it's hotkey-quick-chat vs full-mode). Remote callers use
        elevation status as before."""
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer ") and auth[7:] == LOCAL_TOKEN and requested_tier in (1, 2):
            return requested_tier
        if auth.startswith("Bearer "):
            token = auth[7:]
            if session_tokens.validate(token) and session_tokens.is_elevated(token):
                return 2
        return 1

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
        if not message:
            self.send_json(400, {"error": "empty message"})
            return

        confirm = body.get("confirm", False)
        requested_tier = body.get("tier")  # local callers (perla.sh) may pass this
        source = self.get_source()
        tier = self.get_effective_tier(requested_tier)

        response_text, tool_used, confirm_required, action = process_message(
            message, tier, source, confirm=confirm
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

        self.send_json(200, {"text": response_text, "audio": audio_url})

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
        tier = self.get_effective_tier()  # voice never carries explicit tier

        response_text, tool_used, confirm_required, action = process_message(
            transcript, tier, source, confirm=False
        )

        audio_url = None
        if source == "remote":
            audio_path = generate_tts(response_text)
            audio_url = f"/api/audio/{os.path.basename(audio_path)}" if audio_path else None

        self.send_json(200, {
            "transcript": transcript,
            "text": response_text,
            "audio": audio_url,
            "confirm_required": confirm_required,
            "action": action,
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

    def _parse_multipart_audio(self, raw, boundary):
        boundary_bytes = boundary.encode()
        parts = raw.split(b"--" + boundary_bytes)
        for part in parts:
            if b"Content-Disposition" not in part:
                continue
            header_end = part.find(b"\r\n\r\n")
            if header_end == -1:
                continue
            header = part[:header_end].decode(errors="replace")
            if 'name="audio"' not in header:
                continue
            body = part[header_end + 4:]
            if body.endswith(b"\r\n"):
                body = body[:-2]
            return body
        return None

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
# Audio cleanup thread
# ---------------------------------------------------------------------------
def cleanup_old_audio():
    while True:
        time.sleep(300)
        now = time.time()
        try:
            for f in os.listdir(PERLA_AUDIO_DIR):
                path = os.path.join(PERLA_AUDIO_DIR, f)
                if os.path.isfile(path) and now - os.path.getmtime(path) > 3600:
                    os.unlink(path)
        except Exception as e:
            print(f"ERROR: audio cleanup failed: {e}", flush=True)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    os.makedirs(PERLA_AUDIO_DIR, exist_ok=True)

    if not GATE_PASSWORD:
        print("FATAL: PERLA_GATE_PASSWORD not set. Exiting.", flush=True)
        return

    cleanup_thread = threading.Thread(target=cleanup_old_audio, daemon=True)
    cleanup_thread.start()

    server = HTTPServer((HOST, PORT), CompanionHandler)
    print(f"Perla companion listening on {HOST}:{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Shutting down.", flush=True)
        server.server_close()


if __name__ == "__main__":
    main()
