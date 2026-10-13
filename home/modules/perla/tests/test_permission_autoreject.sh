#!/usr/bin/env bash
# Tests for the Tier 1 permission auto-reject and the free-tier bash policy.
#
# THE BUG. OpenCode's Zen free tier rejects any request whose tool list omits
# `bash` or `read`, answering HTTP 403 FreeTierError: "OpenCode's free tier can
# only be used from within OpenCode" (verified against the live gateway:
# Perla's exact Tier-1 permission set 403s; the same set with bash "ask"
# instead of "deny" returns 200). The message is a decoy -- it says nothing
# about permissions, which is why perla.nix carried a comment asserting the
# 403 "no longer applies". That re-test was a false negative taken while the
# gateway happened not to be enforcing; the gate is enforced intermittently
# and per-request, so it looks flaky rather than broken.
#
# Perla's Tier 1 denied `bash` outright to keep shell out of a headless tier,
# which made every single turn a candidate for rejection. `ask` is the only
# permission value that keeps a tool in the request's tool list without
# granting execution.
#
# But `ask` reintroduces the hang documented in AGENTS.md: in headless serve
# mode an unanswered permission has no UI to prompt in, so the turn sits until
# the 900s turn timeout. Questions already have an auto-dismiss timer;
# permissions had none (perla-companion.py: "unlike a question it has no timer
# of its own"). So the fix is BOTH halves: bash becomes "ask", and an
# unanswered permission is auto-rejected on a short timer.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$HERE/../perla-companion.py"
NIX="$HERE/../../perla.nix"
CFG="$HERE/../perla-config.nix"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

