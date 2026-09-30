#!/usr/bin/env bash
# perla — local client (hotkey/voice capture) for the unified Perla daemon.
#
# This used to talk to OpenCode directly and keep its own session file,
# which meant a laptop conversation and a phone conversation were two
# different OpenCode sessions even at the same tier. All of that logic
# (sessions, OpenCode calls, logging, system actions) now lives in
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
# How long to wait on a turn. Normally supplied by perla.env (Nix-generated
# from the same `turn_timeout_seconds` the daemon uses, so the two can never
# disagree); the default only matters if that file is missing.
: ${PERLA_TURN_TIMEOUT:=900}

LOCAL_TOKEN_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/perla/secrets/local-token"
if [ -f "$LOCAL_TOKEN_FILE" ]; then
  LOCAL_TOKEN="$(cat "$LOCAL_TOKEN_FILE")"
else
  LOCAL_TOKEN="local-only-no-remote-exposure"
fi

DAEMON="http://127.0.0.1:$PERLA_COMPANION_PORT"

log() { echo "[$PERLA_NAME] $*" >&2; }
notify() { notify-send -a "$PERLA_NAME" "$@"; }

# Say what actually went wrong, using curl's exit code. 28 is its operation
# timeout — the turn simply outlasted PERLA_TURN_TIMEOUT. 6/7 are genuine
# reachability failures. 22 means the daemon answered with an HTTP error.
# This used to report "offline" for all three, which was actively misleading
# on a timeout: the daemon was alive and still finished the turn (logging the
# reply to the vault) while the user was told it was unreachable and never
# saw the answer.
explain_failure() {
  local code="$1" what="$2"
  case "$code" in
    28)
      log "No reply within ${PERLA_TURN_TIMEOUT}s for the $what request."
      notify "$PERLA_NAME is still thinking" \
        "No answer after ${PERLA_TURN_TIMEOUT}s. It may still finish — check the web app."
      ;;
    22)
      log "The companion rejected the $what request."
      notify "$PERLA_NAME had a problem" "The companion refused that request."
      ;;
    *)
      log "Perla daemon is offline — couldn't reach the companion."
      notify "$PERLA_NAME is offline" "Couldn't reach the Perla daemon."
      ;;
  esac
}

capture_audio() {
  local out="$1" seconds="${2:-5}"
  notify "$PERLA_NAME" "Listening..."
  log "Recording ${seconds}s..."
  local source="${PERLA_AUDIO_INPUT:-$(pw-cli list-objects | grep -A2 'node.name.*alsa_input' | head -1 | awk '{print $NF}')}"
  pw-record --target "$source" "$out" &
  local pid=$!
  sleep "$seconds"
  kill "$pid" 2>/dev/null || true
  if [ ! -s "$out" ]; then
    log "Couldn't hear anything — check your microphone."
    notify "$PERLA_NAME is offline" "Couldn't hear your microphone."
    exit 1
  fi
}

# Record an answer without the "you said nothing" hard-exit that the opening
# capture uses. Silence here is a legitimate outcome (the user may have
# wandered off), so the caller decides what to do about it.
capture_reply() {
  local out="$1" seconds="${2:-12}"
  log "Recording answer (${seconds}s)..."
  local source="${PERLA_AUDIO_INPUT:-$(pw-cli list-objects | grep -A2 'node.name.*alsa_input' | head -1 | awk '{print $NF}')}"
  pw-record --target "$source" "$out" &
  local pid=$!
  sleep "$seconds"
  kill "$pid" 2>/dev/null || true
  [ -s "$out" ] || rm -f "$out"
}

# Transcribe an already-recorded clip without spending a model turn. /api/voice
# would transcribe AND run the model, which is the opposite of what a spoken
# answer to a question needs.
transcribe_file() {
  local audio_file="$1"
  curl -sf --connect-timeout 5 -m 60 -X POST "$DAEMON/api/transcribe" \
    -H "Authorization: Bearer $LOCAL_TOKEN" \
    -F "audio=@$audio_file" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('text','').strip())" 2>/dev/null
}

# Turn a blocked turn into something worth saying out loud, and decide what to
# send back when the user answers by voice.
#
# Two jobs, both awkward in bash so they live in python:
#   * prompt  — render a question (and its options) or a permission request as
#               speakable prose. The daemon's speech_text already handles code
#               blocks/symbols, but these payloads are structured, not prose.
#   * resolve — map a spoken answer onto an option when the user used a
#               shortcut ("option two", "the second one", "beta"), otherwise
#               pass their words through as free text so nothing is ever lost.
voice_prompt() {
  python3 -c '
import json, sys

d = json.load(sys.stdin)
kind = "question" if d.get("question_required") else "permission"
parts = []

if kind == "question":
    for q in (d.get("questions") or []):
        text = q.get("question") or q.get("header") or q.get("text") or ""
        if text:
            parts.append(text)
        labels = [o.get("label") for o in (q.get("options") or [])
                  if isinstance(o, dict) and o.get("label")]
        if labels:
            parts.append("You can say " + ", ".join(labels) + ", or just tell me in your own words.")
else:
    where = ", ".join(d.get("directories") or []) or ", ".join(d.get("patterns") or [])
    parts.append("I need permission to use " + (where or "a path outside the working directory") + ".")
    parts.append("Say allow, or say reject.")

print(" ".join(p for p in parts if p).strip())
'
}

