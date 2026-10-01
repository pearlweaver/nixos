#!/usr/bin/env bash
# Guards the CSS/JS splice.
#
# The realistic failure is not the split itself (that was verified
# byte-identical once) but a LATER edit: a second copy of a marker, or a
# string in the CSS/JS that closes its own block and silently truncates
# the page while everything else still looks fine.
#
# The durable invariant checked below is deployed == splice(sources), plus
# source sanity and a well-formed result. No golden file or sha256 is
# committed ON PURPOSE: it would fire a false alarm on the first legitimate
# stylesheet edit and get disabled.
#
# The byte-exactness of the parts is load-bearing too. The splice in
# perla.nix is a plain substring replace, so anything an editor or
# formatter normalises — a trailing newline, leading indentation, a
# strip() — lands in the deployed page verbatim and breaks byte-identity
# with the pre-split original. That class of breakage is invisible to a
# review of the assembled document, hence the explicit checks below.
#
# Sizes are compared in BYTES, not characters: these files contain
# multi-byte UTF-8, so a character count would be quietly wrong.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/.."
HTML="$SRC/perla-companion.html"
CSS="$SRC/perla-companion.css"
JS="$SRC/perla-companion.js"
DEPLOYED="$HOME/.config/perla/perla-companion.html"

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

# Counts non-overlapping matches; 0 when there are none. Reports MISSING
# rather than 0 for an unreadable file, so a deleted source can never be
# mistaken for a file that happens to contain no matches.
count_of() {
  if [ ! -f "$1" ]; then echo "MISSING"; return; fi
  grep -o "$2" "$1" 2>/dev/null | wc -l | tr -d ' '
}

# True (0) if the file's last byte is a newline.
has_trailing_newline() {
  [ -s "$1" ] || return 1
  [ "$(tail -c 1 -- "$1" | od -An -c | tr -d ' \n')" = '\n' ]
}

echo "=== 0. the three sources exist and are non-empty ==="
# Up front, because every check below reads these. An empty or absent part
# file is not a passing case: it makes the substring and count checks
# vacuously true and leaves the splice quietly producing a smaller page.
sources_ok=1
for f in "$HTML" "$CSS" "$JS"; do
  name=$(basename "$f")
  if [ ! -f "$f" ]; then
    bad "$name exists" "missing: $f — the splice reads all three sources; this file must be committed"
    sources_ok=0
  elif [ ! -s "$f" ]; then
    bad "$name is non-empty" "$name is 0 bytes ($f) — an emptied source splices to a silently smaller page"
    sources_ok=0
  else
    ok "$name exists and is non-empty ($(wc -c <"$f" | tr -d ' ') bytes)"
  fi
done

if [ "$sources_ok" -eq 0 ]; then
  echo
  echo "=================================="
  echo "  $pass passed, $fail failed"
  echo "  stopping: the source checks below would be vacuous"
  exit 1
fi

echo
echo "=== 1. marker integrity ==="
n=$(count_of "$HTML" '@@PERLA_CSS@@')
[ "$n" = 1 ] && ok "exactly one CSS marker" || bad "exactly one CSS marker" "found $n (want 1)"
n=$(count_of "$HTML" '@@PERLA_JS@@')
[ "$n" = 1 ] && ok "exactly one JS marker" || bad "exactly one JS marker" "found $n (want 1)"
n=$(count_of "$CSS" '@@PERLA_')
[ "$n" = 0 ] && ok "no markers leaked into the CSS" || bad "no markers leaked into the CSS" "found $n (want 0)"
n=$(count_of "$JS" '@@PERLA_')
[ "$n" = 0 ] && ok "no markers leaked into the JS" || bad "no markers leaked into the JS" "found $n (want 0)"

echo
echo "=== 2. neither part closes its own block ==="
n=$(count_of "$CSS" '</style>')
[ "$n" = 0 ] && ok "CSS contains no '</style>'" || bad "CSS contains no '</style>'" "found $n — it would close the block early and leave the rest of the stylesheet as page text"
n=$(count_of "$JS" '</script>')
[ "$n" = 0 ] && ok "JS contains no '</script>'" || bad "JS contains no '</script>'" "found $n — it would close the block early and leave the rest of the script as page text"
n=$(count_of "$JS" '<script')
[ "$n" = 0 ] && ok "JS contains no '<script'" || bad "JS contains no '<script'" "found $n — it would nest a script inside the spliced one"

echo
echo "=== 3. no trailing newline on the parts ==="
# A trailing \n would be spliced in as a blank line just before each
# closing tag. The page would still render, so only a byte comparison
# catches it — and an end-of-file fixer in an editor or formatter is
# exactly the sort of thing that adds one.
for f in "$CSS" "$JS"; do
  name=$(basename "$f")
  if has_trailing_newline "$f"; then
    bad "$name does not end with a newline" \
        "$name gained a trailing newline — an editor or formatter's end-of-file fixer probably ran on it. The splice is a plain substring replace, so that extra byte lands in the deployed page and breaks byte-identity with the pre-split original. Re-save without the fixer."
  else
    ok "$name does not end with a newline"
  fi
done

echo
echo "=== 4-9. the DEPLOYED file is the assembled one ==="
if [ ! -f "$DEPLOYED" ]; then
  echo "  SKIP  deployed file not found at $DEPLOYED"
  echo "        run: home-manager switch --flake .#thedreamdev"
  exit 0
fi

# Scratch is per-run: a fixed path is shared by concurrent runs, and a file
# left behind by an earlier run must never be what node parses below.
SCRATCH="$(mktemp -t perla-spliced-XXXXXX.js)" || exit 1
trap 'rm -f "$SCRATCH"' EXIT

