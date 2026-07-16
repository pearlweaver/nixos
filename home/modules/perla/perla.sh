#!/usr/bin/env bash
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/perla/perla.env"
if [ -f "$CONFIG" ]; then
  . "$CONFIG"
fi

: ${PERLA_NAME:="Perla"}
: ${PERLA_PERSONA:="$HOME/.config/perla/persona.md"}
: ${PERLA_MODEL:="opencode/deepseek-v4-flash-free"}
: ${PERLA_VAULT:="$HOME/Documents/Obsidian/Perla"}
: ${PERLA_VOICE:="en_GB-southern_english_female-low"}
: ${PERLA_WHISPER_MODEL:="tiny"}
: ${PERLA_WHISPER_LANG:="en"}
: ${PERLA_IDLE_MINUTES:=10}
: ${PERLA_AUDIO_INPUT:=""}

SESSION_DIR="${XDG_RUNTIME_DIR:-/tmp}/perla"
mkdir -p "$SESSION_DIR"

SERVER_PORT_T1=13101
SERVER_PORT_T2=13102

log() { echo "[$PERLA_NAME] $*" >&2; }
notify() { notify-send -a "$PERLA_NAME" "$@"; }

tier0() {
  local text="$1"
  local lower
  lower="$(echo "$text" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    *"open firefox"*)    systemd-run --user --unit=perla-firefox firefox 2>/dev/null; return 0 ;;
    *"open terminal"*)   systemd-run --user --unit=perla-kitty kitty 2>/dev/null; return 0 ;;
    *"open code"*)       systemd-run --user --unit=perla-codium codium 2>/dev/null; return 0 ;;
    *"lock"*)            noctalia msg session lock; return 0 ;;
    *"mute"*)            wpctl set-mute @DEFAULT_AUDIO_SINK@ 1; return 0 ;;
    *"unmute"*)          wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; return 0 ;;
    *"screenshot"*)      grim "$HOME/Pictures/Screenshots/$(date +%s).png"; return 0 ;;
    *"suspend"*|*"sleep"*) systemctl suspend; return 0 ;;
    *) return 1 ;;
  esac
}

capture_audio() {
  local out="$1"
  notify "$PERLA_NAME" "Listening..."
  log "Recording 5s..."
  local source="${PERLA_AUDIO_INPUT:-$(pw-cli list-objects | grep -A2 'node.name.*alsa_input' | head -1 | awk '{print $NF}')}"
  pw-record --target "$source" "$out" &
  local pid=$!
  sleep 5
  kill "$pid" 2>/dev/null || true
  if [ ! -s "$out" ]; then
    notify "Couldn't hear anything" "Check your microphone."
    exit 1
  fi
}

stt() {
  local audio="$1"
  local model_dir="$HOME/.local/share/whisper-cpp/models"
  local model_file="$model_dir/ggml-$PERLA_WHISPER_MODEL.bin"
  mkdir -p "$model_dir"
  if [ ! -f "$model_file" ]; then
    log "Downloading whisper model..."
    curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$PERLA_WHISPER_MODEL.bin" -o "$model_file"
  fi
  log "Transcribing..."
  whisper-cli --model "$model_file" --file "$audio" --language "$PERLA_WHISPER_LANG" 2>/dev/null
}

speak() {
  local text="$1"
  local voice_dir="$HOME/.local/share/piper-tts/voices"
  local voice_file="$voice_dir/$PERLA_VOICE.onnx"
  mkdir -p "$voice_dir"
  if [ ! -f "$voice_file" ]; then
    log "Downloading Piper voice $PERLA_VOICE..."
    local lang_region="${PERLA_VOICE%%-*}"
    local lang="${lang_region%_*}"
    local voice_qual="${PERLA_VOICE#*-}"
    local voice="${voice_qual%-*}"
    local quality="${voice_qual##*-}"
    local base="https://huggingface.co/rhasspy/piper-voices/resolve/main/$lang/$lang_region/$voice/$quality/$PERLA_VOICE"
    curl -L "$base.onnx" -o "$voice_file"
    curl -L "$base.onnx.json" -o "$voice_file.json" 2>/dev/null || true
  fi
  log "Speaking..."
  echo "$text" | piper --model "$voice_file" --output-raw --length-scale 1 | pw-play --rate=22050 --channels=1 --format=s16 --raw -
}

