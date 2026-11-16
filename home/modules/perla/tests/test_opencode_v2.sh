#!/usr/bin/env bash
# Tests for the OpenCode v2 client layer (the v2.2.1 breakage).
#
# THE BUG. opencode updated to v2.2.1 and every Perla turn died with
# "Expecting value: line 1 column 1 (char 0)": v2 (a) answers only after HTTP
# basic auth with a per-start random password, (b) moved all routes under
# /api/, (c) made the message POST async (POST /prompt returns the user's
# inbox entry; the turn is over only when a type:"idle" entry with an outcome
# appears in the session's message list), and (d) reformed questions into
# forms and permissions into session-scoped requests with a `decision` reply.
# Each behaviour was verified live against 127.0.0.1:13101 on v2.2.1; these
# tests pin the daemon's side of each mapping so the next opencode bump shows
# up as a red suite instead of a silent outage.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$HERE/../perla-companion.py"
NIX="$HERE/../../perla.nix"
CFG="$HERE/../perla-config.nix"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

echo "=== 1. every OpenCode call carries basic auth (v2 requirement) ==="
check=$(python3 - "$PY" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
bare = re.findall(r'127\.0\.0\.1:\{[^}]+\}/(?!api/)(session|question|permission|global|event)[^"\']*', src)
print("bare:" + ("|".join(bare) if bare else "none"))
print("env:%s" % ("yes" if 'os.environ.get("PERLA_OPENCODE_PASSWORD"' in src else "no"))
# Per-callsite: every curl argv list that points at an OpenCode server
# (127.0.0.1:{port...} — NOT the daemon itself, which is a literal port)
# must thread the OPENCODE_AUTH args in, or that one call would 401.
missing = []
for m in re.finditer(r'127\.0\.0\.1:\{[^}]+\}', src):
    # Walk back to the start of the enclosing argv list / call.
    head = src[max(0, m.start() - 900):m.start()]
    start = head.rfind('["curl"')
    if start < 0:
        continue
    if "*OPENCODE_AUTH" not in head[start:]:
        missing.append(src[m.start():m.end() + 40].split('"')[1])
print("noauth:%d" % len(missing))
print("noauth_detail:%s" % ("|".join(missing)[:300]))
PY
)
bare=$(printf '%s\n' "$check" | sed -n 's/^bare://p')
envset=$(printf '%s\n' "$check" | sed -n 's/^env://p')
noauth=$(printf '%s\n' "$check" | sed -n 's/^noauth://p')
noauth_detail=$(printf '%s\n' "$check" | sed -n 's/^noauth_detail://p')
if [ "$bare" = "none" ]; then ok "no v1 paths left"; else
  bad "no v1 paths left" "bare OpenCode paths remain: $bare"
fi
if [ "$noauth" = "0" ]; then
  ok "every OpenCode curl call carries basic auth"
else
  bad "every OpenCode curl call carries basic auth" \
      "$noauth call(s) missing OPENCODE_AUTH (a v2 server 401s them): $noauth_detail"
fi
[ "$envset" = "yes" ] && ok "password comes from PERLA_OPENCODE_PASSWORD" \
  || bad "password comes from PERLA_OPENCODE_PASSWORD" "no os.environ read for PERLA_OPENCODE_PASSWORD"

echo
echo "=== 2. nix wires ONE password to both server wrappers and the daemon ==="
pw=$(python3 - "$NIX" "$CFG" <<'PY'
import sys
nix, cfg = [open(p).read() for p in sys.argv[1:]]
print("count:%d" % nix.count('OPENCODE_SERVER_PASSWORD="${cfg.opencode_password}"'))
print("daemon:%s" % ("yes" if 'PERLA_OPENCODE_PASSWORD=${cfg.opencode_password}' in nix else "no"))
print("option:%s" % ("yes" if "opencode_password" in cfg else "no"))
PY
)
cnt=$(printf '%s\n' "$pw" | sed -n 's/^count://p')
[ "$cnt" -ge 2 ] && ok "both OpenCode server wrappers export the password" \
  || bad "both OpenCode server wrappers export the password" "exports found: $cnt"
[ "$(printf '%s\n' "$pw" | sed -n 's/^daemon://p')" = "yes" ] \
  && ok "daemon receives PERLA_OPENCODE_PASSWORD" \
  || bad "daemon receives PERLA_OPENCODE_PASSWORD" "missing Environment entry in the perla-companion service"
