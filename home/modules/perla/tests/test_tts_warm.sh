#!/usr/bin/env bash
# Guards for the warm TTS service (spec: docs/superpowers/specs/2026-10-14-tts-latency-design.md).
#
# Reads perla.nix as TEXT and matches attributes by brace-depth, so it tracks
# the file as it moves.
#
# Two things this suite is deliberately strict about, both learned the hard way:
#
#   1. Comments are stripped before anything is matched. A guard that greps raw
#      source is satisfied by PROSE: deleting `Wants = [ "perla-tts.service" ]`
#      and leaving `# Wants perla-tts.service` behind kept this suite at 9/9.
#      Only real code may satisfy a guard.
#
#   2. `#` is also legal inside every Nix string form, so stripping cannot be a
#      naive cut-to-end-of-line. check_lexer asserts the stripper against
#      fixtures, so a broken stripper goes red here instead of quietly
#      corrupting the text every other assertion matches against.
#
# Every assertion here must be observed failing against broken code before this
# suite is trusted.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# tests/ -> perla/ -> modules/. The home-manager module lives at
# home/modules/perla.nix, a sibling of the perla/ payload directory, NOT
# inside it.
NIX="$HERE/../../perla.nix"
# tests/ -> perla/, so the daemon sits one level up from the test dir.
PY="$HERE/../perla-companion.py"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; printf '        %s\n' "$2"; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# Emit `key=value` facts about perla.nix into $WORK/nix.txt. Each fact is
# True/False; the shell loop below turns them into assertions one by one, so a
# missing fact is a FAIL rather than a silently-skipped check.
collect() {
  python3 - "$NIX" > "$WORK/nix.txt" <<'PY'
import sys

src = open(sys.argv[1]).read()

# --- comment stripping -----------------------------------------------------
#
# A `#` starts a comment that runs to end of line — but only in CODE. Inside
# "..." and ''...'' it is an ordinary character. Cutting at every '#' would eat
# string contents, and this suite asserts ON string contents (the bind host,
# the port, the description), so that would corrupt the text being matched
# rather than merely lose coverage. Those two forms are all Nix has.
#
# `${...}` inside any string is real code again, comments included, so the
# scanner keeps a stack and pushes an "antiquote" frame with a brace counter.
def strip_comments(text):
    out = list(text)
    in_string = [False] * len(text)   # True where a char is inside a string
    # Every frame is a TUPLE. `kind` below is read as top[0], so a frame pushed
    # as the bare string "ind" reads as "i", is never recognised as a string,
    # and the scanner leaks state for the rest of the file — which silently
    # stops stripping every comment after the first string literal.
    frames = []   # ('dq',) | ('ind',) | ('anti', brace_depth)
    i, n = 0, len(text)
    while i < n:
        top = frames[-1] if frames else None
        kind = top[0] if top else "code"

        if kind == "anti":
            c = text[i]
            if c == "{":
                frames[-1] = ("anti", top[1] + 1)
            elif c == "}":
                if top[1] == 0:
                    frames.pop()
                else:
                    frames[-1] = ("anti", top[1] - 1)
            elif c == "#":
                while i < n and text[i] != "\n":
                    out[i] = " "; i += 1
                continue
            i += 1
            continue

        if kind != "code":
            c = text[i]
            if c == "\\" and kind != "ind":
                in_string[i] = True
                if i + 1 < n: in_string[i + 1] = True
                i += 2
                continue
            if kind == "dq" and c == '"':
                frames.pop(); i += 1; continue
            if kind == "ind":
                if text.startswith("'''", i):      # '' escape
                    i += 3; continue
                if text.startswith("''${", i):     # antiquote in ''-string
                    # Advance 4, not 3: ''${ is four characters. Stopping at 3
                    # leaves the '{' to be read as code, which bumps the brace
                    # depth to 1 so the matching '}' only decrements instead of
                    # closing — and the frame then swallows everything up to the
                    # next '}' in the file. One unclosed antiquote poisons every
                    # comment-stripping decision after it.
                    frames.append(("anti", 0)); i += 4; continue
                if text.startswith("''", i):       # end of ''-string
                    frames.pop(); i += 2; continue
            if c == "$" and text.startswith("${", i):
                frames.append(("anti", 0)); i += 2; continue
            in_string[i] = True
            i += 1
            continue

        # code
        if text.startswith("#", i):
            while i < n and text[i] != "\n":
                out[i] = " "; i += 1
            continue
        if text.startswith("''", i):
            frames.append(("ind",)); i += 2; continue
        if text[i] == '"':
            frames.append(("dq",)); i += 1; continue
        # No branch for a bare "'" in code, and that is deliberate — but NOT for
        # the reason the obvious one suggests. Nix has no character literals
        # (`nix-instantiate --eval -E "'a'"` is a syntax error), which is true
        # and is not the reason. A lone apostrophe can still appear in code,
        # because identifiers may contain one: the manual's grammar is
        # `identifier ~ [A-Za-z_][A-Za-z0-9_'-]*`, and both of these parse and
        # evaluate —
        #   $ nix-instantiate --eval -E "let foo'bar = 1; in foo'bar"
        #   1
        #   $ nix-instantiate --eval -E 'let x = { a'"'"'b = 1; }; in x.a'"'"'b'
        #   1
        #
        # So the char frame this branch used to push was not unreachable
        # machinery — it was corrupting valid Nix. On `let foo'bar = 1; # c`
        # the `'` in the identifier opened a "string", the `#` was masked as
        # that string's content instead of being stripped, and the comment
        # survived into the very text these assertions match against. Deleting
        # the frame fixed that; it did not remove dead code.
        #
        # What the branch WAS justified by was its fixture: `v = '#'; #gone`,
        # where `'#'` is a syntax error. Asserting on it made a non-Nix input
        # look covered, so the frame read as necessary long after it had gone
        # actively wrong. Neither the fixture nor the rationale it stood on
        # was valid; see LEXER_CASES for the fixtures that replaced them.
        i += 1
    return "".join(out), in_string

clean, in_string = strip_comments(src)

def fact(name, value):
    print(f"{name}={value}")

# The stripper underpins every assertion below, so it is asserted rather than
# trusted. If comment handling regresses, the other guards start matching prose
# again — these go red first.
# (name, input, expected). A comment is replaced by an equal run of spaces so
# the text keeps its shape and offsets — which is what keeps the in-string mask
# aligned with the original source.
LEXER_CASES = [
    ("line", "a = 1; #gone\nb = 2;\n", "a = 1;      \nb = 2;\n"),
    ("dq", 'x = "a # b"; #gone\n', 'x = "a # b";      \n'),
    ("ind", "y = ''\n#kept\n''; #gone\n", "y = ''\n#kept\n'';      \n"),
    ("anti_dq", 'z = "${a #gone\n}"; #gone\n', 'z = "${a      \n}";      \n'),
    ("anti_ind", "w = ''${a #gone\n}''; #gone\n", "w = ''${a      \n}'';      \n"),
    # Comment following an escaped antiquote (''${) inside a ''-string. The
    # comment is ordinary string content and must survive. This is the fixture
    # that catches the ''$-advance-by-3 bug DIRECTLY: with i += 3 the '{' is
    # left behind, the frame survives its own '}', and it then eats this
    # comment as if it were code. Without it the bug is only caught indirectly,
    # by every other assertion going red at once.
    ("ind_escape_anti", "p = ''lit''${x}# kept'';\n", "p = ''lit''${x}# kept'';\n"),
    # An apostrophe run long enough that the '''-escape and a plain ''-close
    # disagree about where the string ends. Per Nix, '' opens, then ''' is the
    # escape for a literal '', leaving '' to CLOSE — so `#kept` is code and must
    # be stripped. Drop the ''' branch and the run re-parses as close-then-
    # reopen, which swallows `#kept` as string content and keeps it. This is the
    # only fixture shape found that discriminates the branch; shorter runs
    # (''', '''a''') parse identically either way.
    ("ind_escape", "s = '''''''#kept'';\n", "s = '''''''        \n"),
    ("escape", 'u = "a\\" # b"; #gone\n', 'u = "a\\" # b";      \n'),
    # A '#' reached as the second half of a backslash pair. This IS valid Nix —
    # `nix-instantiate --eval -E '"a\#b"'` evaluates to "a#b", the backslash
    # simply dropped — so the escape branch is real coverage, not a synthetic
    # edge. What makes it worth its own fixture is the MASK invariant below: the
    # pair is consumed with i += 2, so nothing else in the scanner can flag the
    # '#' as string content. Without the marking in the escape branch this goes
    # red while the LEXER check alone still passes.
    ("escape_hash", 'u = "a\\#b"; #gone\n', 'u = "a\\#b";      \n'),
]
for name, case_in, case_out in LEXER_CASES:
    got, got_mask = strip_comments(case_in)
    fact(f"LEXER[{name}]", got == case_out)
    if got != case_out:
        print(f"LEXER_DETAIL[{name}]={got!r}", file=sys.stderr)
    # The two halves of the return value must stay aligned. A '#' that SURVIVED
    # stripping was inside a string literal, so the mask must say so at exactly
    # that offset. If the mask drifts — extra marks, missing marks, off-by-one
    # after a multi-char construct — this goes red instead of silently making
    # block_after skip or count the wrong braces.
    fact(f"MASK[{name}]", all(got_mask[i] for i, ch in enumerate(got) if ch == "#"))

def block_after(text, mask, marker):
    i = text.find(marker)
    if i < 0:
        return None
    j = text.find("{", i)
    if j < 0:
        return None
    depth = 0
    for k in range(j, len(text)):
        if mask[k]:
            continue                      # braces inside strings are not blocks
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return text[j:k + 1]
    return None

# The mask is not a second opinion about comments — it is what keeps a brace
# inside a string literal from ending an attribute block. block_after is its
# only consumer, so assert on that directly: this snippet's string holds a '}'
# that must NOT close the block. With the mask skipped, block_after returns at
# that '}' and both facts below go red.
MASK_SNIPPET = 'u = {\n  s = "}"; #gone\n  t = 2;\n};\n'
_mask_clean, _mask_bits = strip_comments(MASK_SNIPPET)
fact("MASK[string_brace_flagged]", _mask_bits[_mask_clean.index('"}"') + 1] is True)
fact("MASK[block_ignores_string_brace]",
     block_after(_mask_clean, _mask_bits, "u =") == '{\n  s = "}";      \n  t = 2;\n}')

unit = block_after(clean, in_string, "systemd.user.services.perla-tts")
fact("UNIT_FOUND", unit is not None)
if unit is None:
    sys.exit(0)

for key in ('Restart = "on-failure"', "RestartSec = 5", "Install.WantedBy",
            "default.target", "piper.http_server"):
    fact(f"UNIT_HAS[{key}]", key in unit)

# piper.http_server has no authentication of any kind. Binding it to loopback
# is the ONLY thing standing between the LAN and an open synthesis endpoint,
# so it gets its own guard rather than riding along on another assertion.
fact("UNIT_LOOPBACK", "--host 127.0.0.1" in unit)
fact("UNIT_NOT_WILDCARD", not any(
    bad_host in unit for bad_host in ("--host 0.0.0.0", "--host ::", "--host=0.0.0.0")))

# The port is a single source of truth: the unit's ExecStart and the daemon's
# PERLA_TTS_URL must both come from it, or they point at different servers.
fact("PORT_BINDING", "perlaTtsPort = 5066;" in clean)
fact("PORT_IS_DERIVED", clean.count("toString perlaTtsPort") == 2)

# Depth-1 closure builds an env that ImportErrors at runtime rather than
# failing the build, so the recursion is asserted directly.
fact("CLOSURE_RECURSES", "concatMap piperClosure" in clean)
fact("CLOSURE_START", "piperClosure (piperClosure" not in clean
                      and "piperClosure = p: [ p ] ++ lib.concatMap piperClosure" in clean)

# The site-packages directory moves when python moves. A hardcoded "python3.14"
# would ImportError on the next nixpkgs bump, behind a green suite.
fact("SITE_DERIVED", "perlaTtsSite" in unit and "python3.14" not in unit)
fact("SITE_FROM_INTERPRETER", "lib.versions.majorMinor pkgs.python3.version" in clean)

comp = block_after(clean, in_string, "systemd.user.services.perla-companion") or ""
# The companion must WANT the tts unit, never hard-couple it: a dead TTS
# service has to degrade to audio:null, not stop the daemon booting.
fact("COMP_WANTS", "Wants" in comp and "perla-tts.service" in comp)
fact("COMP_REQUIRES", "Requires" in comp and "perla-tts.service" in comp)
fact("COMP_TTS_URL", "PERLA_TTS_URL" in comp and "perlaTtsPort" in comp)
# PERLA_VOICE must reach the daemon; it was silently falling back to the
# hardcoded default because perla.env is not read by the unit.
fact("COMP_VOICE", "PERLA_VOICE=${cfg.voice_model}" in comp)
PY
}