# --- Persistent server management ---

ensure_server() {
  local tier="$1"
  local port
  local pid_file
  local log_file
  if [ "$tier" = "1" ]; then
    port="$SERVER_PORT_T1"
    pid_file="$SESSION_DIR/server-t1.pid"
    log_file="$SESSION_DIR/server-t1.log"
  else
    port="$SERVER_PORT_T2"
    pid_file="$SESSION_DIR/server-t2.pid"
    log_file="$SESSION_DIR/server-t2.log"
  fi

  if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    if curl -sf "http://127.0.0.1:$port/global/health" >/dev/null 2>&1; then
      return 0
    fi
  fi

  log "Starting OpenCode server (Tier $tier)..."
  if [ "$tier" = "1" ]; then
    local tmpdir
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/opencode"
    cp -r "$HOME/.config/opencode/"* "$tmpdir/opencode/"
    cp "$HOME/.config/opencode/opencode-t1.json" "$tmpdir/opencode/opencode.json"
    setsid -f env XDG_CONFIG_HOME="$tmpdir" opencode serve --port "$port" > "$log_file" 2>&1
  else
    setsid -f opencode serve --port "$port" > "$log_file" 2>&1
  fi

  for i in $(seq 1 5); do
    local found
    found="$(pgrep -f "opencode serve.*--port $port" 2>/dev/null | head -1)"
    if [ -n "$found" ]; then
      echo "$found" > "$pid_file"
      break
    fi
    sleep 1
  done

  for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:$port/global/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  notify "Server failed to start" "OpenCode server (Tier $tier) did not respond."
  exit 1
}

ensure_session() {
  local tier="$1"
  local port
  local session_file="$SESSION_DIR/server-t$tier.session"

  if [ "$tier" = "1" ]; then port="$SERVER_PORT_T1"; else port="$SERVER_PORT_T2"; fi

  if [ -f "$session_file" ]; then
    local sid
    sid="$(cat "$session_file")"
    if curl -sf "http://127.0.0.1:$port/session/$sid" >/dev/null 2>&1; then
      echo "$sid"
      return 0
    fi
  fi

  log "Creating session (Tier $tier)..."
  local sid
  sid="$(curl -sf -X POST "http://127.0.0.1:$port/session" \
    -H 'Content-Type: application/json' \
    -d '{"title":"perla"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")"
  echo "$sid" > "$session_file"
  rm -f "$SESSION_DIR/server-t$tier.injected"
  echo "$sid"
}

model_part() {
  local full="$1"
  local provider="${full%%/*}"
  local model="${full#*/}"
  printf '{"providerID":"%s","modelID":"%s"}' "$provider" "$model"
}

call_opencode() {
  local text="$1"
  local tier="$2"

  if ! command -v opencode &>/dev/null; then
    notify "$PERLA_NAME brain unavailable" "OpenCode not installed."
    exit 1
  fi

  ensure_server "$tier"
  local port
  if [ "$tier" = "1" ]; then port="$SERVER_PORT_T1"; else port="$SERVER_PORT_T2"; fi

  local session_file="$SESSION_DIR/server-t$tier.session"
  local injected_file="$SESSION_DIR/server-t$tier.injected"

  local sid
  sid="$(ensure_session "$tier")"

  if [ ! -f "$injected_file" ]; then
    local persona_file="${PERLA_PERSONA:-$HOME/.config/perla/persona.md}"
    if [ -f "$persona_file" ]; then
      text="ATTENTION — Read and follow these rules for your identity and behavior:

$(cat "$persona_file")

Now respond to the user:

$text"
    else
      text="IMPORTANT — Your name is Perla. You are NOT opencode.

$text"
    fi
    touch "$injected_file"
  fi

  log "Consulting OpenCode (Tier $tier)..."
  local model_json
  model_json="$(model_part "$PERLA_MODEL")"

  local body
  body="$(python3 -c "
import sys, json
text = sys.stdin.read()
model = json.loads('$model_json')
print(json.dumps({
  'parts': [{'type': 'text', 'text': text}],
  'model': model
}))
" <<< "$text")"

  local result
  result="$(curl -sf -X POST "http://127.0.0.1:$port/session/$sid/message" \
    -H 'Content-Type: application/json' \
    -d "$body")" || {
    notify "$PERLA_NAME is offline" "OpenCode server (Tier $tier) error."
    exit 1
  }

  local output
  output="$(python3 -c "