[ "$(printf '%s\n' "$pw" | sed -n 's/^option://p')" = "yes" ] \
  && ok "opencode_password option exists" \
  || bad "opencode_password option exists" "not found in perla-config.nix"

echo
echo "=== 3. the async prompt turn is completed via the idle entry ==="
behaviour=$(python3 - "$PY" <<'PY'
import json, sys, threading, types
src = open(sys.argv[1]).read()
lines = src.split("\n")

def block(sig):
    start = next((i for i, l in enumerate(lines) if l.strip().startswith(sig)), None)
    if start is None:
        return None
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = start
    for i in range(start + 1, len(lines)):
        if lines[i].strip() and (len(lines[i]) - len(lines[i].lstrip())) <= indent:
            break
        end = i
    return "\n".join(lines[start:end + 1])

need = [block(s) for s in [
    "def _worker_run_turn", "def _await_turn_reply", "def _fetch_messages_once",
    "def _abort_session", "def _parse_message_response",
]]
if not all(need):
    print("MISSING")
    sys.exit(0)

class FakeTurn:
    def __init__(self):
        self.tier = 1; self.sid = "ses_x"; self.port = 13101; self.body = "{}"
        self.interrupted = False; self.result = None; self.finished = False
        self.began = True; self.cleanup_paths = None
        self.cond = threading.Condition()

import time as _time, subprocess as _sp
POSTED = []
CALLS = []
def fake_run(argv, **kw):
    CALLS.append(list(argv))
    joined = " ".join(argv)
    if "/prompt" in joined:
        POSTED.append(json.loads(kw.get("input")))
        return types.SimpleNamespace(returncode=0, stdout=json.dumps(
            {"data": {"id": "msg_u", "time": {"created": 1000}, "type": "user"}}))
    if "/interrupt" in joined:
        return types.SimpleNamespace(returncode=0, stdout="{}")
    if "/message" in joined:
        # First poll: still running. Second: idle with the assistant reply.
        if not POSTED_DONE[0]:
            POSTED_DONE[0] = True
            return types.SimpleNamespace(returncode=0, stdout=json.dumps({"data": []}))
        return types.SimpleNamespace(returncode=0, stdout=json.dumps({"data": [
            {"id": "msg_i", "type": "idle", "time": {"created": 1100}, "outcome": "succeeded"},
            {"id": "msg_a", "type": "assistant", "content": [
                {"type": "text", "text": "all done"}], "time": {"completed": 1090}},
            {"id": "msg_u", "type": "user", "time": {"created": 1000}},
        ]}))
    raise AssertionError("unexpected curl: " + joined)

POSTED_DONE = [False]
ns = {
    "OPENCODE_AUTH": [], "TURN_TIMEOUT_SECONDS": 5, "INTERRUPTED_REPLY": "Stopped.",
    "time": _time, "subprocess": types.SimpleNamespace(run=fake_run, TimeoutExpired=_sp.TimeoutExpired),
    "json": json, "_abort_session": lambda turn: CALLS.append(["abort-marker"]),
    "_parse_message_response": lambda data, tier: ("parsed:" + " ".join(
        c.get("text", "") for c in data.get("content") if c.get("type") == "text"),
        False, False, False, None),
    "_finalize_turn": lambda turn: None,
    "print": lambda *a, **k: None,
}
exec(need[0], ns)   # _worker_run_turn
exec(need[1], ns)   # _await_turn_reply
exec(need[2], ns)   # _fetch_messages_once
turn = FakeTurn()
ns["_worker_run_turn"](turn)
text = turn.result[0] if turn.result else None
print("text:%s" % text)
print("body_files:%s" % json.dumps(POSTED[0].get("files")) if POSTED else "no post")
print("body_model:%s" % ("absent" if POSTED and "model" not in POSTED[0] else "present"))
print("prompted:%s" % ("yes" if POSTED and any("/prompt" in " ".join(c) for c in CALLS) else "no"))
PY
)
[ "$(echo "$behaviour" | grep -c MISSING)" -eq 0 ] || { bad "v2 turn worker extracted" "needed blocks missing from perla-companion.py"; exit 0; }
[ "$(echo "$behaviour" | sed -n 's/^text://p')" = "parsed:all done" ] \
  && ok "idle entry ends the turn and the assistant reply is parsed" \
  || bad "idle entry ends the turn" "worker result: $(echo "$behaviour" | sed -n 's/^text://p')"
