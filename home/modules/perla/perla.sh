#!/usr/bin/env bash
# perla — local client (hotkey/voice capture) for the unified Perla daemon.
#
# This used to talk to OpenCode directly and keep its own session file,
# which meant a laptop conversation and a phone conversation were two
# different OpenCode sessions even at the same tier. All of that logic
# (sessions, OpenCode calls, logging, tier0 dispatch) now lives in
# perla-companion.py — the single daemon every surface talks to. This
# script's only remaining jobs: capture mic audio, hotkey/dmenu UI, and
# play responses through local speakers.
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/perla/perla.env"
if [ -f "$CONFIG" ]; then
  . "$CONFIG"
fi

: ${PERLA_NAME:="Perla"}
: ${PERLA_AUDIO_INPUT:=""}
: ${PERLA_COMPANION_PORT:=8443}

LOCAL_TOKEN_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/perla/secrets/local-token"
if [ -f "$LOCAL_TOKEN_FILE" ]; then
  LOCAL_TOKEN="$(cat "$LOCAL_TOKEN_FILE")"
else
  LOCAL_TOKEN="local-only-no-remote-exposure"
fi

DAEMON="http://127.0.0.1:$PERLA_COMPANION_PORT"

log() { echo "[$PERLA_NAME] $*" >&2; }
notify() { notify-send -a "$PERLA_NAME" "$@"; }

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
    log "Couldn't hear anything — check your microphone."
    notify "Couldn't hear anything" "Check your microphone."
    exit 1
  fi
}

# Ask the daemon to speak text through THIS machine's speakers directly,
# rather than fetching an audio file and playing it ourselves — the daemon
# already has piper wired up, no need to duplicate that here.
speak_via_daemon() {
  local text="$1"
  curl -sf --connect-timeout 3 -m 60 -X POST "$DAEMON/api/speak-local" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $LOCAL_TOKEN" \
    -d "$(python3 -c "import json,sys; print(json.dumps({'text': sys.argv[1]}))" "$text")" \
    >/dev/null || log "WARNING: speak-local request failed"
}

send_text() {
  local text="$1"
  local tier="$2"
  curl -sf --connect-timeout 5 -m 300 -X POST "$DAEMON/api/text" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $LOCAL_TOKEN" \
    -d "$(python3 -c "
import json, sys
print(json.dumps({'message': sys.argv[1], 'tier': int(sys.argv[2])}))
" "$text" "$tier")"
}

send_voice() {
  local audio_file="$1"
  local tier="$2"
  curl -sf --connect-timeout 5 -m 300 -X POST "$DAEMON/api/voice" \
    -H "Authorization: Bearer $LOCAL_TOKEN" \
    -F "audio=@$audio_file" \
    -F "tier=$tier"
}

main() {
  local mode="${1:-hotkey}"
  local tier="${2:-1}"
  local input="${3:-}"

  if [ "$mode" = "hotkey" ]; then
    local choice
    choice="$(printf 'Quick chat\nFull mode\n' | noctalia dmenu -p "$PERLA_NAME")" || exit 0
    case "$choice" in
      "Quick chat") mode="voice"; tier=2 ;;
      "Full mode")  mode="voice"; tier=2 ;;
      *) exit 0 ;;
    esac
  fi

  if [ "$mode" = "voice" ]; then
    local audio_file="/tmp/$PERLA_NAME-input.wav"
    capture_audio "$audio_file"

    log "Sending audio to Perla..."
    local result
    result="$(send_voice "$audio_file" "$tier")" || {
      log "Perla daemon is offline — couldn't reach the companion."
      notify "$PERLA_NAME is offline" "Couldn't reach the Perla daemon."
      exit 1
    }

    local transcript response
    transcript="$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript',''))")"
    response="$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text',''))")"

    log "Heard: $transcript"
    log "Response: $response"

    echo "$response"
    speak_via_daemon "$response"
    notify -u low "$PERLA_NAME" "$response"
    return 0
  fi

  # Text mode (e.g. called directly with input text)
  if [ -z "$input" ]; then
    log "No input provided."
    notify "$PERLA_NAME" "No input."
    exit 1
  fi

  local result response
  result="$(send_text "$input" "$tier")" || {
    log "Perla daemon is offline — couldn't reach the companion."
    notify "$PERLA_NAME is offline" "Couldn't reach the Perla daemon."
    exit 1
  }
  response="$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text',''))")"

  echo "$response"
  speak_via_daemon "$response"
  notify -u low "$PERLA_NAME" "$response"
}

main "$@"
