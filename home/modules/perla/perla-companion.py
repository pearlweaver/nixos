#!/usr/bin/env python3
"""Perla phone companion — HTTP backend for Tailscale-served mobile access."""

import json
import os
import shlex
import subprocess
import tempfile
import time
import uuid
from datetime import datetime
from http import HTTPStatus
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import re
import threading

# ---------------------------------------------------------------------------
# Config from environment (set by systemd unit)
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
SERVER_PORT_T1 = int(os.environ.get("PERLA_SERVER_PORT_T1", "13101"))
SERVER_PORT_T2 = int(os.environ.get("PERLA_SERVER_PORT_T2", "13102"))
ELEVATION_DURATION = int(os.environ.get("PERLA_ELEVATION_DURATION", "300"))  # 5 minutes
GATE_PASSWORD = os.environ.get("PERLA_GATE_PASSWORD", "")

# Tokens read from sops-decrypted files at startup
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


ELEVATE_TOKEN = read_secret("elevate-token")


# ---------------------------------------------------------------------------
# Session token store (server-issued short-lived tokens)
# ---------------------------------------------------------------------------
SESSION_TTL = int(os.environ.get("PERLA_SESSION_TTL", "86400"))  # 24 hours


class SessionTokenStore:
    """Manages short-lived session tokens issued after gate authentication."""

    def __init__(self):
        self._tokens = {}  # token -> expiry_timestamp
        self._elevated = set()  # tokens with active Tier 2 elevation
        self._elevation_expiry = {}  # token -> expiry_timestamp
        self._lock = threading.Lock()

    def create(self):
        """Issue a new session token, return it."""
        token = uuid.uuid4().hex
        with self._lock:
            self._tokens[token] = time.time() + SESSION_TTL
        return token

    def validate(self, token):
        """Check if a session token is valid and not expired."""
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
        """Grant Tier 2 elevation to a session token."""
        with self._lock:
            if token not in self._tokens:
                return False
            self._elevated.add(token)
            self._elevation_expiry[token] = time.time() + ELEVATION_DURATION
            return True

    def is_elevated(self, token):
        """Check if a session token has active Tier 2 elevation."""
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
        """Seconds of elevation remaining."""
        with self._lock:
            expiry = self._elevation_expiry.get(token, 0)
            remaining = expiry - time.time()
            return max(0, int(remaining))


session_tokens = SessionTokenStore()