[ "$(echo "$behaviour" | sed -n 's/^prompted://p')" = "yes" ] \
  && ok "the message POST goes to /api/session/{sid}/prompt" \
  || bad "the message POST goes to the prompt endpoint" "no /prompt POST observed"
[ "$(echo "$behaviour" | sed -n 's/^body_model://p')" = "absent" ] \
  && ok "v2 prompt body omits the model key (set per tier in config)" \
  || bad "v2 prompt body omits the model key" "model still attached to the prompt body"
[ "$(echo "$behaviour" | sed -n 's/^body_files://p')" != "no post" ] \
  && ok "a prompt body was built" \
  || bad "a prompt body was built" "worker never issued the prompt POST"

echo
echo "=== 3b. an aborted turn's idle cannot end the turn that superseded it ==="
behaviour=$(python3 - "$PY" <<'PY'
import json, sys, threading, types, time
src = open(sys.argv[1]).read()
lines = src.split("\n")

def block(sig):
    start = next((i for i, l in enumerate(lines) if l.strip().startswith(sig)), None)
    if start is None:
        return None
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = start
    for i in range(start + 1, len(lines)):
        if lines[i].strip() and (len(lines[i]) - len(lines[i].lstrip())) <= indent:
            break
        end = i
    return "\n".join(lines[start:end + 1])

need = [block(s) for s in ["def _await_turn_reply", "def _fetch_messages_once"]]
if not all(need):
    print("MISSING"); sys.exit(0)

class FakeTurn:
    def __init__(self):
        self.tier = 1; self.sid = "ses_x"; self.port = 13101
        self.interrupted = False; self.cond = threading.Condition()

POLLS = [
    # A previous turn's SUCCEEDED idle sits behind our prompt in the list but
    # within the old same-second window — ordering, not wall clock, must
    # reject it. Its prompt is outside the list window, so the superseded
    # scan alone cannot.
    [{"id": "msg_u2", "type": "user", "time": {"created": 2000}},
     {"id": "msg_i0", "type": "idle", "time": {"created": 1999}, "outcome": "succeeded"},
     {"id": "msg_a0", "type": "assistant", "time": {"created": 1998}, "content": [
         {"type": "text", "text": "old reply"}]}],
    # Turn 1's abort-idle lands NEWER than our prompt (same wall-clock second)
    # with turn 1's "Stopped." reply behind it.
    [{"id": "msg_i1", "type": "idle", "time": {"created": 2001}, "outcome": "interrupted"},
     {"id": "msg_u2", "type": "user", "time": {"created": 2000}},
     {"id": "msg_a1", "type": "assistant", "time": {"created": 1999}, "content": [
         {"type": "text", "text": "Stopped."}]}],
    # Our own run finishes.
    [{"id": "msg_i2", "type": "idle", "time": {"created": 2002}, "outcome": "succeeded"},
     {"id": "msg_a2", "type": "assistant", "time": {"created": 2001}, "content": [
         {"type": "text", "text": "real reply"}]},
     {"id": "msg_u2", "type": "user", "time": {"created": 2000}},
     {"id": "msg_i1", "type": "idle", "time": {"created": 1999}, "outcome": "interrupted"}],
]
seen = []
def fake_run(argv, **kw):
    if "/message" in " ".join(argv):
        seen.append(1)
        return types.SimpleNamespace(returncode=0, stdout=json.dumps(
            {"data": POLLS[min(len(seen), len(POLLS)) - 1]}))
    raise AssertionError("unexpected curl: " + " ".join(argv))

ns = {
    "OPENCODE_AUTH": [], "TURN_TIMEOUT_SECONDS": 5, "INTERRUPTED_REPLY": "Stopped.",
    "time": types.SimpleNamespace(time=time.time, sleep=lambda s: None),
    "subprocess": types.SimpleNamespace(run=fake_run),
    "json": json, "_abort_session": lambda turn: None,
    "_parse_message_response": lambda data, tier: ("parsed:" + " ".join(
        c.get("text", "") for c in data.get("content") if c.get("type") == "text"),
        False, False, False, None),
    "print": lambda *a, **k: None,
}
exec(need[0], ns); exec(need[1], ns)
turn = FakeTurn()
text = ns["_await_turn_reply"](turn, {"id": "msg_u2", "time": {"created": 2000}})[0]
print("text:%s" % text)
print("polls:%s" % len(seen))
PY
)
[ "$(echo "$behaviour" | grep -c MISSING)" -eq 0 ] || { bad "interrupt race fixture extracted" "needed blocks missing"; exit 0; }
[ "$(echo "$behaviour" | sed -n 's/^text://p')" = "parsed:real reply" ] \
  && ok "the superseding turn returns its own reply, not the aborted turn's idle" \
  || bad "superseding turn reply" "got: $(echo "$behaviour" | sed -n 's/^text://p')"