# Decide the answer to POST. Shortcut only when the user clearly picked one of
# the offered options; anything else is treated as free text, which the
# question card already accepts.
voice_answer_for_question() {
  python3 -c '
import json, re, sys

payload = json.loads(sys.argv[1])
spoken = sys.argv[2].strip().strip(" .!?,")
lowered = spoken.lower()

NUMBER_WORDS = {"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,
                "eight":8,"nine":9,"ten":10,"first":1,"second":2,"third":3,
                "fourth":4,"fifth":5,"1":1,"2":2,"3":3,"4":4,"5":5,
                "1st":1,"2nd":2,"3rd":3}

options = []
for q in (payload.get("questions") or []):
    for o in (q.get("options") or []):
        if isinstance(o, dict) and o.get("label"):
            options.append(o["label"])

lowered_options = [o.lower() for o in options]

# 1. An explicit option label.
for o, low in zip(options, lowered_options):
    if lowered == low:
        print(json.dumps([[o]])); sys.exit(0)

# 2. "option two" / "the second one" / bare "two" — but only when the word
#    is not itself one of the option labels (otherwise a label named "Two"
#    would be read as the number).
if options:
    idx = None
    if lowered.startswith(("option ", "number ")):
        idx = NUMBER_WORDS.get(lowered.split()[-1])
    elif lowered.startswith("the "):
        idx = NUMBER_WORDS.get(lowered.split()[1] if len(lowered.split()) > 1 else "")
    elif lowered in NUMBER_WORDS and lowered not in lowered_options:
        idx = NUMBER_WORDS[lowered]
    if idx and 1 <= idx <= len(options):
        print(json.dumps([[options[idx-1]]])); sys.exit(0)

# 3. An option named inside a sentence ("just go ahead with gamma"). Only for
#    labels long enough that a stray substring match is implausible.
for o, low in zip(options, lowered_options):
    if len(low) >= 4 and re.search(r"\b" + re.escape(low) + r"\b", lowered):
        print(json.dumps([[o]])); sys.exit(0)

# 4. Otherwise it is free text and we send exactly what was said.
print(json.dumps([[spoken]]))
' "$(cat)" "$1"
}

# Permission answers: anything that is not clearly a refusal counts as allow,
# since the user asked for the action in the first place.
voice_permission_reply() {
  python3 -c '
import re, sys
spoken = sys.argv[1].strip().lower()
# Word-boundary matching, not exact match: "no", "nope", "stop", "cancel"
# and "no stop" all have to read as refusals. An exact-match case statement
# silently allowed "no stop", which is the worst possible miss here.
REFUSAL = {"no","nope","nay","not","never","reject","deny","stop","cancel",
           "abort","negative","nothing","dont","nuh"}
words = re.findall(r"[a-z]+", spoken)
if any(w in REFUSAL for w in words):
    print("reject")
else:
    print("once")
' "$1"
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
  curl -sf --connect-timeout 5 -m "$PERLA_TURN_TIMEOUT" -X POST "$DAEMON/api/text" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $LOCAL_TOKEN" \
    -d "$(python3 -c "
import json, re, sys
print(json.dumps({'message': sys.argv[1], 'tier': int(sys.argv[2])}))
" "$text" "$tier")"
}

send_voice() {
  local audio_file="$1"
  local tier="$2"
  curl -sf --connect-timeout 5 -m "$PERLA_TURN_TIMEOUT" -X POST "$DAEMON/api/voice" \
    -H "Authorization: Bearer $LOCAL_TOKEN" \
    -F "audio=@$audio_file" \
    -F "tier=$tier"
}

# Answering a blocked turn. The daemon holds the same turn open while these
# block, so the response that comes back is the turn's real reply (or another
# prompt, if the model immediately hits one again).
send_question_answer() {
  local answers="$1" tier="$2" request_id="$3"
  curl -sf --connect-timeout 5 -m "$PERLA_TURN_TIMEOUT" -X POST "$DAEMON/api/question" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $LOCAL_TOKEN" \
    -d "$(python3 -c "import json,sys; print(json.dumps({'tier': int(sys.argv[1]), 'request_id': sys.argv[2], 'answers': json.loads(sys.argv[3])}))" \
        "$tier" "$request_id" "$answers")"
}

send_permission_answer() {
  local reply="$1" tier="$2" request_id="$3" message="$4"
  curl -sf --connect-timeout 5 -m "$PERLA_TURN_TIMEOUT" -X POST "$DAEMON/api/permission" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $LOCAL_TOKEN" \
    -d "$(python3 -c "import json,sys; print(json.dumps({'tier': int(sys.argv[1]), 'request_id': sys.argv[2], 'reply': sys.argv[3], 'message': sys.argv[4]}))" \
        "$tier" "$request_id" "$reply" "$message")"
}

# Normalize a tier selection into 1 or 2, whatever spelling it arrives as
# (voice argument "1"/"2", noctalia's "Tier 1"/"Tier 2" selection).
normalize_tier() {
  case "${1,,}" in
    1|"tier 1"|quick|"quick chat"|t1) echo 1 ;;
    2|"tier 2"|full|"full mode"|t2) echo 2 ;;
    *) echo 1 ;;
  esac
}