results=$(python3 - "$DEPLOYED" "$HTML" "$CSS" "$JS" "$SCRATCH" <<'PYEOF'
import sys

deployed, html_path, css_path, js_path, scratch = sys.argv[1:6]

read = lambda p: open(p, "rb").read()
d, h, css, js = read(deployed), read(html_path), read(css_path), read(js_path)

# The same splice perla.nix performs: a plain substring replace of the two
# marker literals, no trimming, no newline appended. Comparing the deployed
# bytes against this is a source-relative correctness check — it needs no
# golden file and no magic line count, and it pins the markup wrapper too.
expected = h.replace(b"/* @@PERLA_CSS@@ */", css).replace(b"// @@PERLA_JS@@", js)


def block(b, open_tag, close_tag):
    """The single open..close region as raw bytes, or (None, why)."""
    no, nc = b.count(open_tag), b.count(close_tag)
    if no != 1:
        return None, f"expected exactly 1 {open_tag.decode()}, found {no}"
    if nc != 1:
        return None, f"expected exactly 1 {close_tag.decode()}, found {nc}"
    s, e = b.find(open_tag) + len(open_tag), b.find(close_tag)
    if e <= s:
        return None, f"{close_tag.decode()} does not follow {open_tag.decode()}"
    return b[s:e], ""


out = []

out.append((
    d == expected,
    "deployed page is byte-identical to the sources re-spliced",
    f"re-splicing the three sources gives {len(expected)} bytes, "
    f"deployed is {len(d)} bytes; first difference at byte "
    f"{next((i for i, (a, b) in enumerate(zip(expected, d)) if a != b), min(len(expected), len(d)))}",
))

out.append((css in d, "deployed page contains the full CSS body",
            "perla-companion.css does not appear verbatim in the deployed page"))
out.append((js in d, "deployed page contains the full JS body",
            "perla-companion.js does not appear verbatim in the deployed page"))
out.append((b"@@PERLA" not in d, "no unreplaced markers remain",
            "the deployed page still contains @@PERLA — the splice did not run, "
            "or ran on a source whose markers had moved"))

# Length equality against the source, not a magic threshold. `> 0` was the
# bug it replaces: an emptied CSS yields a 0-byte block, which is non-empty
# by no measure yet scores as "0 lines, looks fine".
for part, name, size in ((css, "CSS", "perla-companion.css"), (js, "JS", "perla-companion.js")):
    tag = b"<style>" if name == "CSS" else b"<script>"
    end = b"</style>" if name == "CSS" else b"</script>"
    got, why = block(d, tag, end)
    exp, why_exp = block(expected, tag, end)
    if got is None:
        out.append((False, f"deployed {name} block has the expected length",
                    f"could not locate the {name} block in the deployed page: {why}"))
        continue
    if exp is None:
        out.append((False, f"deployed {name} block has the expected length",
                    f"internal: could not locate the {name} block in the re-spliced sources: {why_exp}"))
        continue
    # The block is the part plus whatever the markup wraps it in (a newline
    # and the closing tag's indentation); the wrapper comes from expected,
    # so the delta is stated rather than hardcoded.
    low = name.lower()
    wrapper = len(exp) - len(part)
    how = " plus %d bytes of markup wrapper" % wrapper if wrapper else ""
    detail = ("%s block is %d bytes; re-spliced from the %s source it is %d bytes "
              "(source is %d bytes%s)" % (low, len(got), low, len(exp), len(part), how))
    out.append((len(got) == len(exp), f"deployed {name} block has the expected length", detail))

got_js, why_js = block(d, b"<script>", b"</script>")
out.append((got_js is not None, "located the <script> block",
            f"could not locate the <script> block in the deployed page: {why_js}"))

script_written = False
if got_js is not None:
    open(scratch, "wb").write(got_js)
    script_written = True

for good, msg, detail in out:
    print("PASS" if good else "FAIL", msg, "", detail, sep="|")

# Sentinel, consumed by the shell to gate the node parse check. Without it a
# page with no <script> block would still run node on whatever the scratch
# path held and report a bogus pass.
if script_written:
    print("SCRATCH|spliced-script-extracted|")
PYEOF
)
py_status=$?

if [ "$py_status" -ne 0 ] || [ -z "$results" ]; then
  bad "deployed-file checks ran" \
      "the python helper failed (exit $py_status) and produced no results — the output below is not a verdict"
else
  script_extracted=0
  while IFS='|' read -r verdict name _marker detail; do
    if [ "$verdict" = SCRATCH ]; then
      script_extracted=1
      continue
    fi
    if [ "$verdict" = PASS ]; then
      ok "$name"
    elif [ "$verdict" = FAIL ]; then
      bad "$name" "${detail:-the deployed page does not match the sources; re-run with home-manager switch}"
    else
      bad "malformed check result" "unrecognised verdict '$verdict' for '$name'"
    fi
  done <<< "$results"

  if [ "$script_extracted" -eq 1 ]; then
    if node -e 'new Function(require("fs").readFileSync(process.argv[1],"utf8"))' "$SCRATCH" 2>"$SCRATCH.err"; then
      ok "spliced JS parses as valid JavaScript"
    else
      bad "spliced JS parses as valid JavaScript" \
          "node rejected the spliced script: $(head -3 "$SCRATCH.err" | tr '\n' ' ')"
    fi
    rm -f "$SCRATCH.err"
  fi
fi

echo
echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1