[ "$(echo "$behaviour" | sed -n 's/^polls://p')" -ge 3 ] \
  && ok "stale idles do not end the poll early" \
  || bad "stale idles ignored" "polling stopped after a stale idle"

echo
echo "=== 4. forms answer per field key; dismiss DELETES the form ==="
behaviour=$(python3 - "$PY" <<'PY'
import json, sys, types
src = open(sys.argv[1]).read()
lines = src.split("\n")

def block(sig):
    start = next((i for i, l in enumerate(lines) if l.strip().startswith(sig)), None)
    if start is None:
        return None
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = start
    for i in range(start + 1, len(lines)):
        if lines[i].strip() and (len(lines[i]) - len(lines[i].lstrip())) <= indent:
            break
        end = i
    return "\n".join(lines[start:end + 1])

ask = block("def _poll_pending_question")
res = block("def _resolve_question")
if not (ask and res):
    print("MISSING"); sys.exit(0)

FORM = {"data": [{"id": "frm_1", "sessionID": "ses_x", "title": "Questions", "fields": [
    {"key": "q0", "title": "Frontend", "description": "pick one", "type": "string",
     "options": [{"value": "A", "label": "A"}, {"value": "B", "label": "B"}], "custom": True},
    {"key": "q1", "title": "Extras", "type": "multiselect",
     "options": [{"value": "x", "label": "x"}]},
]}]}
captured = []
def fake_run(argv, **kw):
    joined = " ".join(argv)
    body = argv[list(argv).index("-d") + 1] if "-d" in argv else None
    captured.append((joined, body))
    payload = FORM if joined.endswith("/api/form") else "{}"
    return types.SimpleNamespace(returncode=0, stdout=json.dumps(payload))
ns = {
    "OPENCODE_AUTH": [], "subprocess": types.SimpleNamespace(run=fake_run),
    "json": json, "print": lambda *a, **k: None,
}
exec(ask, ns); exec(res, ns)

class T: sid = "ses_x"; port = 13101; question = None; answered_request_ids = set()
t = T()
q = ns["_poll_pending_question"](t)
shape = (q["request_id"], q["questions"][0]["question"], q["questions"][1]["multiple"])
print("shape:%s" % (shape,))
t.question = q
r = ns["_resolve_question"](t, "frm_1", [["B", "typed"], ["x"]])
post = captured[-1]
print("answer_body:%s" % post[1])
print("reply_url:%s" % ("yes" if "/form/frm_1/reply" in post[0] else "no"))
t2 = T(); t2.question = q
ns["_resolve_question"](t2, "frm_1", dismiss=True)
del_url = captured[-1][0]
print("delete_url:%s" % ("yes" if "/form/frm_1" in del_url and "DELETE" in del_url else "no"))
PY
)
[ "$(echo "$behaviour" | grep -c MISSING)" -eq 0 ] || { bad "form helpers extracted" "missing blocks"; exit 0; }
[ "$(echo "$behaviour" | sed -n 's/^shape://p')" = "('frm_1', 'Frontend', True)" ] \
  && ok "a form's fields become the question card payload" \
  || bad "a form's fields become the question payload" "got: $(echo "$behaviour" | sed -n 's/^shape://p')"
[ "$(echo "$behaviour" | sed -n 's/^answer_body://p' | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['answer']['q0'], ','.join(d['answer']['q1']))")" = "B x" ] \
  && ok "answers (labels + typed) map back onto field keys and values" \
  || bad "answers map onto field keys" "$(echo "$behaviour" | sed -n 's/^answer_body://p')"
[ "$(echo "$behaviour" | sed -n 's/^reply_url://p')" = "yes" ] \
  && ok "answers POST to /form/{id}/reply" \
  || bad "answers POST to /form/{id}/reply" "wrong endpoint"
[ "$(echo "$behaviour" | sed -n 's/^delete_url://p')" = "yes" ] \
  && ok "dismiss deletes the form (v2 rejects are DELETEs)" \
  || bad "dismiss deletes the form" "wrong dismiss endpoint"

