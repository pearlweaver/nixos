#!/usr/bin/env bash
# Regression test for "Perla says it sent the file but nothing arrives".
#
# Root cause under test: _parse_message_response's schema-independent
# staged-file fallback is gated on `send_file_called`, which is only set by
# finding a part with type=="tool" whose name ends in "send_file" in the
# OpenCode POST /message response. Current OpenCode returns ONLY the final
# step's parts (step-start / text / step-finish), so that tool part is never
# present, the gate is permanently False, and the fallback never runs --
# leaving sent_file_ref None and the web UI's "file" key null.
#
# The fix must make the fallback reachable whenever the daemon itself staged
# a file during the turn, WITHOUT depending on OpenCode's response shape.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../perla-companion.py"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
rm -rf "$WORK"; mkdir -p "$WORK"

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail+1)); }

# Extract the real functions from the real source so the test cannot drift
# from the implementation. Boundaries are found STRUCTURALLY (by dedent), not
# by hardcoded line numbers, so editing the file cannot silently truncate the
# extracted code.
python3 - "$SRC" "$WORK/extracted.py" <<'PY'
import sys, re
lines = open(sys.argv[1]).read().split("\n")

def block(start_idx):
    """Return source from start_idx through the end of that top-level block."""
    out = [lines[start_idx]]
    for l in lines[start_idx + 1:]:
        if l.strip() and not l[0].isspace() and not l.lstrip().startswith("#"):
            break
        if l.strip() and l[0].isspace() and re.match(r"^\S", l):
            break
        out.append(l)
    return "\n".join(out)

def find(pat):
    return next(i for i, l in enumerate(lines) if re.match(pat, l))

out = [
    "import json, re, time, threading",
    "\n".join(lines[find(r"^_LAST_STAGED_LOCK = "):find(r"^_LAST_STAGED_TTL_SECONDS") + 1]),
    block(find(r"^def _record_staged_file")),
    block(find(r"^def _pop_recently_staged_file")),
    block(find(r"^def _parse_message_response")),
]
src = "\n\n".join(out) + "\n"
# Guard against a truncated extraction: the last statement of the parser must
# be the 5-tuple return ending in sent_file_ref.
last = [l for l in src.split("\n") if l.strip()][-1].strip()
assert last.endswith("sent_file_ref"), f"extraction truncated, ends: {last!r}"
assert src.count("def _pop_recently_staged_file") == 1
open(sys.argv[2], "w").write(src)
print("  extracted %d blocks, %d lines" % (len(out), src.count("\n")))
PY

# run_case <label> <response-json> <stage:yes|no> <expect: FILE|NONE>
run_case() {
  local label="$1" response="$2" stage="$3" expect="$4"
  local got
  got=$(RESPONSE="$response" STAGE="$stage" python3 - "$WORK/extracted.py" <<'PY'
import contextlib, io, json, os, runpy, sys
ns = runpy.run_path(sys.argv[1])
if os.environ["STAGE"] == "yes":
    ns["_record_staged_file"](2, "abc123", "probe.txt")
data = json.loads(os.environ["RESPONSE"])
# The parser logs to stdout; swallow it so only the verdict reaches the shell.
with contextlib.redirect_stdout(io.StringIO()):
    res = ns["_parse_message_response"](data, 2)
ref = res[4]
print("RESULT:" + (ref["id"] if ref else "NONE"))
PY
)
  got="${got##*RESULT:}"
  if [ "$expect" = "FILE" ]; then
    [ "$got" = "abc123" ] && ok "$label" || bad "$label" "expected the staged file id, got '$got'"
  else
    [ "$got" = "NONE" ] && ok "$label" || bad "$label" "expected no file, got '$got'"
  fi
}

# Case 1: the REAL shape OpenCode returns today — final step only, no tool
# part. The model got a real id from send_file, and the daemon staged the file
# in-process, so the parser must recover it via the fallback.
run_case "recovers the file from a final-step-only response (no tool part)" \
  '{"parts":[{"type":"step-start"},{"type":"text","text":"Sent. id: abc123"},{"type":"step-finish"}]}' \
  yes FILE

# Case 2: a genuine tool part with the JSON result inline still works via the
# primary path (this is the case the old code was built around).
run_case "still uses the primary path when a tool part IS present" \
  '{"parts":[{"type":"tool","tool":"file_send_file","state":{"status":"completed","output":"{\"ok\": true, \"id\": \"abc123\", \"filename\": \"probe.txt\"}"}}]}' \
  yes FILE

# Case 3: send_file found nothing, so the daemon staged nothing. The fallback
# must not invent a file out of nothing — this is what stops the relaxed gate
# from attaching a bogus download to an unrelated reply.
run_case "does not invent a file when nothing was staged" \
  '{"parts":[{"type":"step-start"},{"type":"text","text":"I could not find that file."},{"type":"step-finish"}]}' \
  no NONE

# Case 4: a prior turn's staged file must not leak into this turn's reply.
# The record is popped on use, so a second parse of the same turn finds none.
run_case "a popped record does not leak into a later turn" \
  '{"parts":[{"type":"step-start"},{"type":"text","text":"Second turn."},{"type":"step-finish"}]}' \
  no NONE

echo
echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