# ---------------------------------------------------------------------------
# OpenCode session management
# ---------------------------------------------------------------------------
class SessionManager:
    """Manages OpenCode API sessions per tier."""

    def __init__(self):
        self._sessions = {}  # tier -> session_id
        self._persona_injected = set()  # set of tier values
        self._lock = threading.Lock()

    def get_session(self, tier):
        """Get or create a session for the given tier."""
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
        port = SERVER_PORT_T1 if tier == 1 else SERVER_PORT_T2
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
        port = SERVER_PORT_T1 if tier == 1 else SERVER_PORT_T2
        try:
            result = subprocess.run(
                ["curl", "-sf", "--connect-timeout", "3", "-m", "10",
                 "-X", "POST", f"http://127.0.0.1:{port}/session",
                 "-H", "Content-Type: application/json",
                 "-d", '{"title":"perla-companion"}'],
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
# Core functions
# ---------------------------------------------------------------------------
def read_persona():
    """Read persona.md content."""
    try:
        with open(PERLA_PERSONA, "r") as f:
            return f.read()
    except FileNotFoundError:
        return f"IMPORTANT — Your name is {PERLA_NAME}. You are NOT opencode."


def model_part():
    """Parse provider/model into OpenCode JSON."""
    provider, model = PERLA_MODEL.split("/", 1)
    return {"providerID": provider, "modelID": model}


def call_opencode(sid, port, text, tier):
    """Call OpenCode API and return (response_text, tool_used)."""
    # Persona injection on first message
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
            return "OpenCode server error — try again.", False

        data = json.loads(result.stdout)
        response_text = " ".join(
            p.get("text", "") for p in data.get("parts", []) if p.get("type") == "text"
        )
        tool_used = any(p.get("type") == "tool" for p in data.get("parts", []))
        return response_text or "(no response)", tool_used

    except subprocess.TimeoutExpired:
        return "Request timed out — the AI took too long to respond.", False
    except Exception as e:
        print(f"ERROR: call_opencode failed: {e}", flush=True)
        return "Failed to reach Perla's brain.", False


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


def transcribe_audio(audio_path):
    """Transcribe audio file using whisper-cli."""
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
        # whisper-cli outputs transcription to stdout
        return result.stdout.strip() or ""
    except Exception as e:
        print(f"ERROR: transcription failed: {e}", flush=True)
        return ""


def log_request(input_text, response, tier, tool_used):
    """Log to Obsidian vault (same format as perla.sh)."""
    tier_label = f"Tier {tier} (remote)"
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


def is_destructive(text):
    """Check if a message contains destructive actions."""
    lower = text.lower()
    destructive_patterns = [
        r"\bdelete\b", r"\brm\b", r"\bremove\b",
        r"\boverwrite\b", r"\bwrite\b.*\bfile\b",
        r"\bsudo\b", r"\bsystemctl\b", r"\breboot\b", r"\bshutdown\b",
        r"\bformat\b", r"\bkill\b", r"\bpkill\b",
    ]
    return any(re.search(p, lower) for p in destructive_patterns)


# ---------------------------------------------------------------------------
# HTTP Handler
# ---------------------------------------------------------------------------
class CompanionHandler(BaseHTTPRequestHandler):
    """HTTP request handler for Perla companion API."""

    def log_message(self, format, *args):
        # Suppress default access log
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
        """Check bearer token. Returns True if authorized."""
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            token = auth[7:]
            if session_tokens.validate(token):
                return True
            if ELEVATE_TOKEN and token == ELEVATE_TOKEN:
                return True
        self.send_json(401, {"error": "unauthorized"})
        return False

    def get_effective_tier(self):
        """Determine effective tier (1 or 2 if elevated)."""
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            token = auth[7:]
            if session_tokens.validate(token) and session_tokens.is_elevated(token):
                return 2
        return 1

    def read_body(self):
        """Read request body as bytes."""
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length > 0 else b""

    def do_OPTIONS(self):
        """Handle CORS preflight."""
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
            # Sanitize filename
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

        # Auth check (except health and gate)
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

        self.send_error(404)

    def handle_gate(self):
        """Handle POST /api/gate — exchange gate password for session token."""
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
        """Handle POST /api/text."""
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
        tier = self.get_effective_tier()

        # Destructive action check for Tier 2
        if tier == 2 and is_destructive(message) and not confirm:
            self.send_json(200, {
                "text": f"About to execute a potentially destructive action. Confirm?",
                "confirm_required": True,
                "action": message
            })
            return

        sid = session_mgr.get_session(tier)
        if not sid:
            self.send_json(503, {"error": "OpenCode server unavailable"})
            return

        port = SERVER_PORT_T1 if tier == 1 else SERVER_PORT_T2
        response_text, tool_used = call_opencode(sid, port, message, tier)

        # Generate TTS
        audio_path = generate_tts(response_text)
        audio_url = f"/api/audio/{os.path.basename(audio_path)}" if audio_path else None

        # Log
        log_request(message, response_text, tier, tool_used)

        self.send_json(200, {"text": response_text, "audio": audio_url})

    def handle_voice(self):
        """Handle POST /api/voice."""
        content_type = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in content_type:
            self.send_json(400, {"error": "expected multipart/form-data"})
            return

        # Parse multipart manually (no external deps)
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

        # Save uploaded audio to temp file
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

        # Feed transcript through text pipeline
        tier = self.get_effective_tier()
        sid = session_mgr.get_session(tier)
        if not sid:
            self.send_json(503, {"error": "OpenCode server unavailable"})
            return

        confirm = False  # Voice doesn't carry confirm flag
        port = SERVER_PORT_T1 if tier == 1 else SERVER_PORT_T2
        response_text, tool_used = call_opencode(sid, port, transcript, tier)

        audio_path = generate_tts(response_text)
        audio_url = f"/api/audio/{os.path.basename(audio_path)}" if audio_path else None

        log_request(transcript, response_text, tier, tool_used)

        self.send_json(200, {
            "transcript": transcript,
            "text": response_text,
            "audio": audio_url
        })

    def _parse_multipart_audio(self, raw, boundary):
        """Extract the 'audio' field from multipart data."""
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
            # Extract filename if present
            body = part[header_end + 4:]
            # Remove trailing \r\n-- if present
            if body.endswith(b"\r\n"):
                body = body[:-2]
            return body
        return None

    def handle_elevate(self):
        """Handle POST /api/elevate — grant Tier 2 to the caller's session token."""
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

        # Elevate the session token from the Authorization header
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
    """Delete audio files older than 1 hour."""
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

    # Start cleanup thread
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