echo
echo "=== 5. permissions reply with a v2 decision, session-scoped ==="
behaviour=$(python3 - "$PY" <<'PY'
import json, sys, types
src = open(sys.argv[1]).read()
lines = src.split("\n")

def block(sig):
    start = next((i for i, l in enumerate(lines) if l.strip().startswith(sig)), None)
    if start is None:
        return None
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = start
    for i in range(start + 1, len(lines)):
        if lines[i].strip() and (len(lines[i]) - len(lines[i].lstrip())) <= indent:
            break
        end = i
    return "\n".join(lines[start:end + 1])

poll = block("def _poll_pending_permission")
reso = block("def _resolve_permission")
if not (poll and reso):
    print("MISSING"); sys.exit(0)

PERMS = {"data": [{"id": "per_1", "sessionID": "ses_x", "action": "shell",
                   "resources": ["echo hello"], "metadata": {}}]}
captured = []
def fake_run(argv, **kw):
    joined = " ".join(argv)
    body = argv[list(argv).index("-d") + 1] if "-d" in argv else None
    captured.append((joined, body))
    payload = PERMS if joined.endswith(f"/api/session/{t.sid}/permission") else "{}"
    return types.SimpleNamespace(returncode=0, stdout=json.dumps(payload))
ns = {
    "OPENCODE_AUTH": [], "subprocess": types.SimpleNamespace(run=fake_run),
    "json": json, "print": lambda *a, **k: None,
}
exec(poll, ns); exec(reso, ns)
class T: sid = "ses_x"; port = 13101; answered_request_ids = set()
t = T()
entry = ns["_poll_pending_permission"](t)
print("mapped:%s" % ((entry["id"], entry.get("permission"), entry.get("patterns")),))
r = ns["_resolve_permission"](t, "per_1", "reject", "no")
url, body = captured[-1]
print("url:%s" % ("yes" if "/api/session/ses_x/permission/per_1/reply" in url else "no"))
print("body:%s" % body)
print("body_decision:%s" % (json.loads(body).get("decision") if body else None))
PY
)
[ "$(echo "$behaviour" | grep -c MISSING)" -eq 0 ] || { bad "permission helpers extracted" "missing blocks"; exit 0; }
[ "$(echo "$behaviour" | sed -n 's/^mapped://p')" = "('per_1', 'shell', ['echo hello'])" ] \
  && ok "v2 action/resources surface under the UI's old names" \
  || bad "v2 action/resources mapped for the UI" "$(echo "$behaviour" | sed -n 's/^mapped://p')"
[ "$(echo "$behaviour" | sed -n 's/^url://p')" = "yes" ] \
  && ok "the reply posts to the session-scoped v2 endpoint (no ?directory=)" \
  || bad "the v2 permission reply endpoint" "wrong URL"
[ "$(echo "$behaviour" | sed -n 's/^body_decision://p')" = "reject" ] \
  && ok "the reply uses v2's decision field" \
  || bad "the reply uses v2's decision field" "body: $(echo "$behaviour" | sed -n 's/^body://p')"

echo
echo "=== 6. an idle turn is a session the active map has dropped ==="
behaviour=$(python3 - "$PY" <<'PY'
import json, sys, types, time
src = open(sys.argv[1]).read()
lines = src.split("\n")
start = next(i for i, l in enumerate(lines) if l.strip().startswith("def _wait_session_idle"))
indent = len(lines[start]) - len(lines[start].lstrip())
end = start
for i in range(start + 1, len(lines)):
    if lines[i].strip() and (len(lines[i]) - len(lines[i].lstrip())) <= indent:
        break
    end = i
ns = {
    "IDLE_WAIT_SECONDS": 0.01, "IDLE_WAIT_TIMEOUT": 1,
    "OPENCODE_AUTH": [], "time": time,
    "subprocess": types.SimpleNamespace(run=lambda argv, **kw: types.SimpleNamespace(
        returncode=0, stdout=json.dumps({"data": {"ses_other": {"type": "running"}}}))),
    "json": json,
}
class T: sid = "ses_x"; port = 13101
turn = T()
rr = list(lines[start:end + 1])
exec("\n".join(rr), ns)
print("idle:%s" % ns["_wait_session_idle"](turn))
PY
)
[ "$(echo "$behaviour" | sed -n 's/^idle://p')" = "True" ] \
  && ok "idle detection uses /api/session/active" \
  || bad "idle detection uses /api/session/active" "got: $behaviour"

echo
echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
