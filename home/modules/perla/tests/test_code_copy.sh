#!/usr/bin/env bash
# The per-code-block copy button must stay pinned in the corner.
#
# Reported bug: on a code block wider than the bubble, the button scrolled away
# with the code instead of staying put.
#
# Root cause: .code-copy-btn is position:absolute and lived INSIDE the <pre>.
# That <pre> is the horizontal scroll container, and an absolutely positioned
# descendant of a scroller is placed against the scroller's CONTENT and scrolls
# with it - so `right: 6px` meant 6px past the end of the longest line, not the
# visible edge. The fix gives the button a positioned ancestor that does not
# scroll (div.code-block) and makes the button a SIBLING of the pre.
#
# Two halves, because neither covers the other:
#
#   code_copy_dom_test.js  RUNS attachCodeBlockCopyButtons and asserts the DOM
#     shape. This half is not replaceable by grepping: `const wrap = pre`, which
#     aliases the wrapper back to the scroller, leaves every relevant line of
#     source in place and restores the bug exactly. A source assertion passes
#     while the behaviour is broken - that was observed, not theorised.
#   below                   reads the CASCADE, because jsdom has no layout and
#     cannot answer "does this element scroll".
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CSS="$HERE/../perla-companion.css"
JS="$HERE/../perla-companion.js"

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

# Print the body of the rule whose selector SET equals the arguments.
rule_body() { # rule_body <selector> [<selector>...]
  python3 - "$CSS" "$@" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
want = {s for s in sys.argv[2:]}
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    if {s.strip() for s in m.group(1).split(",")} == want:
        print(" ".join(m.group(2).split()))
        break
PY
}

echo "=== behaviour: the button must not end up inside the scroller ==="
dom_out="$(node "$HERE/code_copy_dom_test.js" "$JS" 2>&1)"
dom_status=$?
n_dom="$(printf '%s\n' "$dom_out" | grep -c '^PASS')"
if [ "$dom_status" -eq 0 ]; then
  pass=$((pass + n_dom))
  printf '%s\n' "$dom_out" | grep '^PASS' | sed 's/^PASS\t/  PASS  /'
else
  fail=$((fail + 1))
  echo "  FAIL  the copy-button DOM harness"
  printf '%s\n' "$dom_out" | sed 's/^/        /'
fi

echo
echo "=== cascade: the pinned corner must not itself scroll ==="
# --- code-block copy button must not ride the horizontal scroll ---
# Reported: with a long line the copy button scrolled away with the code
# instead of staying pinned in the corner.
#
# Root cause: .code-copy-btn is position:absolute inside .prose pre, and that
# same <pre> is the scroll container (overflow-x: auto). An absolutely
# positioned descendant of a scroller is positioned against the scroller's
# CONTENT and scrolls with it, so `right: 6px` meant 6px from the end of the
# longest line, not the visible edge.
#
# The invariant, asserted below: the button's nearest positioned ancestor must
# not itself scroll. jsdom has no layout, so this is asserted structurally —
# the DOM shape (button is a SIBLING of the pre, inside a wrapper) plus the
# cascade on that wrapper.
py_code_block_fn() { python3 - "$JS" <<'PY2'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"function attachCodeBlockCopyButtons\(container\) \{(.*?)\n    \}", src, re.S)
print(m.group(1) if m else "")
PY2
}
copy_fn="$(py_code_block_fn)"
# The wrapper is the whole point of the fix: it has to establish a positioning
# context that does not scroll.
cb="$(rule_body ".code-block")"
if printf '%s' "$cb" | grep -qE 'position:[[:space:]]*(relative|absolute|sticky)'; then
  ok ".code-block is the positioning context"
else
  bad ".code-block is the positioning context" \
      "without it the button resolves against some further ancestor and lands off in space - got: $cb"
fi
# Guarded on the rule existing: an empty body contains no "overflow", so a bare
# grep for it would pass on the very absence of the rule.
if [ -z "$cb" ]; then
  bad ".code-block does not scroll (it is the fixed corner)" \
      "there is no .code-block rule, so there is no positioning context to pin to"
elif printf '%s' "$cb" | grep -q 'overflow'; then
  bad ".code-block does not scroll (it is the fixed corner)" \
      "if the wrapper scrolls the button drifts again - got: $cb"
else
  ok ".code-block does not scroll (it is the fixed corner)"
fi
# The <pre> must still be the thing that scrolls, or long lines wrap instead.
if rule_body ".prose pre" | grep -q 'overflow-x: auto'; then
  ok ".prose pre is still the horizontal scroller"
else
  bad ".prose pre is still the horizontal scroller" \
      "long code lines would wrap rather than scroll"
fi
# The reveal is driven by hovering the block, which is now the wrapper.
if grep -q '\.code-block:hover \.code-copy-btn' "$CSS" && \
   ! grep -q 'pre\.code-block-wrap:hover \.code-copy-btn' "$CSS"; then
  ok "hover reveals the copy button via the wrapper, not the scrolling pre"
else
  bad "hover reveals the copy button via the wrapper" \
      "a :hover on the scroller does not fire for the button once it is a sibling"
fi

echo
echo "=================================="
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