# The stripper underpins every other assertion, so it gets fixtures rather
# than trust. If comment handling regresses, the guards below start matching
# prose again and these go red first.

collect

assert_fact() {
  if grep -qxF "$1=True" "$WORK/nix.txt"; then
    ok "$2"
  else
    bad "$2" "$3"
  fi
}

# For facts where True is the BAD outcome. Asserting `assert_fact` on one of
# these would assert the defect is present.
assert_not_fact() {
  if grep -qxF "$1=False" "$WORK/nix.txt"; then
    ok "$2"
  else
    bad "$2" "$3"
  fi
}

assert_fact UNIT_FOUND              "perla.nix defines systemd.user.services.perla-tts" "unit block not found"
for name in line dq ind anti_dq anti_ind ind_escape_anti escape escape_hash ind_escape; do
  assert_fact "LEXER[$name]" "comment stripper handles the '$name' Nix string form" "see LEXER_DETAIL on stderr"
  assert_fact "MASK[$name]" "in-string mask stays aligned through '$name'" "a surviving # was not flagged as string content"
done
assert_fact MASK[string_brace_flagged]     "a brace inside a string is flagged" "mask did not mark the string's '}'"
assert_fact MASK[block_ignores_string_brace] "block matching ignores a brace inside a string" "block_after closed on the string's '}'"
for key in 'Restart = "on-failure"' 'RestartSec = 5' 'Install.WantedBy' 'default.target' 'piper.http_server'; do
  assert_fact "UNIT_HAS[$key]" "perla-tts has $key" "not present in the unit block"