import sys, json
d = json.load(sys.stdin)
text = ' '.join(p.get('text','') for p in d['parts'] if p['type']=='text')
tool_used = any(p.get('type') == 'tool' for p in d['parts'])
print('true' if tool_used else 'false')
print(text)
" <<< "$result")"

  OPENCODE_TOOL_USED="$(echo "$output" | head -1)"
  OPENCODE_RESPONSE="$(echo "$output" | tail -n +2)"
}

is_casual() {
  local text="$1"
  local lower
  lower="$(echo "$text" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    "hi"|"hello"|"hey"|"yo"|"sup"|"what's up"|"howdy"|"good morning"|"good evening"|"good night"|"how are you"|"how's it going"|"what's new"|"good"|"fine"|"ok"|"okay"|"nice"|"cool"|"great"|"awesome"|"thanks"|"bye"|"goodbye")
      return 0 ;;
    say\ hello|say\ hi|tell\ me\ a\ joke|what\ is\ your\ name|just\ say\ hi)
      return 0 ;;
  esac
  [ "$(echo "$text" | wc -w)" -le 3 ] && return 0
  return 1
}

log_command() {
  local text="$1"
  local response="$2"
  local tier="$3"
  local log_dir="$PERLA_VAULT/Command Log"
  mkdir -p "$log_dir"
  local log_file="$log_dir/$(date +%Y-%m-%d).md"
  {
    echo "## $(date +%H:%M) — Tier $tier"
    echo "- **Input:** $text"
    echo "- **Response:** $response"
    echo ""
  } >> "$log_file"
}

log_conversation() {
  local text="$1"
  local response="$2"
  local tier="$3"
  local log_dir="$PERLA_VAULT/Conversations"
  mkdir -p "$log_dir"
  local log_file="$log_dir/$(date +%Y-%m-%d).md"
  {
    echo "## $(date +%H:%M) — Tier $tier"
    echo "- **User:** $text"
    echo "- **Perla:** $response"
    echo ""
  } >> "$log_file"
}

main() {
  local mode="${1:-hotkey}"
  local tier="${2:-1}"
  local input="${3:-}"

  if [ "$mode" = "hotkey" ]; then
    local choice
    choice="$(printf 'Quick chat\nFull mode\n' | noctalia dmenu -p "$PERLA_NAME")" || exit 0
    case "$choice" in
      "Quick chat")
        mode="voice"
        tier=2
        ;;
      "Full mode")
        mode="voice"
        tier=2
        ;;
      *) exit 0 ;;
    esac
  fi

  if [ "$mode" = "voice" ]; then
    local audio_file="/tmp/$PERLA_NAME-input.wav"
    capture_audio "$audio_file"
    input="$(stt "$audio_file")"
    log "Heard: $input"
    if [ -z "$input" ]; then
      notify "$PERLA_NAME" "I didn't catch that."
      exit 1
    fi
  fi

  if [ -z "$input" ]; then
    notify "$PERLA_NAME" "No input."
    exit 1
  fi

  if tier0 "$input"; then
    log_command "$input" "Executed directly" "0"
    return 0
  fi

  if [ "$mode" = "voice" ]; then
    tier=2
  fi

  call_opencode "$input" "$tier"
  local response="$OPENCODE_RESPONSE"
  local tool_used="$OPENCODE_TOOL_USED"
  log "Response: $response"

  if [ "$mode" = "voice" ]; then
    speak "$response"
  else
    notify "$PERLA_NAME" "$response"
  fi

  if [ "$tool_used" = "true" ]; then
    log_command "$input" "$response" "$tier"
  else
    log_conversation "$input" "$response" "$tier"
  fi
}

main "$@"