main() {
  local mode="${1:-hotkey}"
  local tier="$(normalize_tier "${2:-1}")"
  local input="${3:-}"

  if [ "$mode" = "hotkey" ]; then
    local choice
    choice="$(printf 'Tier 1\nTier 2\n' | noctalia dmenu -p "$PERLA_NAME")" || exit 0
    case "$choice" in
      "Tier 1") mode="voice"; tier=1 ;;
      "Tier 2") mode="voice"; tier=2 ;;
      *) exit 0 ;;
    esac
  fi

  if [ "$mode" = "voice" ]; then
    local audio_file="/tmp/$PERLA_NAME-input.wav"
    capture_audio "$audio_file"

    log "Sending audio to Perla..."
    local result
    result="$(send_voice "$audio_file" "$tier")" || {
      local rc=$?
      explain_failure "$rc" "voice"
      exit 1
    }

    local transcript response
    transcript="$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript',''))")"
    response="$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text',''))")"

    log "Heard: $transcript"

    # A blocked turn has no "text" — speaking it would say nothing and the turn
    # would die silently. Questions and permission prompts both come back on the
    # same turn, so speak the prompt, listen again, and post the answer. Loops
    # so a question that begets another question keeps going.
    local blocked
    blocked="$(echo "$result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('question' if d.get('question_required') else ('permission' if d.get('permission_required') else ''))
")"

    while [ -n "$blocked" ]; do
      local request_id
      request_id="$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('request_id',''))")"

      local spoken_prompt
      spoken_prompt="$(echo "$result" | voice_prompt)"
      log "Asking: $spoken_prompt"
      speak_via_daemon "$spoken_prompt"

      # Longer window than the opener — answering a question properly takes
      # more than five seconds.
      local reply_file="/tmp/$PERLA_NAME-reply.wav"
      capture_reply "$reply_file" 12

      if [ ! -s "$reply_file" ]; then
        local miss="I didn't catch that."
        log "No answer recorded."
        speak_via_daemon "$miss"
        notify -u low "$PERLA_NAME" "$miss"
        echo "$miss"
        rm -f "$reply_file"
        return 0
      fi

      # Transcribe the answer by re-posting it as a voice turn would cost a
      # whole model call; instead the daemon already returns whatever it
      # understood for the ORIGINAL turn, so ask for the answer transcript
      # via a dedicated short call.
      local answer_text
      answer_text="$(transcribe_file "$reply_file")" || answer_text=""

      if [ -z "$answer_text" ]; then
        local miss="I didn't catch that."
        log "Answer didn't transcribe."
        speak_via_daemon "$miss"
        notify -u low "$PERLA_NAME" "$miss"
        echo "$miss"
        rm -f "$reply_file"
        return 0
      fi
      log "Heard answer: $answer_text"

      if [ "$blocked" = "question" ]; then
        local answers
        answers="$(echo "$result" | voice_answer_for_question "$answer_text")"
        log "Answering question -> $answers"
        result="$(send_question_answer "$answers" "$tier" "$request_id")" || {
          local rc=$?; explain_failure "$rc" "answer"; rm -f "$reply_file"; exit 1; }
      else
        local decision message
        decision="$(voice_permission_reply "$answer_text")"
        log "Permission answer: '$answer_text' -> $decision"
        # A reject needs the same explicit instruction the web card sends.
        # OpenCode hands the message to the model, which then acknowledges in
        # its own voice; without it the turn can end on a bare "(no response)"
        # and a spoken refusal reads as Perla having ignored the user.
        if [ "$decision" = "reject" ]; then
          message="The user rejected this action by voice (they said '$answer_text'). Do not retry it. Acknowledge briefly and move on."
        else
          message="The user allowed this by voice (they said '$answer_text')."
        fi
        result="$(send_permission_answer "$decision" "$tier" "$request_id" \
                  "$message")" || {
          local rc=$?; explain_failure "$rc" "answer"; rm -f "$reply_file"; exit 1; }
      fi
      rm -f "$reply_file"

      blocked="$(echo "$result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('question' if d.get('question_required') else ('permission' if d.get('permission_required') else ''))
")"
    done

    response="$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text',''))")"
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
    local rc=$?
    explain_failure "$rc" "text"
    exit 1
  }
  response="$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text',''))")"

  echo "$response"
  speak_via_daemon "$response"
  notify -u low "$PERLA_NAME" "$response"
}

main "$@"