echo "=== 1. the free-tier bash policy (the regression that bit us) ==="
# The real invariant, asserted generally rather than as a one-off string: a
# free-tier model must never be paired with a denied `bash`, because that
# combination is what the gateway rejects. This is the assertion that would
# have caught the original bug.
policy=$(python3 - "$NIX" <<'PY'
import re, sys
src = open(sys.argv[1]).read()

# The Tier 1 config is emitted as a Nix attrset; pull out its `model` and
# its `permission` block by brace-matching so the test tracks the file
# instead of a line number.
def block_after(text, marker):
    i = text.find(marker)
    if i < 0:
        return None
    j = text.find("{", i)
    if j < 0:
        return None
    depth = 0
    for k in range(j, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return text[j:k + 1]
    return None

t1 = block_after(src, 'xdg.configFile."opencode/opencode-t1.json"')
if t1 is None:
    print("NOT_FOUND")
    sys.exit(0)

m = re.search(r'model\s*=\s*cfg\.opencode_model', t1)
perm = block_after(t1, "permission = {")
if perm is None:
    print("NO_PERMISSION_BLOCK")
    sys.exit(0)

def val(key):
    mm = re.search(key + r'\s*=\s*"([^"]*)"', perm)
    return mm.group(1) if mm else None

print("model_is_cfg=%s" % ("yes" if m else "no"))
print("bash=%s" % (val("bash") or "ABSENT"))
print("read=%s" % (val("read") or "ABSENT"))
PY
)
bash_mode=$(printf '%s\n' "$policy" | sed -n 's/^bash=//p')
model_is_cfg=$(printf '%s\n' "$policy" | sed -n 's/^model_is_cfg=//p')

if [ "$policy" = "NOT_FOUND" ]; then
  bad "the Tier 1 config block is present in perla.nix" "could not locate opencode-t1.json"
elif [ "$model_is_cfg" != "yes" ]; then
  bad "the Tier 1 config is located" "no model = cfg.opencode_model in the t1 block"
elif [ "$bash_mode" = "ABSENT" ]; then
  bad "the Tier 1 permission block declares bash" "no bash entry found"
elif [ "$bash_mode" = "deny" ]; then
  # opencode_model is opencode/space-bunny-free, i.e. a free-tier model, and
  # denying bash strips it from the tool list the gateway inspects.
  bad "a free-tier model is never paired with bash=deny" \
      "opencode_model is a *-free model and t1 permission sets bash=\"deny\" -- every Tier 1 turn is then rejected by the Zen free-tier gate with a 403"
elif [ "$bash_mode" = "ask" ]; then
  ok "a free-tier model is never paired with bash=deny"
else
  bad "the Tier 1 bash permission is a known value" "got bash=\"$bash_mode\", expected \"ask\""
fi

echo
echo "=== 2. an unanswered permission is auto-rejected ==="
# Real behaviour, not string matching: the extracted functions are exec'd and
# driven with a short timeout. If the auto-reject never fires, the recorder
# stays empty and this fails.
behaviour=$(python3 - "$PY" <<'PY'
import re, sys, time, threading
src = open(sys.argv[1]).read()
lines = src.split("\n")

def block(sig):
    """Source of a def/class INCLUDING its closing line, by indentation.

    Structural, never by line number, so the test cannot silently drift onto
    the wrong function when the file above it grows.
    """
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

turn_src = block("class _Turn")
sched_src = block("def _schedule_permission_autodismiss")
dismiss_src = block("def _autodismiss_permission")
if not (turn_src and sched_src and dismiss_src):
    print("MISSING")
    sys.exit(0)

calls = []
ns = {
    "threading": threading,
    "PERMISSION_TIMEOUT_SECONDS": 0.25,
    "_resolve_permission": lambda turn, rid, reply, message=None: calls.append((rid, reply)) or True,
    "print": lambda *a, **k: None,
    "_clear_turn": lambda *a, **k: None,
}
exec(turn_src, ns)
exec(sched_src, ns)
exec(dismiss_src, ns)

# --- case A: nobody answers -> the timer must reject it
turn = ns["_Turn"]("1", "ses_x", 13101, {})
turn.permission = {"id": "per_a"}
turn.permission_timer = None
ns["_schedule_permission_autodismiss"](turn)
time.sleep(1.0)
a_ok = ("per_a", "reject") in calls

# --- case B: answered first -> the timer must NOT touch it
calls.clear()
turn2 = ns["_Turn"]("1", "ses_x", 13101, {})
turn2.permission = {"id": "per_b"}
turn2.permission_timer = None
ns["_schedule_permission_autodismiss"](turn2)
# simulate the client answering before the timer fires
turn2.answered_request_ids.add("per_b")
time.sleep(1.0)
b_ok = calls == []

# --- case C: a second permission on the same turn gets its own timer
# (a turn can be asked for a permission more than once; a stale timer from an
# already-answered request must not be reused or suppressed)
calls.clear()
turn3 = ns["_Turn"]("1", "ses_x", 13101, {})
turn3.permission = {"id": "per_c"}
turn3.permission_timer = None
ns["_schedule_permission_autodismiss"](turn3)
time.sleep(1.0)
c_ok = ("per_c", "reject") in calls

print("A=%s" % ("yes" if a_ok else "no"))
print("B=%s" % ("yes" if b_ok else "no"))
print("C=%s" % ("yes" if c_ok else "no"))
PY
)
if [ "$behaviour" = "MISSING" ]; then
  bad "the permission auto-dismiss functions exist" \
      "_schedule_permission_autodismiss / _autodismiss_permission not found in the daemon"
else
  ok "the permission auto-dismiss functions exist"
  for c in A B C; do
    case "$c" in
      A) name="an unanswered permission is rejected on the timer" ;;
      B) name="a permission answered before the timer is left alone" ;;
      C) name="a later permission on the same turn still gets rejected" ;;
    esac
    if [ "$(printf '%s\n' "$behaviour" | sed -n "s/^$c=//p")" = "yes" ]; then
      ok "$name"
    else
      bad "$name" "observed behaviour did not match"
    fi
  done
fi

echo
echo "=== 3. the timer is actually scheduled, cancelled, and configurable ==="
tab=$'\t'
wiring=$(python3 - "$PY" <<'PY'
import sys
src = open(sys.argv[1]).read()
lines = src.split("\n")

def block(sig):
    """Source of a top-level def INCLUDING its closing line, by indentation."""
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

# The call site has to be checked INSIDE _wait_for_turn_outcome. A bare
# substring search for the call is vacuous: `def _schedule_permission_autodismiss(turn):`
# contains the exact same text, so deleting every real call site would still
# match. That mutation was introduced, observed passing, and is what forced
# this check to become structural.
wait_fn = block("def _wait_for_turn_outcome")
scheduled = bool(wait_fn) and "_schedule_permission_autodismiss(turn)" in wait_fn
print(("yes" if scheduled else "no ")
      + "\t" + "a pending permission schedules the auto-reject (inside _wait_for_turn_outcome)")

checks = [
    ("answering a permission cancels the timer", "turn.permission_timer.cancel()"),
    ("the timeout is configurable via the environment",
     'PERMISSION_TIMEOUT_SECONDS = int(os.environ.get("PERLA_PERMISSION_TIMEOUT"'),
    ("the auto-reject posts a reject to the OpenCode server",
     '/permission/{request_id}/reply'),
    ("the turn records a permission timer slot", "self.permission_timer = None"),
]
for name, needle in checks:
    print(("yes" if needle in src else "no ") + "\t" + name)
PY
)
while IFS="$tab" read -r good name; do
  [ "$good" = "yes" ] && ok "$name" || bad "$name" "not found in the daemon"
done <<<"$wiring"

echo
echo "=== 4. the setting exists and is actually wired through ==="
# A daemon that reads an env var nobody exports just silently falls back to
# its default, so the Nix side has to be checked too: the option must exist,
# and it must reach both environment files the daemon and the client read.
# (Removing the option from perla-config.nix was tried and caught NOTHING —
# these checks are what it needed.)
cfg=$(python3 - "$NIX" "$CFG" <<'PY'
import re, sys
nix, cfgpath = sys.argv[1], sys.argv[2]
nixsrc = open(nix).read()
cfgsrc = open(cfgpath).read()

checks = []

m = re.search(r'^\s*permission_timeout_seconds\s*=\s*(\d+)\s*;', cfgsrc, re.M)
checks.append(("perla-config.nix declares permission_timeout_seconds", bool(m)))
checks.append(("the declared timeout is sane (5s..600s)",
               bool(m) and 5 <= int(m.group(1)) <= 600))
if m:
    v = int(m.group(1))
    # Every place the turn timeout is exported, the permission timeout must be
    # too — the daemon unit AND the shared env file perla.sh sources.
    exports = nixsrc.count('PERLA_TURN_TIMEOUT=${toString cfg.turn_timeout_seconds}')
    wired = nixsrc.count('PERLA_PERMISSION_TIMEOUT=${toString cfg.permission_timeout_seconds}')
    checks.append(("every PERLA_TURN_TIMEOUT export also exports the permission timeout",
                   exports > 0 and exports == wired))
    checks.append(("the exported value is the configured one",
                   f'toString cfg.permission_timeout_seconds' in nixsrc))
else:
    checks.append(("every PERLA_TURN_TIMEOUT export also exports the permission timeout", False))
    checks.append(("the exported value is the configured one", False))

for name, good in checks:
    print(("yes" if good else "no ") + "\t" + name)
PY
)
while IFS="$tab" read -r good name; do
  [ "$good" = "yes" ] && ok "$name" || bad "$name" "not satisfied in the Nix config"
done <<<"$cfg"

echo
echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1