done
assert_fact UNIT_LOOPBACK           "perla-tts binds loopback only" "--host 127.0.0.1 absent"
assert_fact UNIT_NOT_WILDCARD       "perla-tts never binds a wildcard address" "a non-loopback --host is present"
assert_fact PORT_BINDING            "perlaTtsPort is 5066" "port binding missing or changed"
assert_fact PORT_IS_DERIVED         "port is derived, not repeated as a literal" "toString perlaTtsPort must appear twice (unit + companion)"
assert_fact CLOSURE_RECURSES        "piperClosure recurses" "closure is not recursive"
assert_fact CLOSURE_START           "piperClosure starts at piper-tts itself" "piperClosure definition changed"
assert_fact SITE_DERIVED            "PYTHONPATH is derived, not a literal python3.14" "perlaTtsSite missing or python3.14 hardcoded"
assert_fact SITE_FROM_INTERPRETER   "site path comes from the interpreter version" "majorMinor derivation missing"
assert_fact COMP_WANTS              "perla-companion Wants perla-tts.service" "no Wants on the tts unit"
assert_not_fact COMP_REQUIRES     "perla-companion does not hard-couple perla-tts.service" "a hard coupling would make a dead TTS unit fatal"
assert_fact COMP_TTS_URL            "perla-companion receives PERLA_TTS_URL (derived port)" "env var missing from the unit"
assert_fact COMP_VOICE              "perla-companion receives PERLA_VOICE (latent-bug fix)" "PERLA_VOICE missing from the unit"

# Source-level guards on the daemon. Same discipline as the Nix half: comments
# and docstrings are stripped before anything is matched, so a guard can never
# be satisfied by PROSE. A generate_tts whose docstring says "no longer spawns
# piper" must not pass NO_PIPER_SUBPROCESS while its body still shells out.
check_py_source() {
  python3 - "$PY" > "$WORK/py.txt" <<'PYX'
import io, re, sys, tokenize

src = open(sys.argv[1]).read()

def take(name):
    i = src.find("\ndef " + name + "(")
    if i < 0:
        return None
    rest = src[i + 1:]
    m = re.search(r"\n(?=\S)", rest)
    return rest[: m.start()] if m else rest

def code_only(text):
    """Drop comments and string literals, keeping executable tokens only.

    tokenize is used rather than a regex because the body is full of f-strings
    whose braces and quotes a cut-to-# scanner would mangle. It is allowed to
    raise rather than fall back to raw text: a silent fallback would quietly
    turn every guard below into a prose match.
    """
    toks = [t for t in tokenize.generate_tokens(io.StringIO(text).readline)
            if t.type not in (tokenize.COMMENT, tokenize.STRING)]
    return tokenize.untokenize(toks)

g = take("generate_tts")
print("FOUND" if g else "MISSING")
if g:
    body = code_only(g)
    # The regression guard that matters: the voice model must never be re-loaded
    # by spawning piper again. `subprocess` is NOT itself banned — the mux step
    # legitimately shells out to ffmpeg. What is being protected against is the
    # piper binary, its --model flag, and the --output-raw PCM pipe the old
    # body used. (The brief's own draft banned the bare word "subprocess",
    # which its own ffmpeg mux step satisfies — so it could never go green.)
    print(f"NO_PIPER_SUBPROCESS={'piper' not in body and '--model' not in body and 'output-raw' not in body}")
    # generate_tts must route synthesis through the warm service. It reaches
    # PERLA_TTS_URL via the _tts_wav transport helper rather than by naming the
    # env var itself, so either counts — what must not happen is going back to
    # inlining a synthesis call.
    print(f"USES_URL={'PERLA_TTS_URL' in body or '_tts_wav' in body}")
    # Writes must land via os.replace so a crash mid-mux cannot leave a
    # truncated mp3 that send_file would happily serve.
    print(f"ATOMIC={'os.replace' in body}")
print(f"CONFIG_URL={'PERLA_TTS_URL' in src}")

s = take("speak_locally")
print("SPEECH_FOUND" if s else "SPEECH_MISSING")
if s:
    sbody = code_only(s)
    # Assert on the exact string the old body shelled out to, not the bare
    # word "piper" — the word also occurs in prose, which would make the
    # guard permanently red and therefore meaningless.
    print(f"SPEECH_NO_PIPER={'piper --model' not in sbody}")
    # The hotkey path paid the same ~2.3 s model reload as generate_tts did.
    print(f"SPEECH_USES_HELPER={'_tts_wav' in sbody}")
    # pw-play needs a file path now instead of a raw pipe, so every exit path
    # must remove it or each hotkey turn leaks a wav.
    print(f"SPEECH_CLEANUP={'finally' in sbody and 'os.unlink' in sbody}")
PYX
  grep -q '^FOUND$' "$WORK/py.txt" \
    && ok "generate_tts is present in the daemon" \
    || bad "generate_tts is present in the daemon" "function not found"
  grep -q 'NO_PIPER_SUBPROCESS=True' "$WORK/py.txt" \
    && ok "generate_tts no longer spawns piper" \
    || bad "generate_tts no longer spawns piper" "still shells out — the 2.3 s model load is back"
  grep -q 'USES_URL=True' "$WORK/py.txt" \
    && ok "generate_tts uses PERLA_TTS_URL" \
    || bad "generate_tts uses PERLA_TTS_URL" "no reference to the env var or the transport helper"
  grep -q 'ATOMIC=True' "$WORK/py.txt" \
    && ok "generate_tts writes via os.replace" \
    || bad "generate_tts writes via os.replace" "non-atomic write can serve a truncated mp3"
  grep -q 'CONFIG_URL=True' "$WORK/py.txt" \
    && ok "daemon reads PERLA_TTS_URL at module scope" \
    || bad "daemon reads PERLA_TTS_URL at module scope" "config line missing"
  grep -q 'SPEECH_FOUND' "$WORK/py.txt" \
    && ok "speak_locally is present in the daemon" \
    || bad "speak_locally is present in the daemon" "function not found"
  grep -q 'SPEECH_NO_PIPER=True' "$WORK/py.txt" \
    && ok "speak_locally no longer spawns piper" \
    || bad "speak_locally no longer spawns piper" "still shells out — the hotkey still pays the model reload"
  grep -q 'SPEECH_USES_HELPER=True' "$WORK/py.txt" \
    && ok "speak_locally routes through the warm transport" \
    || bad "speak_locally routes through the warm transport" "not using _tts_wav"
  grep -q 'SPEECH_CLEANUP=True' "$WORK/py.txt" \
    && ok "speak_locally removes its temp wav on every path" \
    || bad "speak_locally removes its temp wav on every path" "temp wav leaks per hotkey turn"
}

check_py_source

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1