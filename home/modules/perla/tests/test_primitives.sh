#!/usr/bin/env bash
# Guards the PRIMITIVE layer in perla-companion.css - the one-name-per-widget
# section that replaced the hand-rolled variants.
#
# test_design_tokens.sh locks the palette and the flatness of four surfaces.
# test_scales.sh locks the type/shadow/stacking scales and the rule that colour
# is only spelled out inside :root. This one locks the two failure modes a
# migration actually produces:
#
#   1. A PRIMITIVE THAT DOES NOT EXIST - a class emitted by the JS that no rule
#      matches, so the element renders unstyled and nothing complains. Three
#      were already in the tree before any of this (.qac-stage, .tier-item,
#      .attach-file-chip-delivered); the first two are now resolved, not
#      tolerated.
#   2. RE-DUPLICATION - the same recipe written out again somewhere else, which
#      is how the file got here in the first place. Sections 3-5 assert the
#      collapses STAY collapsed.
#
# Every assertion is mutation-tested; see the note beside each.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CSS="$HERE/../perla-companion.css"
JS="$HERE/../perla-companion.js"
HTML="$HERE/../perla-companion.html"

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

# Print the body of the rule whose selector SET equals the arguments, so a rule
# written as `.a,\n.b` is found by either name - a single-name lookup failed on
# exactly that shape and reported a correct rule as missing.
#
# Defined up here rather than next to its first use: sections 3b and 8 both call
# it, and a helper introduced halfway down the file is not a helper.
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

for f in "$CSS" "$JS" "$HTML"; do
  [ -f "$f" ] || { echo "  FAIL  source exists" "not found: $f"; exit 1; }
done

echo "=== 1. no class is emitted that no rule can style ==="
# A dangling class is invisible: the element exists, the class is on it, and
# nothing renders differently. That is how .tier-item shipped.
#
# Only COMPLETE class attribute values are read. The markup is assembled by
# string concatenation in a few places (`"entry-" + kind`), and half-reading
# those would report "entry-" as a class that nothing styles.
#
# Mutation: add `orphan.className = "no-such-class";` to the JS -> red.
report=$(python3 - "$CSS" "$JS" "$HTML" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
js  = open(sys.argv[2], encoding="utf-8").read()
html = open(sys.argv[3], encoding="utf-8").read()
tokens = set()
def take(value):
    # Skip assembled values: a '+', '${' or backtick means this string is only
    # part of a class list, so its words are not classes on their own.
    if any(c in value for c in "+${`"):
        return
    for w in value.split():
        # A well-formed single class: starts alphanumeric, no dangling hyphen.
        if re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*[A-Za-z0-9]|[A-Za-z]", w):
            tokens.add(w)
for src, pat in ((html, r'class="([^"]*)"'),
                 (js,   r'class="([^"]*)"'),
                 (js,   r'className\s*=\s*"([^"]*)"'),
                 (js,   r"classList\.(?:add|remove|toggle)\(\s*\"([^\"]+)\"")):
    for m in re.finditer(pat, src):
        take(m.group(1))
known = set(re.findall(r"\.([A-Za-z][A-Za-z0-9_-]*)", css))
# A class the JS SELECTS on is a behaviour hook, not a style hook, and is
# allowed to carry no rule of its own. .copy-btn and .replay-btn are matched by
# the click-delegation closest() in the message-row handler, and since C3c
# neither has any styling left. Without this exemption the detector flagged two
# classes that are genuinely still load-bearing - the detector was right that
# they have no rule and wrong that that makes them dead.
hooked = set()
for pat in (r"closest\(\s*[\"']\.([A-Za-z][\w-]*)",
            r"querySelector(?:All)?\(\s*[\"']\.([A-Za-z][\w-]*)",
            r"matches\(\s*[\"']\.([A-Za-z][\w-]*)"):
    hooked |= set(re.findall(pat, js))
missing = sorted(tokens - known - hooked)
print(len(missing))
for x in missing:
    print("#   ." + x + (" (a behaviour hook)" if x in hooked else ""))
PY
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "every class in the markup has a matching rule ($count dangling)"
else
  bad "every class in the markup has a matching rule" "$report"
fi

echo
echo "=== 2. the primitives exist ==="
# Mutation: rename any of these selectors in the stylesheet -> red.
for t in divider divider-vertical scroll-area spinner empty status \
         input input-sunken textarea radio checkbox \
         btn-icon btn-icon-outline btn-icon-accent btn-icon-square \
         btn-icon-28 btn-icon-30 btn-icon-32 btn-icon-34 btn-icon-lg \
         btn btn-xs btn-sm btn-md btn-pill btn-block \
         btn-primary btn-outline btn-ghost btn-solid btn-destructive \
         btn-destructive-flat \
         badge badge-outline badge-solid badge-label; do
  # Match .name as a WHOLE token. A plain `\.name` also matches the `.checkbox`
  # inside `.radio, .checkbox`, so renaming only the standalone rule would have
  # left this assertion green - verified by mutation.
  if grep -qE "(^|[ ,])\.$t([ ,:{]|$)" "$CSS"; then
    ok ".$t is defined"
  else
    bad ".$t is defined" "no rule in the stylesheet"
  fi
done

echo
echo "=== 2b. the input collapse STAYS collapsed ==="
# The five boxed fields were five near-copies. Each of these selectors used to
# restate the border, radius, colour, font and focus ring.
# Mutation: add `.reminder-composer input[type="text"] { ... }` back -> red.
stripped=$(python3 -c "import re,sys;print(re.sub(r'/\*[\s\S]*?\*/','',open(sys.argv[1],encoding='utf-8').read()),end='')" "$CSS")
for legacy in \
  '.reminder-composer input[type="text"]' \
  '.reminder-composer input[type="datetime-local"], .reminder-composer select' \
  '.drive-new-folder-row input' \
  '.qa-input-row input' \
  '.dropdown-row' \
  '.qac-input' \
  '#textInput {'; do
  n=$(printf '%s' "$stripped" | grep -cF "$legacy" || true)
  if [ "$n" -eq 0 ]; then
    ok "$legacy is gone from the stylesheet"
  else
    bad "$legacy is gone from the stylesheet" "$n rule(s) remain"
  fi
done

# Every boxed field must actually carry the class, or it silently loses all
# styling when its old rule is deleted. This is the assertion that makes the
# deletions above safe.
for id in reminderTextInput reminderDueInput reminderRepeatInput \
          driveNewFolderInput qaInputField; do
  if grep -qE "<(input|select)[^>]*id=\"$id\"[^>]*class=\"[^\"]*\binput\b" "$HTML"; then
    ok "#$id carries .input"
  else
    bad "#$id carries .input" "no .input class on the element"
  fi
done
if grep -qE '<textarea[^>]*id="textInput"[^>]*class="[^"]*\btextarea\b' "$HTML"; then
  ok "#textInput carries .textarea"
else
  bad "#textInput carries .textarea" "no .textarea class on the composer"
fi
# The Quick Actions field sits on a card->popover gradient, so it needs the
# sunken background or it blends into the panel. Losing the modifier is a pure
# visual regression with no functional symptom, which is exactly why it needs
# an assertion.
if grep -qE '<input[^>]*id="qaInputField"[^>]*class="[^"]*\binput-sunken\b' "$HTML"; then
  ok "#qaInputField carries .input-sunken (it sits on a gradient panel)"
else
  bad "#qaInputField carries .input-sunken" \
      "without it the field takes --card and blends into the gradient behind it"
fi
# The question card's radios and checkboxes take their shape from the type.
if grep -q 'input.className = multiple ? "checkbox" : "radio";' "$JS"; then
  ok "the question option input picks .radio or .checkbox from its type"
else
  bad "the question option input picks .radio or .checkbox from its type" \
      "expected the ternary on input.className in perla-companion.js"
fi
# ...and the re-sync that reads the control back must not go through a class
# name again, or the next rename breaks the selected state silently.
if grep -q 'r.querySelector(".qac-input")' "$JS"; then
  bad "the option re-sync does not query by class" \
      "it still looks up .qac-input, which no longer exists"
else
  ok "the option re-sync queries by tag, not a class name"
fi

echo
echo "=== 3. the divider collapse STAYS collapsed ==="
# Three chrome dividers became .divider / .divider-vertical. .prose hr is
# deliberately excluded: a rule inside rendered markdown is prose.
#
# Comments are stripped before grepping. Each legacy name is still mentioned in
# the Primitives comment that explains what it replaced, and counting that
# mention as a live reference would make the assertion unsatisfiable.
# Mutation: reintroduce `.menu-divider { ... }` -> red.
stripped=$(python3 -c "import re,sys;print(re.sub(r'/\*[\s\S]*?\*/','',open(sys.argv[1],encoding='utf-8').read()),end='')" "$CSS")
for legacy in menu-divider editor-divider drive-toolbar-divider; do
  n=$(printf '%s' "$stripped" | grep -c "\.$legacy" || true)
  if [ "$n" -eq 0 ]; then
    ok ".$legacy has no rule left in the stylesheet"
  else
    bad ".$legacy has no rule left in the stylesheet" "$n rule(s) remain"
  fi
  for src in "$JS" "$HTML"; do
    n=$(grep -c "$legacy" "$src" || true)
    [ "$n" -eq 0 ] && ok ".$legacy is gone from $(basename "$src")" \
      || bad ".$legacy is gone from $(basename "$src")" "$n reference(s) remain"
  done
done

echo
echo
echo "=== 3b. the icon-button collapse STAYS collapsed ==="
# Four classes for one widget (.icon-btn, .editor-icon-btn, .voice-draft-btn,
# .reminder-add-toggle), plus a DESCENDANT OVERRIDE that made .icon-btn render
# two different things depending on where it sat: a 30px transparent ghost in
# the header, a 32px bordered chip in the Drive toolbar.
# Mutation: reintroduce `.icon-btn { ... }` -> red.
for legacy in '.icon-btn' '.editor-icon-btn' '.voice-draft-btn' \
              '.drive-toolbar-actions .icon-btn'; do
  n=$(printf '%s' "$stripped" | grep -cF "$legacy" || true)
  if [ "$n" -eq 0 ]; then
    ok "$legacy has no rule left in the stylesheet"
  else
    bad "$legacy has no rule left in the stylesheet" "$n rule(s) remain"
  fi
  for src in "$JS" "$HTML"; do
    n=$(grep -cF "$legacy" "$src" || true)
    [ "$n" -eq 0 ] && ok "$legacy is gone from $(basename "$src")" \
      || bad "$legacy is gone from $(basename "$src")" "$n reference(s) remain"
  done
done

# Every icon button must carry BOTH .btn-icon and a size class, or it collapses
# to a zero-size flex box. This is what makes deleting the old rules safe.
report=$(python3 - "$HTML" <<'PY'
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
SIZES = {"btn-icon-28", "btn-icon-30", "btn-icon-32", "btn-icon-34", "btn-icon-lg"}
bad = []
for m in re.finditer(r"<button\b([^>]*)>", html):
    attrs = m.group(1)
    # Read the class VALUE, not the raw attribute text: the size class sits
    # inside the quotes, so a whitespace-delimited match on the attribute blob
    # fails on the closing quote and reports every button as unsized.
    cm = re.search(r'class="([^"]*)"', attrs)
    if not cm:
        continue
    classes = set(cm.group(1).split())
    if "btn-icon" not in classes:
        continue
    if not classes & SIZES:
        ident = re.search(r'id="([^"]*)"', attrs)
        bad.append((ident.group(1) if ident else "?") + " -> " + cm.group(1))
print(len(bad))
for b in bad:
    print("#   " + b)
PY
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "every .btn-icon also carries a size ($count unsized)"
else
  bad "every .btn-icon also carries a size" "$report"
fi

# Was `.btn-icon[hidden]`, with a comment explaining that display:inline-flex
# outranks a bare attribute selector. True, and beside the point: the global
# `[hidden] { display: none !important }` outranks specificity outright, so the
# per-class rule was always redundant. #voiceDraftPlay is hidden by the global
# one, and this asserts the thing that actually protects it.
if [ "$(rule_body "[hidden]")" = "display: none !important;" ]; then
  ok "a hidden .btn-icon is hidden by the global rule (#voiceDraftPlay relies on it)"
else
  bad "a hidden .btn-icon is hidden by the global rule" \
      "a hidden icon button (voiceDraftPlay) would stay visible - got: $(rule_body "[hidden]")"
fi

# cursor:pointer is NOT the UA default for <button>. All four replaced rules set
# it individually; without it a control stops reading as clickable.
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    if {s.strip() for s in m.group(1).split(",")} == {".btn-icon"}:
        sys.exit(0 if "cursor: pointer" in m.group(2) else 1)
sys.exit(1)
PY
then
  ok ".btn-icon sets cursor: pointer"
else
  bad ".btn-icon sets cursor: pointer" \
      "every replaced rule set it individually; without it the control is not clickable-looking"
fi

# Both variants must have a BASE rule, not just their state rules. Grepping for
# the name is not enough: `.btn-icon-outline:hover` and `.btn-icon-outline.active`
# both keep the name alive in the stylesheet, so deleting the base rule - which
# carries the border and the resting background - passed every other check here.
for v in btn-icon btn-icon-outline btn-icon-accent; do
  if python3 - "$CSS" "$v" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
want = "." + sys.argv[2]
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    if {s.strip() for s in m.group(1).split(",")} == {want}:
        sys.exit(0)
sys.exit(1)
PY
  then
    ok ".$v has a base rule, not only :hover/:active variants"
  else
    bad ".$v has a base rule, not only :hover/:active variants" \
        "only its state rules exist, so the border and resting background are gone"
  fi
done

# Every JS-constructed .btn-icon must carry the right size AND shape, or it
# renders with no size or as a circle when it should be a rounded square. The
# earlier check only scanned <button> tags in the HTML, and every button in this
# family is built by JS - so the check passed vacuously (verified by mutation).
# Mutation: drop btn-icon-square from any JS-built button -> red.
js_icons=$(python3 - "$JS" <<'PYX'
import re, sys
js = open(sys.argv[1], encoding="utf-8").read()
bad = []
for m in re.finditer(r'className\s*=\s*"([^"]*\bbtn-icon\b[^"]*)"', js):
    cls = set(m.group(1).split())
    if not any(c.startswith("btn-icon-") for c in cls):
        bad.append(m.group(1))
    if "btn-icon-square" in m.group(1) and "btn-icon-outline" not in cls:
        pass  # a square ghost is legitimate; shape is checked per class below
print(len(bad))
for b in bad:
    print("#   " + b)
PYX
)
count=${js_icons%%#*}
if [ "$count" -eq 0 ]; then
  ok "every JS-built .btn-icon carries a size"
else
  bad "every JS-built .btn-icon carries a size" "$js_icons"
fi

# The two controls that must be SQUARE, checked by name so the assertion is
# about the right elements and not merely "some square exists".
square_needed='drive-item-menu-btn code-copy-btn'
for c in $square_needed; do
  line=$(grep -o "className = \"[^\"]*$c\"" "$JS" || true)
  case "$line" in
    *btn-icon-square*) ok ".$c carries .btn-icon-square" ;;
    *) bad ".$c carries .btn-icon-square" \
            "it would render as a circle inside a dense grid - got: ${line:-not found}" ;;
  esac
done

# Both fading controls need opacity in their transition. The primitive only
# transitions background and colour, so without this they snap between opacities
# instead of fading - invisible in a screenshot, obvious in use.
for sel in .code-copy-btn .drive-item-menu-btn; do
  case "$(rule_body "$sel")" in
    *opacity*transition*|transition*opacity*)
      ok "$sel keeps opacity in its transition" ;;
    *)
      bad "$sel keeps opacity in its transition" \
          "it fades between two opacities and would snap instead - got: $(rule_body "$sel")" ;;
  esac
done

# The reminder dismiss is the only control here that goes destructive on hover.
if [ "$(rule_body ".reminder-dismiss:hover")" != "" ] \
   && rule_body ".reminder-dismiss:hover" | grep -q 'var(--destructive-bright)'; then
  ok ".reminder-dismiss still goes destructive on hover"
else
  bad ".reminder-dismiss still goes destructive on hover" \
      "it deletes, so its hover has to read as destructive"
fi

# .copied is the shared green confirmation on BOTH copy buttons.
if python3 - "$CSS" <<'PYX'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    if {s.strip() for s in m.group(1).split(",")} == {".btn-icon.copied"}:
        sys.exit(0 if "var(--success)" in m.group(2) else 1)
sys.exit(1)
PYX
then
  ok ".btn-icon.copied carries the shared success colour"
else
  bad ".btn-icon.copied carries the shared success colour" \
      "copy confirmation regresses to the resting colour on both copy buttons"
fi

# --- the text-button collapse stays collapsed ---
# Nine implementations of "a button with a word on it" were nine sets of
# geometry. Every one of these names is gone.
# Mutation: reintroduce `.elevate-submit { ... }` -> red.
stripped2=$(python3 -c "import re,sys;print(re.sub(r'/\*[\s\S]*?\*/','',open(sys.argv[1],encoding='utf-8').read()),end='')" "$CSS")
# NOT in this list, because these two are state hooks rather than styles and are
# still load-bearing: .history-tier-btn carries its `.active` selected state and
# the JS reads `.active` off it; .history-daypicker-btn carries `.open` and the
# rotated caret. Their geometry comes from .btn, but the names are queried.
for legacy in '.gate-card button' '.qac-btn' '.qac-btn-primary' '.qac-btn-destructive' \
              '.editor-pill-btn' '.elevate-submit' '.qa-input-go' '.qa-drawer-clear' \
              '#reminderAddBtn'; do
  n=$(printf '%s' "$stripped2" | grep -cF "$legacy" || true)
  if [ "$n" -eq 0 ]; then
    ok "$legacy has no rule left in the stylesheet"
  else
    bad "$legacy has no rule left in the stylesheet" "$n rule(s) remain"
  fi
done

# Every migrated control must actually carry .btn, or it silently loses all
# geometry when its old rule is deleted. This is what makes those deletions safe.
report=$(python3 - "$HTML" "$JS" <<'PYX'
import re, sys
html, js = open(sys.argv[1], encoding="utf-8").read(), open(sys.argv[2], encoding="utf-8").read()
bad = []
# Static markup: every one of these used to be a hand-rolled button.
for i in ["gateSubmit", "reminderAddBtn", "historyDayBtn", "qaDrawerClear",
          "qaInputGo", "qaInputCancel", "driveNewFolderGo", "driveNewFolderCancel",
          "driveClipboardCancel", "elevateSubmit", "applyCrop", "editorSave"]:
    m = re.search(r'<button[^>]*id="' + i + r'"[^>]*>', html)
    if not m:
        bad.append(i + " (not found)"); continue
    cm = re.search(r'class="([^"]*)"', m.group(0))
    if not cm or "btn" not in cm.group(1).split():
        bad.append(i + " -> " + (cm.group(1) if cm else "no class"))
# The question card builds its own six in JS.
for m in re.finditer(r'className = "([^"]*\bbtn\b[^"]*)"', js):
    pass
print(len(bad))
for b in bad:
    print("#   " + b)
PYX
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "all 12 static text buttons carry .btn ($count unconverted)"
else
  bad "all 12 static text buttons carry .btn" "$report"
fi

# The question card's six are built in JS, so the HTML scan cannot see them.
n=$(grep -c 'className = "btn btn-sm' "$JS" || true)
if [ "$n" -eq 6 ]; then
  ok "all 6 JS-built question-card buttons carry .btn"
else
  bad "all 6 JS-built question-card buttons carry .btn" \
      "found $n of 6 - a question card button lost its geometry"
fi

# A .btn must be paired with a size. .btn alone is a shape with no dimensions,
# which is the one mistake the class system can make silently.
report=$(python3 - "$HTML" "$JS" <<'PYX'
import re, sys
SIZES = {"btn-xs", "btn-sm", "btn-md", "btn-pill"}
bad = []
# Match .btn as a whole token. \b matches at a hyphen, so a loose pattern also
# catches "btn-icon" - which is a different component entirely and made every
# icon button look unsized.
TOKEN = r"(?<![\w-])btn(?![\w-])"
CLASS_ATTR = r'<button[^>]*class="([^"]*)"'
JS_ASSIGN = r'className = "([^"]*)"'
for path in (sys.argv[1], sys.argv[2]):
    src = open(path, encoding="utf-8").read()
    for pat in (CLASS_ATTR, JS_ASSIGN):
        for m in re.finditer(pat, src):
            classes = set(m.group(1).split())
            # Only controls that really are text buttons: .btn present as a
            # whole token, and not one of the .btn-icon* family.
            if "btn" in classes and "btn-icon" not in classes \
               and not (classes & SIZES):
                bad.append(m.group(1))
print(len(bad))
for b in sorted(set(bad)):
    print("#   " + b)
PYX
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "every .btn is paired with a size ($count unsized)"
else
  bad "every .btn is paired with a size" "$report"
fi

# A variant dropped from a button is a silent regression: the button still
# renders, just without its fill or colour, and nothing else fails. Assert the
# two that matter - the question card's solid affirmative, and the destructive
# variants - are actually applied where they are meant to be.
# Mutation: strip btn-solid from the JS-built question buttons -> red.
n=$(grep -c 'className = "btn btn-sm btn-solid' "$JS" || true)
if [ "$n" -eq 2 ]; then
  ok "both JS-built solid-affirmative buttons carry .btn-solid (Next, Allow once)"
else
  bad "both JS-built solid-affirmative buttons carry .btn-solid" \
      "found $n of 2 - the question card's affirmative loses its accent fill"
fi
if grep -q 'id="gateSubmit" class="btn btn-md btn-primary btn-block"' "$HTML"; then
  ok "the gate CTA is a full-bleed .btn.btn-primary"
else
  bad "the gate CTA is a full-bleed .btn.btn-primary" "it reverted to a plain styled button"
fi
# The three heights must come from the tokens, so all three change together if
# the scale is retuned.
for t in xs sm md; do
  if [ "$(rule_body ".btn-$t")" = "height: var(--btn-height-$t); padding: 0 $( [ $t = xs ] && echo 8 || { [ $t = sm ] && echo 12 || echo 14; } )px; font-size: $( [ $t = md ] && echo '0.85rem' || echo "var(--text-$t)" );" ]; then
    ok ".btn-$t reads --btn-height-$t"
  else
    bad ".btn-$t reads --btn-height-$t" "got: $(rule_body ".btn-$t")"
  fi
done

# The two surviving hooks: their geometry is .btn's, but the names still carry
# state and are still read. Dropping either would silently break the control.
for h in ".history-tier-btn.active" ".history-daypicker-btn.open"; do
  if [ -n "$(rule_body "$h")" ]; then
    ok "$h still exists (it is a state hook, not just styling)"
  else
    bad "$h still exists" "the selected/open state has no rule"
  fi
done
n=$(grep -c 'querySelectorAll(".history-tier-btn' "$JS" || true)
m=$(grep -c '\.classList.toggle("active"' "$JS" || true)
if [ "$n" -ge 1 ] || [ "$m" -ge 1 ]; then
  ok "the tier filter's .active state is still toggled by the JS"
else
  bad "the tier filter's .active state is still toggled by the JS" \
      "the segment would never highlight"
fi

# --- the badge collapse stays collapsed ---
# Three hand-written badges became .badge plus a variant. All three legacy names
# must be gone, and each element must carry a variant - a bare .badge is a
# layout with no fill, which renders as invisible text.
# Mutation: reintroduce `.tier-badge { ... }` -> red.
stripped3=$(python3 -c "import re,sys;print(re.sub(r'/\*[\s\S]*?\*/','',open(sys.argv[1],encoding='utf-8').read()),end='')" "$CSS")
for legacy in '.tier-badge' '.tier-timer' '.menu-item-badge' \
              '.menu-item-badge.locked' '.menu-item-badge.unread'; do
  n=$(printf '%s' "$stripped3" | grep -cF "$legacy" || true)
  if [ "$n" -eq 0 ]; then
    ok "$legacy has no rule left in the stylesheet"
  else
    bad "$legacy has no rule left in the stylesheet" "$n rule(s) remain"
  fi
done
# Counted per variant rather than with one alternation: `grep -E` with
# `badge (a|b|c)` counted 0 against correct markup, because the class attribute
# here is followed by more classes and by the tag's own ">" - a single-line
# anchored alternation is the wrong tool for "does this element carry any of
# these three". Summed instead.
for v in badge-outline badge-solid badge-label; do
  n=$(grep -c "class=\"badge $v\"" "$HTML" || true)
  case "$v" in
    badge-outline) want=1 ;;
    badge-solid)   want=1 ;;
    badge-label)   want=2 ;;
  esac
  if [ "$n" -eq "$want" ]; then
    ok "$n element(s) carry .$v"
  else
    bad "the .$v badges are all converted" "found $n, want $want"
  fi
done
# ...and no element carries a bare .badge with no variant, which would render as
# loose text with no fill or pill.
if grep -qE 'class="badge"' "$HTML"; then
  bad "no badge is left without a variant" 'a bare class="badge" renders as loose text'
else
  ok "no badge is left without a variant"
fi
# .locked and .unread are JS-toggled state, and the JS reads the badge elements
# by id, so the variant rename must not have orphaned the state classes.
for st in locked unread; do
  if [ -n "$(rule_body ".badge-label.$st")" ]; then
    ok ".badge-label.$st still exists (JS toggles it)"
  else
    bad ".badge-label.$st still exists" "the menu badge state has no styling"
  fi
done
# The countdown's [hidden] rule had to be re-declared against the new class: an
# attribute selector loses to a class selector on specificity, so without
# !important the pill would show while Full Mode is off.
# Was `.badge-outline[hidden]`, whose comment argued that "an attribute selector
# loses to a class selector on specificity". True and irrelevant: the global
# !important rule outranks specificity regardless, so it was always redundant.
if [ "$(rule_body "[hidden]")" = "display: none !important;" ]; then
  ok "the countdown is hidden by the global [hidden] rule, as every panel is"
else
  bad "the countdown is hidden by the global [hidden] rule" \
      "the countdown would be visible before Full Mode is elevated - got: $(rule_body "[hidden]")"
fi
# The countdown uses tabular figures so the numbers do not jitter as they tick.
if rule_body ".badge-outline" | grep -q 'tabular-nums'; then
  ok ".badge-outline uses tabular figures (no jitter while counting down)"
else
  bad ".badge-outline uses tabular figures" "the countdown visibly jitters as digits change"
fi

# === Chat-only status indicator ===
# T1/T2, the session countdown and the status dot describe the live
# conversation, so they hide when an overlay covers it. The same [hidden]
# trap as the countdown, and worse: `.status-indicator` sets `display: flex`,
# and an author display beats the user-agent [hidden] rule outright whatever
# the specificity - so the attribute alone does nothing.
# Mutation: delete the [hidden] rule -> red.
# Was `.status-indicator[hidden]`, added earlier in this migration with the
# comment "an author display beats the user-agent [hidden] rule outright". True,
# and beside the point: the global rule is an AUTHOR rule too, and being
# !important it wins. The badges hide because of the global rule.
if [ "$(rule_body "[hidden]")" = "display: none !important;" ] && \
   [ -z "$(rule_body ".status-indicator[hidden]")" ]; then
  ok "the status indicator relies on the global [hidden] rule, not a private copy"
else
  bad "the status indicator relies on the global [hidden] rule" \
      "a private copy has crept back (global: $(rule_body "[hidden]"))"
fi
# The element the JS hides must be addressable. Mutation: drop the id -> red.
if grep -q 'class="status-indicator" id="statusIndicator"' "$HTML"; then
  ok "#statusIndicator is on the status-indicator div (the JS hides by id)"
else
  bad "#statusIndicator is on the status-indicator div" \
      "the JS toggle has no element to hide - the badges show over every overlay"
fi
# The toggle has to sit ABOVE updateComposerMode's `if (activeOverlay !== null)`
# early return. Below it, the overlay branch returns first and the badges never
# hide on exactly the views they should. Asserted positionally, because that
# ordering is the whole correctness of this change and nothing else covers it.
# Mutation: move the assignment below the return -> red.
toggle_at="$(grep -n 'statusIndicator.hidden = activeOverlay !== null' "$JS" | head -1 | cut -d: -f1)"
guard_at="$(grep -n 'if (activeOverlay !== null)' "$JS" | head -1 | cut -d: -f1)"
if [ -n "$toggle_at" ] && [ -n "$guard_at" ] && [ "$toggle_at" -lt "$guard_at" ]; then
  ok "the status-indicator toggle precedes the activeOverlay early return"
elif [ -z "$toggle_at" ]; then
  bad "the status-indicator toggle precedes the activeOverlay early return" \
      "no line sets 'statusIndicator.hidden = activeOverlay !== null' - the toggle was removed or its condition changed"
else
  bad "the status-indicator toggle precedes the activeOverlay early return" \
      "toggle at line $toggle_at is below the return at $guard_at, so the overlay branch skips it"
fi
# Mutation: change the condition to `===` -> red.
if grep -q 'statusIndicator.hidden = activeOverlay !== null;' "$JS"; then
  ok "the toggle keys off 'an overlay is open', not 'an overlay is named'"
else
  bad "the toggle keys off 'an overlay is open'" \
      "a future overlay value would leave the badges on screen"
fi

# The gate's CTA needs room to breathe. Its margin lived on `.gate-card button`
# and was lost in the .btn migration, leaving the password field's underline
# flush against the button - invisible in a diff, obvious on screen.
# Mutation: remove the margin -> red.
if [ "$(rule_body ".gate-card .btn")" = "margin-top: 22px;" ]; then
  ok ".gate-card .btn keeps its margin below the password field"
else
  bad ".gate-card .btn keeps its margin below the password field" \
      "the field's underline sits flush against the Unlock button - got: $(rule_body ".gate-card .btn")"
fi

# The outlined variant is a rounded SQUARE. .btn-icon rounds everything to a
# circle, and the Drive toolbar's five buttons were --radius-lg before the
# change - so without this the shape silently changed on five controls.
# Mutation: drop border-radius from .btn-icon-outline -> red.
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    if {s.strip() for s in m.group(1).split(",")} == {".btn-icon-outline"}:
        sys.exit(0 if "border-radius: var(--radius-lg)" in m.group(2) else 1)
sys.exit(1)
PY
then
  ok ".btn-icon-outline is a rounded square, not a circle"
else
  bad ".btn-icon-outline is a rounded square, not a circle" \
      "it inherits border-radius:50% from .btn-icon, changing five Drive toolbar buttons"
fi

# The outlined variant belongs to the Drive toolbar and nowhere else. The
# breadcrumb edit button sits OUTSIDE .drive-toolbar-actions and was always a
# plain ghost circle; marking it outlined gives it a border and a fill it never
# had.
n=$(python3 - "$HTML" <<'PY'
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'<div class="drive-toolbar-actions">(.*?)\n        </div>', html, re.S)
inside = m.group(1).count("btn-icon-outline") if m else 0
outside = html[:m.start()].count("btn-icon-outline") + html[m.end():].count("btn-icon-outline")
print(outside + abs(inside - 5))
PY
)
if [ "$n" -eq 0 ]; then
  ok "the 5 outlined buttons are exactly the Drive toolbar's"
else
  bad "the 5 outlined buttons are exactly the Drive toolbar's" \
      "$n mismatch(es) - an outlined button outside the toolbar gained a border and a fill"
fi

# The mic button's position:relative is load-bearing: .mic-stop-square and the
# two .ring-N pulse rings are absolutely positioned against it. Dropping it
# re-roots them to the nearest positioned ancestor - the editor overlay - and
# the rings land in the wrong place mid-recording.
if [ "$(rule_body ".mic-btn")" = "position: relative;" ]; then
  ok ".mic-btn keeps position: relative (the pulse rings are positioned against it)"
else
  bad ".mic-btn keeps position: relative" \
      "the recording rings and stop square re-root to the editor overlay - got: $(rule_body ".mic-btn")"
fi

# The send glyph is sized explicitly; without it the arrow renders at whatever
# intrinsic size the SVG happens to carry.
svg=$(rule_body ".send-btn svg")
case "$svg" in
  *"width: 19px"*"height: 19px"*) ok ".send-btn svg is still explicitly sized (19px)" ;;
  *) bad ".send-btn svg is still explicitly sized" \
         "the send arrow falls back to its intrinsic SVG size - got: $svg" ;;
esac

# The stop affordance is a HOLLOW square. It was fill="currentColor", a solid
# block, and at the same optical weight as the replay/copy/retry glyphs beside
# it "stop" read as the loudest thing in the row - when it is a quiet, temporary
# affordance. Asserted structurally: a stroked rect, no fill.
# Mutation: put fill="currentColor" back -> red.
# Parsed from the string rather than grepped, because the stroke lives on the
# <svg> element rather than on the <rect> - a grep for `<rect ... stroke=` does
# not match, and the assertion failed on a correct icon until this was fixed.
if python3 - "$JS" <<'PYX'
import re, sys
js = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"STOP_ICON_SVG = '([^']+)'", js)
if not m:
    print("#   STOP_ICON_SVG not found"); sys.exit(1)
svg = m.group(1)
hollow = ('fill="none"' in svg
          and 'fill="currentColor"' not in svg
          and re.search(r'stroke="[^"]+"', svg) is not None
          and re.search(r'<rect [^>]*?/>', svg) is not None)
print("OK" if hollow else "not hollow: " + svg[:110])
sys.exit(0 if hollow else 1)
PYX
then
  ok "the stop icon is a hollow (stroked, unfilled) square"
else
  bad "the stop icon is a hollow (stroked, unfilled) square" \
      "a filled square reads as the loudest control in the message action row"
fi
# ...and centred: the rect spans 5.5..16.5 on both axes, so its centre is
# (11,11), the viewBox centre. An off-centre square is visibly lopsided.
if python3 - "$JS" <<'PYX'
import re, sys
js = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"STOP_ICON_SVG = '([^']+)'", js)
if not m:
    print("#   STOP_ICON_SVG not found"); sys.exit(1)
svg = m.group(1)
vb = [float(v) for v in re.search(r'viewBox="([\d.\s-]+)"', svg).group(1).split()]
cx, cy = vb[0] + vb[2] / 2, vb[1] + vb[3] / 2
r = re.search(r'<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)"', svg)
if not r:
    print("#   no rect in the stop icon"); sys.exit(1)
x, y, w, h = (float(r.group(i)) for i in range(1, 5))
off = (round((x + w / 2) - cx, 3), round((y + h / 2) - cy, 3))
print("OK" if off == (0.0, 0.0) else f"ink centre off by {off}")
sys.exit(0 if off == (0.0, 0.0) else 1)
PYX
then
  ok "the stop square is centred in its viewBox"
else
  bad "the stop square is centred in its viewBox" "an off-centre square is visibly lopsided"
fi

# The send arrow's INK is centred in its viewBox, not just its <svg> box. It
# was drawn at x 5..19 and y 5..19 - centred on (12,12) inside a 0 0 22 22
# viewBox whose centre is (11,11) - so it sat ~0.9px right and down. Layout was
# never the problem; flex centring a 19px box in a 42px button cannot fix ink
# that is off-centre inside its own viewBox.
# Mutation: shift the arrow back to x/y centred on 12 -> red.
if python3 - "$HTML" <<'PYX'
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'id="sendText".*?</svg>', html, re.S)
if not m:
    print("#   send button not found"); sys.exit(1)
svg = m.group(0)
vb = [float(v) for v in re.search(r'viewBox="([\d.\s-]+)"', svg).group(1).split()]
cx, cy = (vb[0] + vb[2] / 2, vb[1] + vb[3] / 2)
pts = []
for mm in re.finditer(r'x1="([\d.]+)" y1="([\d.]+)" x2="([\d.]+)" y2="([\d.]+)"', svg):
    pts += [(float(mm.group(1)), float(mm.group(2))), (float(mm.group(3)), float(mm.group(4)))]
for mm in re.finditer(r'points="([\d.\s,-]+)"', svg):
    v = [float(x) for x in re.findall(r'-?[\d.]+', mm.group(1))]
    pts += list(zip(v[0::2], v[1::2]))
xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
ink = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2)
off = (round(ink[0] - cx, 3), round(ink[1] - cy, 3))
if off == (0.0, 0.0):
    print("OK")
    sys.exit(0)
# The exit code is the assertion. An earlier version printed this message and
# fell off the end of the script, exiting 0 either way - so the check passed
# with the arrow deliberately shifted back off-centre.
print(f"ink centre {ink}, viewBox centre {cx},{cy}, off by {off}")
sys.exit(1)
PYX
then
  ok "the send arrow's ink is centred in its viewBox"
else
  bad "the send arrow's ink is centred in its viewBox" \
      "the glyph is drawn off-centre inside its own viewBox, which no amount of flex centring can fix"
fi

echo
echo "=== 4. one scrollbar recipe, not three ==="
# .history-day-menu and .qa-drawer-body each had their own block, and a third
# served six elements by listing all six selectors. One class now does it.
#
# .drive-breadcrumbs is the documented EXCEPTION: it scrolls sideways but hides
# the scrollbar, so it must NOT carry .scroll-area. Asserting its absence of the
# class is what stops someone "fixing" it into consistency.
# Mutation: add a second `.something::-webkit-scrollbar-thumb { ... }` -> red.
count=$(grep -cE '^\s*\.[A-Za-z][A-Za-z0-9_-]*::?-webkit-scrollbar(-thumb|-track)?\s*\{' "$CSS" || true)
if [ "$count" -eq 4 ]; then
  ok "exactly 4 scrollbar rules, all on .scroll-area ($count)"
else
  bad "exactly 4 scrollbar rules, all on .scroll-area" \
      "found $count - a hand-written scrollbar recipe has come back"
fi
n=$(grep -cE '^\s*\.[A-Za-z][A-Za-z0-9_-]*::?-webkit-scrollbar' "$CSS" || true)
if [ "$n" -eq 5 ]; then
  ok "the only non-.scroll-area scrollbar rule is the documented exception ($n)"
else
  bad "the only non-.scroll-area scrollbar rule is the documented exception" \
      "found $n scrollbar rules outside .scroll-area"
fi
# The four counts above only see the WebKit/Blink pseudo-elements, which is how
# THREE hand-written copies of the Firefox pair survived a migration that had
# already put .scroll-area on every one of those elements: .qa-drawer-body,
# .history-day-menu and a six-selector list. The primitive is now whole, so the
# Firefox half must be declared exactly once.
# Counts the RECIPE (`: thin`), not every scrollbar-width declaration -
# .drive-breadcrumbs legitimately declares `scrollbar-width: none`.
py_scrollbar_width_sites() { python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
n = 0
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    if re.search(r"(^|;)\s*scrollbar-width\s*:\s*thin\b", m.group(2)):
        n += 1
print(n)
PY2
}
_sw="$(py_scrollbar_width_sites)"
if [ "$_sw" -eq 1 ]; then
  ok "scrollbar-width is declared exactly once, on .scroll-area"
else
  bad "scrollbar-width is declared exactly once, on .scroll-area" \
      "found $_sw - a hand-written Firefox scrollbar copy has come back"
fi
if grep -q 'class="drive-breadcrumbs[^"]*scroll-area' "$HTML" \
   || grep -q 'drive-breadcrumbs[^"]*scroll-area' "$JS"; then
  bad "drive-breadcrumbs does not carry .scroll-area" \
      "it hides its scrollbar on purpose; adding the class puts the thumb back"
else
  ok "drive-breadcrumbs does not carry .scroll-area (it hides the bar on purpose)"
fi

echo
echo "=== 5. one spin keyframe, not three ==="
# attach-spin, qa-spin and perla-spin all rotated 360deg. Two of them are gone.
# Mutation: add `@keyframes qa-spin { to { transform: rotate(360deg); } }` -> red.
spins=$(grep -oE '@keyframes [a-z0-9-]*spin' "$CSS" | sort -u)
n=$(printf '%s\n' "$spins" | grep -c '@keyframes' || true)
if [ "$n" -eq 1 ] && printf '%s' "$spins" | grep -q '@keyframes perla-spin'; then
  ok "exactly one spin keyframe, and it is perla-spin"
else
  bad "exactly one spin keyframe, and it is perla-spin" "found: $(printf '%s' "$spins" | tr '\n' ' ')"
fi
users=$(grep -oE 'animation: [a-z0-9-]*spin' "$CSS" | sort -u | wc -l)
if [ "$users" -ge 1 ] && ! printf '%s' "$users" | grep -qE 'attach-spin|qa-spin'; then
  ok "no animation still names attach-spin or qa-spin ($users distinct timing(s))"
else
  bad "no animation still names attach-spin or qa-spin" "leftover references remain"
fi

echo
echo "=== 6. the empty-state appearance is stated once ==="
# Seven states shared `color: var(--accent-foreground); font-style: italic`, so
# neither declaration may appear in a per-surface empty-state rule any more.
# Counted per RULE, not per file: --accent-foreground is a palette token with 35
# legitimate uses elsewhere, and a whole-file count would say nothing about
# whether the empty states are still styling themselves.
# Mutation: put `color: var(--accent-foreground)` back into .drive-empty -> red.
EMPTY_STATES="drive-empty reminder-empty qa-drawer-empty history-day-menu-empty
file-viewer-empty file-viewer-modal-empty file-viewer-modal-loading
entry-image-loading"
report=$(python3 - "$CSS" $EMPTY_STATES <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
targets = {t.lstrip(".") for t in sys.argv[2:]}
SHARED = ("color: var(--accent-foreground)", "font-style: italic")
hits = []
for m in re.finditer(r"(?m)^([ \t]*)((?:\.[\w-]+)(?:\s*,\s*\.[\w-]+)*)\s*\{([^}]*)\}", css):
    names = {s.strip().lstrip(".") for s in m.group(2).split(",")}
    if names & targets:
        for decl in SHARED:
            if decl in m.group(3):
                hits.append(" ".join(sorted(names & targets)) + " -> " + decl)
print(len(hits))
for h in hits:
    print("#   " + h)
PY
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "no per-surface empty state restates the shared appearance ($count)"
else
  bad "no per-surface empty state restates the shared appearance" "$report"
fi

# And the shared pair must actually be on .empty, or the states have no styling.
empty_body=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
for m in re.finditer(r"(?m)^([ \t]*)((?:\.[\w-]+)(?:\s*,\s*\.[\w-]+)*)\s*\{([^}]*)\}", css):
    if {s.strip().lstrip(".") for s in m.group(2).split(",")} == {"empty"}:
        print(m.group(3))
        break
PY
)
case "$empty_body" in
  *"var(--accent-foreground)"*"font-style: italic"*)
    ok ".empty carries the shared appearance it replaced" ;;
  *)
    bad ".empty carries the shared appearance it replaced" \
        "got: $(printf '%s' "$empty_body" | tr -s ' ')" ;;
esac

echo "=== 7. no undeclared property override ==="
# Found the hard way. The header's connection widget and the panels' inline
# status line were BOTH `.status`. Equal specificity, so whichever came later in
# the file silently won and the header's `display: flex` ended up applying to a
# row of status text. Renaming one fixed it; nothing caught it, because every
# individual assertion was still true.
#
# A later rule overriding an earlier one is NORMAL css - a base rule followed
# by a modifier, or a gradient layered over a fill. So this does not forbid
# overrides; it requires each one to be DECLARED below, with a reason. A new
# undeclared override fails, and a declared one that disappears also fails, so
# the list cannot quietly rot.
#
# Mutation: give .input a second rule that also sets `padding` -> red.
#
# selector | property | why the override is intentional
DECLARED_OVERRIDES="
body|background|the radial accent gradient is layered over the plain fill on purpose
"
collisions=$(python3 - "$CSS" "$DECLARED_OVERRIDES" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
declared = set()
for line in sys.argv[2].strip().splitlines():
    if line.strip():
        sel, prop, _why = line.split("|", 2)
        declared.add((sel.strip(), prop.strip()))

def props(body):
    out = {}
    for decl in body.split(";"):
        if ":" not in decl:
            continue
        k, _, v = decl.partition(":")
        if k.strip() and v.strip():
            out[k.strip()] = v.strip()
    return out

seen, found, i = {}, set(), 0
while i < len(css):
    m = re.compile(r"([^{}]+)\{|\}").search(css, i)
    if not m:
        break
    if m.group(0) == "}":
        i = m.end()
        continue
    sel = " ".join(m.group(1).split())
    if sel.startswith("@"):
        # Skip the whole at-rule: @media is the responsive pattern and
        # @keyframes contributes bare `from`/`to` steps that are not selectors.
        depth, j = 0, m.end() - 1
        while j < len(css):
            if css[j] == "{":
                depth += 1
            elif css[j] == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        i = j + 1
        continue
    close = css.index("}", m.end())
    body = css[m.end():close]
    # Key on each selector in the list INDIVIDUALLY: `.prose-table th, .prose-table td`
    # and a later bare `.prose-table td` are the same selector for one member, and
    # a conflict between them is just as silent.
    for one in (s.strip() for s in sel.split(",")):
        for k, v in props(body).items():
            if k in seen.get(one, {}) and seen[one][k] != v:
                found.add((one, k))
            seen.setdefault(one, {})[k] = v
    i = close + 1

undeclared = sorted(found - declared)
stale = sorted(declared - found)
print(len(undeclared) + len(stale))
for s, p in undeclared:
    print("#   UNDECLARED override: " + s + " { " + p + " }")
for s, p in stale:
    print("#   STALE declaration (no override there any more): " + s + " { " + p + " }")
PY
)
count=${collisions%%#*}
if [ "$count" -eq 0 ]; then
  ok "every property override is declared ($count undeclared or stale)"
else
  bad "every property override is declared (and every declaration still used)" "$collisions"
fi
echo
echo "=== 8. reported layout bugs stay fixed ==="
# Five defects found by looking at the running app, not by reading the code.
# Each was invisible to every other assertion in this file.
# Mutation: revert any one -> red.

# (1) The Drive image viewer scrolled on a tall image: the rule capped
# max-width but not max-height, so only the horizontal axis was constrained.
img=$(rule_body ".file-viewer-modal-body img")
if printf '%s' "$img" | grep -q 'max-height: 100%' \
   && printf '%s' "$img" | grep -q 'max-width: 100%'; then
  ok "the Drive image viewer caps BOTH axes, so a tall image cannot scroll"
else
  bad "the Drive image viewer caps BOTH axes" \
      "max-width alone lets a portrait image overflow into a scrollbar - got: $img"
fi

# (2) Save / Apply-crop read as a very wide border because a bordered pill
# (.editor-float) wrapped a pill-shaped button. Only the SINGLE-control floats
# are exempt; #penOptionsRow holds the slider AND the swatches, so it keeps its ring.
saves=$(grep -c '<div class="editor-float editor-save-float bare">' "$HTML" || true)
crops=$(grep -c '<div class="editor-float editor-context-float bare"' "$HTML" || true)
pens=$(grep -c '<div class="editor-float editor-context-float" id="penOptionsRow"' "$HTML" || true)
if [ "$saves" -eq 2 ] && [ "$crops" -eq 1 ] && [ "$pens" -eq 1 ]; then
  ok "both .editor-save-floats and the crop float are bare; #penOptionsRow is not"
else
  bad "bare single-control floats" \
      "save=$saves (want 2) crop=$crops (want 1) penOptionsRow-without-bare=$pens (want 1)"
fi

# (3) The brush-size row was a fixed 90px holding 70px + 6px gap + 26px label
# = 102px, so the "6px" readout rendered outside the floating toolbar.
size=$(rule_body ".img-editor-size")
case "$size" in
  *width:*px*) bad ".img-editor-size is not a fixed width narrower than its contents" \
                  "got: $size - a fixed px width clips the px readout again" ;;
  *) ok ".img-editor-size is not a fixed width narrower than its contents" ;;
esac

# (4) Attachment edit/remove only on hover - but never on a touch device, which
# has no hover and would leave the attachments unremovable.
if rule_body ".attach-thumb-remove" ".attach-thumb-edit" | grep -q 'opacity: 0'; then
  ok "attachment edit/remove start hidden"
else
  bad "attachment edit/remove start hidden" "they are always visible again"
fi
# The reveal must cover hover AND focus-within, on BOTH buttons. Grepping for
# "focus-within .attach-thumb-edit" passed even with the sibling line renamed,
# because a grep sees the rule's other lines.
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
need = {".attach-thumb:hover .attach-thumb-remove",
        ".attach-thumb:hover .attach-thumb-edit",
        ".attach-thumb:focus-within .attach-thumb-remove",
        ".attach-thumb:focus-within .attach-thumb-edit"}
for m in re.finditer(r"([^{}]+)\{([^}]*opacity:\s*1[^}]*)\}", css):
    got = {s.strip() for s in m.group(1).split(",")}
    if need <= got:
        sys.exit(0)
sys.exit(1)
PY
then
  ok "the reveal covers hover and focus-within on both buttons"
else
  bad "the reveal covers hover and focus-within on both buttons" \
      "one selector is missing, so a control is stranded for keyboard or for mouse"
fi

# The (hover: none) branch must be the one that reveals THESE buttons. There
# are three such media blocks in this stylesheet, so grepping for the feature
# query alone is satisfied by an unrelated one.
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
for m in re.finditer(r"@media \(hover: none\)\s*\{", css):
    # walk to the matching close brace
    d, j = 1, m.end()
    while d and j < len(css):
        d += (css[j] == "{") - (css[j] == "}")
        j += 1
    block = css[m.end():j]
    if ".attach-thumb-remove" in block and "opacity: 1" in block:
        sys.exit(0)
sys.exit(1)
PY
then
  ok "the (hover: none) branch is the one that keeps them visible on touch"
else
  bad "the (hover: none) branch keeps them visible on touch" \
      "on a phone they would be permanently invisible and unremovable"
fi

# (5) The voice draft drew its own border inside footer.composer, which already
# has one - two concentric outlines. And with #textInput and .composer-row both
# hidden, the composer shrank unless the draft reserves their height.
draft=$(rule_body ".voice-draft")
case "$draft" in
  *border:*none*) ok ".voice-draft draws no border of its own" ;;
  *border:*) bad ".voice-draft draws no border of its own" \
                "its border inside the composer's border is the double outline - got: $draft" ;;
  *) ok ".voice-draft draws no border of its own (the composer supplies one)" ;;
esac
case "$draft" in
  *"min-height: calc(40px + var(--control-lg))"*)
    ok ".voice-draft reserves the hidden rows' height via --control-lg" ;;
  *) bad ".voice-draft reserves the hidden rows' height" \
       "the composer jumps in height when drafting starts - got: $draft" ;;
esac
# ...and the token is load-bearing. The three composer controls now carry the
# .btn-icon-lg SIZE HOOK rather than sizing themselves, so the coupling to
# --control-lg runs through that one rule: both halves are checked, because
# either alone would let them drift apart silently.
if [ "$(rule_body ".btn-icon-lg")" = "width: var(--control-lg); height: var(--control-lg);" ]; then
  ok ".btn-icon-lg sizes itself from --control-lg"
else
  bad ".btn-icon-lg sizes itself from --control-lg" \
      "got: $(rule_body ".btn-icon-lg") - resizing it would desync the draft's min-height"
fi
n=$(grep -cE 'id="(sendText|micBtn|attachBtn)" class="btn-icon btn-icon-lg' "$HTML" || true)
if [ "$n" -eq 3 ]; then
  ok "all three composer controls carry .btn-icon-lg"
else
  bad "all three composer controls carry .btn-icon-lg" \
      "only $n of 3 do - one of them would fall back to no size at all"
fi


echo "=== 9. the .md -> .prose rename is complete ==="
# The markdown block was the last surface still on the old namespace. A
# half-done rename is the specific failure here: the JS emits one name and the
# stylesheet matches the other, and every bubble renders as unstyled body text
# with no error anywhere.
#
# Counted over SELECTORS, not occurrences, so a rule that names .prose five
# times counts once - otherwise the threshold below is arbitrary.
py_prose_selectors() { python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
n = 0
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    for sel in m.group(1).split(","):
        if re.search(r"(^|[\s])(\.prose[a-z-]*)(?![\w-])", sel.strip()):
            n += 1
print(n)
PY2
}
prose_n="$(py_prose_selectors)"
if [ "$prose_n" -ge 25 ]; then
  ok "the prose namespace has $prose_n selectors"
else
  bad "the prose namespace has enough selectors" \
      "only $prose_n - the rename looks half-applied and bubbles would render unstyled"
fi
# Not a single .md selector may survive. Extension checks (.md file uploads)
# are not selectors, so this is exact.
py_md_selectors() { python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
n = 0
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    for sel in m.group(1).split(","):
        if re.search(r"(^|[\s])\.md(?![\w-])", sel.strip()):
            n += 1
print(n)
PY2
}
if [ "$(py_md_selectors)" -eq 0 ]; then
  ok "no .md selector survives in the stylesheet"
else
  bad "no .md selector survives in the stylesheet" \
      "$(py_md_selectors) still match - the JS emits .prose, so these are dead rules"
fi
# The renderer and the stylesheet must agree, or tables lose their wrapper and
# alignment silently stops working. Asserted on BOTH ends of the contract.
if grep -q 'class="prose-table-wrap"' "$JS" && [ -n "$(rule_body ".prose-table-wrap")" ]; then
  ok "renderer emits .prose-table-wrap and the stylesheet styles it"
else
  bad "renderer emits .prose-table-wrap and the stylesheet styles it" \
      "one side was renamed without the other"
fi
if grep -q 'class="prose-table"' "$JS" && [ -n "$(rule_body ".prose-table")" ]; then
  ok "renderer emits .prose-table and the stylesheet styles it"
else
  bad "renderer emits .prose-table and the stylesheet styles it" \
      "one side was renamed without the other"
fi
# The alignment class is built by concatenation ('prose-align-' + align), so
# the prefix alone proves nothing - a sibling rule satisfies it. Assert each
# concrete value the renderer can actually produce.
for align in center right; do
  if grep -q "prose-align-'" "$JS" && [ -n "$(rule_body ".prose-align-$align")" ]; then
    ok "renderer can emit .prose-align-$align and the stylesheet styles it"
  else
    bad "renderer can emit .prose-align-$align and the stylesheet styles it" \
        "the class would be emitted with no rule to match it"
  fi
done
# The two entry constructors set the container by className, and both places
# that later read it back use a querySelector. A rename that missed either
# would leave the content set but never displayed (or vice versa).
n_set="$(grep -c 'class="prose"' "$JS" || true)"
n_q="$(grep -c 'querySelector(".prose")' "$JS" || true)"
n_new="$(grep -c 'mdEl.className = "prose"' "$JS" || true)"
if [ "$n_set" -eq 2 ] && [ "$n_q" -eq 2 ] && [ "$n_new" -eq 1 ]; then
  ok "all three JS sites that name the prose container agree (2 templates, 2 queries, 1 createElement)"
else
  bad "all three JS sites that name the prose container agree" \
      "templates=$n_set (want 2) queries=$n_q (want 2) createElement=$n_new (want 1)"
fi

echo "=== 10. the entry-user colour override names only what it must ==="
# Seven of the ten selectors it used to list (p, li, h1-h4, td) set no colour at
# all and simply inherit from the container. Naming them was the recipe written
# out ten times. The three that DO declare their own colour must stay: blockquote
# and the table header each have a rule of their own that would otherwise win.
ovr="$(rule_body ".entry-user .entry-bubble .prose" \
                 ".entry-user .entry-bubble .prose blockquote" \
                 ".entry-user .entry-bubble .prose-table th")"
if [ "$ovr" = "color: var(--primary-foreground);" ]; then
  ok "the entry-user prose override is down to the 3 selectors that need it"
else
  bad "the entry-user prose override is down to the 3 selectors that need it" \
      "expected the 3-selector form with primary-foreground, got: $ovr"
fi
# If someone re-adds a redundant selector the rule SET no longer matches, which
# is the signal - not a silently larger block.
if [ -z "$(rule_body '.entry-user .entry-bubble .prose p')" ]; then
  ok "no redundant .prose p entry in the override list (it inherits)"
else
  bad "no redundant .prose p entry in the override list" \
      "re-adding it means inheriting was assumed not to hold - verify before removing"
fi

echo "=== 11. the toast surface stays on the toast namespace ==="
# The stack used to be .qa-feedback-*, which put the global notifications in the
# Quick Actions namespace for no reason - the same naming lie as .qac-btn, which
# turned out to be dead. Its two interactive children were hand-rolled copies of
# primitives that already existed.
#
# Counted over SELECTORS, so a rule naming .toast five times counts once.
py_toast_selectors() { python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
n = 0
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    for sel in m.group(1).split(","):
        if re.search(r"(^|[\s])\.toast[a-z-]*", sel.strip()):
            n += 1
print(n)
PY2
}
if [ "$(py_toast_selectors)" -ge 14 ]; then
  ok "the toast namespace covers the stack, card and its parts"
else
  bad "the toast namespace covers the stack, card and its parts" \
      "only $(py_toast_selectors) selectors - the rename looks half-applied"
fi
# Not one .qa-feedback-* SELECTOR may survive. Comments are stripped first:
# the block header deliberately names the old namespace to explain the rename,
# and that prose is worth keeping.
qa_left="$(python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
print(css.count("qa-feedback"))
PY2
)"
qa_js="$(grep -c 'qa-feedback' "$JS" || true)"
qa_html="$(grep -c 'qa-feedback' "$HTML" || true)"
if [ "$qa_left" -eq 0 ] && [ "$qa_js" -eq 0 ] && [ "$qa_html" -eq 0 ]; then
  ok "no qa-feedback selector survives (css selectors, js, html)"
else
  bad "no qa-feedback selector survives" \
      "css=$qa_left js=$qa_js html=$qa_html"
fi
# The shared entrance keyframe was named after ONE of its seven users, which is
# how it ended up misleading. It is now named for what it does.
n_pop="$(grep -c 'animation: pop-in' "$CSS" || true)"
if [ -n "$(grep -oE '@keyframes pop-in' "$CSS")" ] && [ "$n_pop" -ge 6 ]; then
  ok "the shared entrance keyframe is pop-in, used by $n_pop rules"
else
  bad "the shared entrance keyframe is pop-in" \
      "keyframes: $(grep -oE '@keyframes [a-z-]+' "$CSS" | tr '\n' ' ') uses=$n_pop"
fi
# Two controls here were duplicates of C3 primitives. If either hand-rolled
# rule comes back, the duplication this migration removed is back too.
for dead in ".toast-action" ".qa-feedback-action" ".toast-close" ".qa-feedback-close"; do
  if grep -qE "^\s*${dead//./\\.}(:|\s*\{)" "$CSS"; then
    bad "no $dead rule survives" "the primitive collapse is undone"
  else
    ok "no $dead rule survives"
  fi
done

echo "=== 12. the toast's two controls ARE the primitives ==="
# notify() must EMIT the primitive composition. Asserted on the JS, because a
# class the JS never sets is exactly the dangling-class failure section 1 hunts
# in the other direction.
if grep -q 'btn.className = "btn btn-xs btn-primary";' "$JS"; then
  ok "the toast action button is .btn.btn-xs.btn-primary"
else
  bad "the toast action button is .btn.btn-xs.btn-primary" \
      "got: $(grep -o 'btn.className = "[^"]*"' "$JS" | head -1)"
fi
# 28px was the tell: --btn-height-xs is the only 28px control height, so a
# toast action that is NOT .btn-xs is not 28px.
if rule_body ".btn-xs" | grep -q 'var(--btn-height-xs)'; then
  ok ".btn-xs still resolves its height from the scale (the toast action's 28px)"
else
  bad ".btn-xs still resolves its height from the scale" "got: $(rule_body ".btn-xs")"
fi
if grep -q 'closeBtn.className = "btn-icon btn-icon-24 btn-icon-square";' "$JS"; then
  ok "the toast close button is .btn-icon.btn-icon-24.btn-icon-square"
else
  bad "the toast close button is .btn-icon.btn-icon-24.btn-icon-square" \
      "got: $(grep -o 'closeBtn.className = "[^"]*"' "$JS")"
fi
if rule_body ".btn-icon-24" | grep -qE '24px'; then
  ok ".btn-icon-24 is still 24px, which is what the close button was"
else
  bad ".btn-icon-24 is still 24px" "got: $(rule_body ".btn-icon-24")"
fi
# Every class notify() sets must have a rule, or part of the toast renders bare.
# Listed as "class|what it is" pairs; the loop keeps them from drifting apart.
while IFS='|' read -r cls what; do
  [ -n "$cls" ] || continue
  emitted="$(grep -c "className = \"$cls\"" "$JS" || true)"
  styled="$(python3 - "$CSS" "$cls" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
want = "." + sys.argv[2]
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    for sel in m.group(1).split(","):
        if sel.strip() == want:
            print(1); raise SystemExit
print(0)
PY2
)"
  if [ "$emitted" -gt 0 ] && [ "$styled" -eq 1 ]; then
    ok ".$cls is emitted and styled ($what)"
  else
    bad ".$cls is emitted and styled ($what)" \
        "emitted=$emitted styled=$styled"
  fi
done <<'LIST'
toast|the card itself
toast-icon|the status icon
toast-content|the text column
toast-title|the title
toast-meta|the meta line
toast-actions|the action row
LIST
# The four state classes are built by concatenation, so each concrete value
# needs a rule - checking the bare prefix would be satisfied by any sibling.
for st in loading success error; do
  if grep -q "className = \"toast\" + (type" "$JS" && [ -n "$(rule_body ".toast.$st")" ]; then
    ok "the .toast.$st state has a rule (notify builds it by concatenation)"
  else
    bad "the .toast.$st state has a rule" "got: $(rule_body ".toast.$st")"
  fi
done
# .closing is added by classList, separately from the type assignment.
if [ -n "$(rule_body ".toast.closing")" ]; then
  ok ".toast.closing has a rule for the dismiss animation"
else
  bad ".toast.closing has a rule" "dismissNotification adds .closing to an unstyled state"
fi
# The stack must stay a click-through overlay: only the cards take pointer
# events, so a toast never blocks the chat underneath it. Losing the `none` on
# the container makes every toast a full-width invisible shield.
stack_pe="$(rule_body ".toast-stack" | grep -o 'pointer-events:[[:space:]]*[a-z]*' | head -1)"
child_rule="$(rule_body ".toast-stack > *")"
if [ "$stack_pe" = "pointer-events: none" ] && [ "$child_rule" = "pointer-events: auto;" ]; then
  ok "the stack is click-through and only its cards take pointer events"
else
  bad "the stack is click-through and only its cards take pointer events" \
      "stack: [$stack_pe] child: [$child_rule]"
fi

echo "=== 13. the entry containers: collapsed, and no dead selectors ==="
# Three rules used to repeat `border: none` and `border-radius:
# var(--radius-bubble)`. That repetition is not cosmetic - it is what hid a
# real bug. .entry-failed set only a border-COLOUR, and with every variant
# declaring border-style:none there was no border to colour, so the documented
# "only the border goes wax-red" never rendered. Re-run that bug as a mutation
# below.
if [ "$(rule_body ".entry-bubble")" = "padding: 10px 14px; border-radius: var(--radius-bubble);" ]; then
  ok ".entry-bubble states its own shape once, with no border"
else
  bad ".entry-bubble states its own shape once" \
      "got: $(rule_body ".entry-bubble")"
fi
# The failed border has to declare a STYLE and a WIDTH, not just a colour.
# Mutation: back to `border-color` only -> red, which is the original bug.
failed="$(rule_body ".entry-failed .entry-bubble")"
if printf '%s' "$failed" | grep -qE 'border:[[:space:]]*[0-9]+px solid' && \
   printf '%s' "$failed" | grep -q 'var(--destructive-bright)'; then
  ok ".entry-failed draws a real border (width + style + the destructive token)"
else
  bad ".entry-failed draws a real border" \
      "a bare border-color cannot render against border-style:none - got: $failed"
fi
# And no non-failed variant may declare one, or the 2px would be paid by every
# bubble to make one state visible.
_b=0
for _sel in ".entry-perla .entry-bubble" ".entry-user .entry-bubble"; do
  case "$(rule_body "$_sel")" in *border:*) _b=$((_b + 1)) ;; esac
done
if [ "$_b" -eq 0 ]; then
  ok "no ordinary bubble declares a border (only the failed one does)"
else
  bad "no ordinary bubble declares a border" "$_b of 2 do"
fi

# --- dead selectors, verified by reachability not by memory ---
# .entry-system and .entry-image-grid had no producer. addEntry is only ever
# called with "perla"/"user" and addHistoryEntry with "user"/"perla"/
# "perla entry-tier0" - the class name is BUILT by concatenation
# (`"entry entry-" + kind`), so grepping for the literal would have found
# nothing while the class was still live. This asserts the CSS side stays
# clean; the producer audit is re-run from the JS below.
if grep -qE '^\s*\.entry-system(\s|,|:|\{)' "$CSS"; then
  bad "no .entry-system rule survives" \
      "$(grep -cE '^\s*\.entry-system(\s|,|:|\{)' "$CSS") rules - the class has no producer"
else
  ok "no .entry-system rule survives (no producer builds that class)"
fi
if grep -qE '^\s*\.entry-image-grid(\s|,|:|\{)' "$CSS"; then
  bad "no .entry-image-grid rule survives" \
      "$(grep -cE '^\s*\.entry-image-grid(\s|,|:|\{)' "$CSS") rules - images are only rendered singly"
else
  ok "no .entry-image-grid rule survives (the grid was never wired up)"
fi
# Guard the audit itself: if a call site starts passing a new kind, the CSS for
# it must exist. Enumerated from the real call sites, not a hardcoded list.
py_entry_kinds() { python3 - "$JS" <<'PY2'
import re, sys
js = open(sys.argv[1], encoding="utf-8").read()
kinds = set(re.findall(r'addEntry\("([a-z0-9_-]+)"', js))
kinds |= set(re.findall(r'addHistoryEntry\("([a-z0-9_ ]+)"', js))
for k in sorted(kinds):
    print(k.split(" ")[0])
PY2
}
missing=""
for k in $(py_entry_kinds); do
  grep -qE "^\s*\.entry-$k(\s|,|:|\{)" "$CSS" || missing="$missing $k"
done
if [ -z "$missing" ]; then
  ok "every entry kind the constructors can build has CSS ($(py_entry_kinds | tr '\n' ' '))"
else
  bad "every entry kind the constructors can build has CSS" "unstyled:$missing"
fi

echo "=== 14. no border-COLOUR is left pointing at nothing ==="
# Found by accident, then confirmed by sweeping the whole file: `* { border-color:
# var(--border) }` means every element has a border colour, so a rule that sets
# ONLY a colour looks like it works. It does not - with border-style still `none`
# there is no border to paint. That is exactly how .entry-failed's documented
# "the border goes wax-red" never rendered, hidden by three neighbouring rules
# that each said `border: none`.
#
# So: every border-color-only rule must have a border STYLE and WIDTH reachable
# for the same element - from its own selector, or from another class on the same
# element in real markup. Resolution has to consider co-occurring classes, or
# .history-daypicker-btn.open is a false positive (it is a .btn).
unresolved="$("$HERE"/border_source_audit.py "$CSS" "$HERE/../perla-companion.html" "$JS")"
if [ -z "$unresolved" ]; then
  ok "every border-colour-only rule has a border to paint (swept the whole file)"
else
  bad "every border-colour-only rule has a border to paint" "$unresolved"
fi

echo "=== 15. the panel shell, and the scrollbar migration actually finished ==="
# .panel-header / .panel-body exist because the modal and the drawer each wrote
# the same frame out longhand: six identical declarations in the two headers,
# and `flex: 1; min-height: 0; overflow-y: auto` in both bodies. Each kept only
# what was genuinely its own afterwards.
if [ "$(rule_body ".panel-body")" = "flex: 1; min-height: 0; overflow-y: auto;" ]; then
  ok ".panel-body is the flex-1 / min-height-0 / scroll recipe"
else
  bad ".panel-body is the flex-1 / min-height-0 / scroll recipe" "got: $(rule_body ".panel-body")"
fi
for want in "display: flex" "align-items: center" "gap: 10px" "flex-shrink: 0"; do
  if rule_body ".panel-header" | grep -q "$want"; then
    ok ".panel-header keeps $want"
  else
    bad ".panel-header keeps $want" "got: $(rule_body ".panel-header")"
  fi
done
# Each shell adds only its own thing, and the primitives add nothing back.
if [ "$(rule_body ".file-viewer-modal-header")" = "border-bottom: 1px solid var(--input);" ] && \
   [ "$(rule_body ".qa-drawer-header")" = "cursor: pointer;" ]; then
  ok "each header keeps only what is its own (modal border / drawer cursor)"
else
  bad "each header keeps only what is its own" \
      "modal: $(rule_body ".file-viewer-modal-header") | drawer: $(rule_body ".qa-drawer-header")"
fi
# The modal scrolls BOTH axes so wide content can move sideways; that is the one
# thing separating it from the drawer, so it must not be lost in the collapse.
if rule_body ".file-viewer-modal-body" | grep -q 'overflow: auto'; then
  ok "the modal body still scrolls both axes (wide content needs sideways)"
else
  bad "the modal body still scrolls both axes" "got: $(rule_body ".file-viewer-modal-body")"
fi
# All four elements must actually carry the primitives - a primitive nothing
# uses is the dangling-class failure in the other direction.
# Uses python, not grep: bash mangles the quoting these patterns need.
py_has_class() {  # py_has_class "<class>"  -> prints the elements carrying it
  python3 - "$HTML" "$JS" "$1" <<'PY2'
import re, sys
# argv holds PATHHS - open them. Reading argv[1] directly silently yields the
# filename (20 bytes, zero matches) and reports "carries no class" for
# everything, which looks like a missing class rather than a broken helper.
html = open(sys.argv[1], encoding="utf-8").read()
js = open(sys.argv[2], encoding="utf-8").read()
want = sys.argv[3]
hits = []
for m in re.finditer(r'class="([^"]*)"', html):
    if want in m.group(1).split():
        hits.append(m.group(1))
for m in re.finditer(r'className\s*=\s*"([^"]*)"', js):
    if want in m.group(1).split():
        hits.append(m.group(1))
print("|".join(dict.fromkeys(hits)))
PY2
}
for sel in "panel-header" "panel-body"; do
  n="$(py_has_class "$sel" | tr '|' '\n' | grep -c "$sel" || true)"
  if [ "${n:-0}" -ge 2 ]; then
    ok ".$sel is carried by both shells (modal + drawer)"
  else
    bad ".$sel is carried by both shells (modal + drawer)" \
        "only ${n:-0} of 2 - the collapsed rule now styles nothing"
  fi
done
# The scrollbar half of the same migration. .scroll-area gained the Firefox
# declarations its own comment already claimed, which let three hand-written
# copies go: a six-selector list plus .qa-drawer-body and .history-day-menu.
# Section 4 asserts the declarations happen once; this asserts the CONSUMERS all
# carry the class, since a rule can be declared once and still reach nobody.
for sel in "page" "drive-panel" "file-viewer-body" "file-viewer-modal-body" \
           "qa-drawer-body" "history-day-menu"; do
  if py_has_class "$sel" | tr '|' '\n' | grep -q "scroll-area"; then
    ok ".$sel carries .scroll-area (so the one recipe reaches it)"
  else
    bad ".$sel carries .scroll-area" \
        "the shared scrollbar rule was deleted, so this surface lost its thumb styling"
  fi
done
# The renderer emits the <pre> for code blocks, so .prose pre is reachable only
# through that one line.
if grep -q '<pre class="scroll-area">' "$JS"; then
  ok "rendered code blocks emit .scroll-area on their <pre>"
else
  bad "rendered code blocks emit .scroll-area on their <pre>" \
      "the shared scrollbar rule was deleted, so code blocks lost their thumb"
fi

echo "=== 16. the raised surface is one primitive, and it is opt-in ==="
# Four components each wrote the same three declarations. This asserts the
# primitive exists AND that every one of the four actually carries it - a
# primitive nothing uses styles nothing, and a rule that kept its own copy
# alongside is the duplication coming straight back.
# Flat fill, since the file-wide flattening. A gradient here would reintroduce
# the exact duplication the primitive exists to end.
if [ "$(rule_body ".surface-raised")" = "background: var(--card); border: 1px solid var(--input); border-radius: var(--radius-xl);" ]; then
  ok ".surface-raised is a FLAT card fill plus a border, stated once"
else
  bad ".surface-raised is a FLAT card fill plus a border, stated once" \
      "got: $(rule_body ".surface-raised")"
fi
if [ "$(rule_body ".surface-raised-accent")" = "border-color: var(--primary-dim);" ]; then
  ok ".surface-raised-accent is the only variant"
else
  bad ".surface-raised-accent is the only variant" "got: $(rule_body ".surface-raised-accent")"
fi
py_carries() {  # py_carries "<class>" -> prints the class lists carrying it
  python3 - "$HTML" "$JS" "$1" <<'PY2'
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
js = open(sys.argv[2], encoding="utf-8").read()
want = sys.argv[3]
out = []
for m in re.finditer(r'class="([^"]*)"', html):
    if want in m.group(1).split():
        out.append(m.group(1))
for m in re.finditer(r'className\s*=\s*"([^"]*)"', js):
    if want in m.group(1).split():
        out.append(m.group(1))
print("|".join(dict.fromkeys(out)))
PY2
}
# Every consumer, asserted individually: these four were identical, so "all of
# them" is exactly the set that must not drift apart.
for sel in drive-toolbar drive-item drive-new-folder-row qa-input-row; do
  if py_carries surface-raised | tr '|' '\n' | grep -q "\b$sel\b"; then
    ok ".$sel carries .surface-raised"
  else
    bad ".$sel carries .surface-raised" \
        "its rule no longer declares the surface, so it renders bare"
  fi
done
# No gradient may be reintroduced on ANY surface. This is the file-wide
# flatness rule, and it is deliberately broader than the four consumers above:
# twelve gradient fills accumulated precisely because only four narrow surfaces
# were ever checked. The three remaining radial-gradient rules are the declared
# exceptions (the ambient page wash and the two logo marks), listed by selector
# so adding a fourth has to be a deliberate edit here.
py_gradients() { python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
EXC = {"body", ".gate-mark", ".welcome-mark"}
hits = []
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    body = m.group(2)
    if "-gradient(" not in body:
        continue
    for sel in (" ".join(m.group(1).split())).split(","):
        s2 = sel.strip()
        if s2 not in EXC:
            hits.append(s2)
print("; ".join(sorted(set(hits))))
PY2
}
_grads="$(py_gradients)"
if [ -z "$_grads" ]; then
  ok "no gradient anywhere except the 3 declared exceptions (page wash, 2 logo marks)"
else
  bad "no gradient anywhere except the declared exceptions" "found: $_grads"
fi
# And the exceptions must still be exactly those three, so the list cannot rot.
for exc in "body" ".gate-mark" ".welcome-mark"; do
  if grep -qE "^\s*\Q$exc\E\s*\{" "$CSS" 2>/dev/null || grep -qE "^\s*$(printf '%s' "$exc" | sed 's/\./\\./g')\s*[,{]" "$CSS"; then
    ok "the declared exception $exc still exists"
  else
    bad "the declared exception $exc still exists" \
        "the exception list has rotted - a removed exception means the list is wrong"
  fi
done

echo "=== 17. the question card has a named type scale ==="
# Thirteen .qac-* rules carried seven rem font sizes with no name for the
# hierarchy. The :root comment already promised "Phase C migrates the call
# sites family by family; this is where they land" - this is that family.
py_qac_scale_defs() { python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
print(len(re.findall(r"--qac-text-[a-z]+:\s*[\d.]+rem", css)))
PY2
}
if [ "$(py_qac_scale_defs)" -eq 7 ]; then
  ok "the card-local scale declares all 7 steps"
else
  bad "the card-local scale declares all 7 steps" "found $(py_qac_scale_defs)"
fi
# Every .qac-* rule must read the scale. A bare rem left behind is the whole
# point of the exercise, and it is invisible in review because the value is
# still correct - only the hierarchy is lost.
py_qac_bare() { python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
hits = []
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    if not re.search(r"\.qac-", m.group(1)):
        continue
    for d in re.findall(r"font-size:\s*([\d.]+(?:rem|px))", m.group(2)):
        hits.append(" ".join(m.group(1).split()) + " -> " + d)
print("; ".join(hits))
PY2
}
if [ -z "$(py_qac_bare)" ]; then
  ok "no .qac-* rule is left on a bare font-size"
else
  bad "no .qac-* rule is left on a bare font-size" "$(py_qac_bare)"
fi
# And each call site must name a step that EXISTS. A typo'd token falls back to
# the inherited size silently, so the pairing is asserted rather than assumed.
for pair in "qac-title:title" "qac-label:label" "qac-sub:sub" "qac-desc:desc" \
            "qac-status:status" "qac-command:command" "qac-progress:progress"; do
  cls="${pair%%:*}"; step="${pair##*:}"
  # .qac-custom shares the label step, so it is checked with .qac-label above.
  if [ "$cls" = "qac-label" ]; then
    grep -qE '^\s*\.qac-custom \{' "$CSS" || continue
  fi
  if rule_body ".$cls" | grep -q "var(--qac-text-$step)"; then
    ok ".$cls reads --qac-text-$step"
  else
    bad ".$cls reads --qac-text-$step" \
        "got: $(rule_body ".$cls") - an undefined token inherits instead"
  fi
done
if rule_body ".qac-custom" | grep -q "var(--qac-text-label)"; then
  ok ".qac-custom shares the label step (it is a label-sized field)"
else
  bad ".qac-custom shares the label step" "got: $(rule_body ".qac-custom")"
fi

# --- the [hidden] collapse stays collapsed ---
# 21 rules were deleted because the global !important rule already covered
# them. Asserted as a COUNT so they cannot quietly return one at a time, which
# is exactly how they accumulated in the first place.
py_hidden_display_rules() { python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
n = 0
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    for sel in (" ".join(m.group(1).split())).split(","):
        s2 = sel.strip()
        if "[hidden]" not in s2:
            continue
        # A combinator, :not() or :has() means the rule does something OTHER
        # than hide its own target, so it is not a copy of the global rule.
        # * and not +: the bare `[hidden]` selector has ZERO characters before
        # the attribute, so requiring one silently failed to count the global
        # rule and reported 0 for a stylesheet that had it.
        if not re.fullmatch(r"[\w.#-]*\[hidden\]", s2):
            continue
        if re.search(r"(^|;)\s*display\s*:\s*none", m.group(2)):
            n += 1
print(n)
PY2
}
_hd="$(py_hidden_display_rules)"
if [ "$_hd" -eq 1 ]; then
  ok "exactly one [hidden] display rule: the global one"
else
  bad "exactly one [hidden] display rule" \
      "found $_hd - a per-element [hidden] copy is back, and the global rule already covered it"
fi
# The three that merely MENTION [hidden] do something else and must survive.
for keeper in "#quickActionsPanel:not([hidden]) ~ .content-wrap" \
              ".reminder-composer:has(.reminder-composer-menu[hidden])" \
              ".reminder-composer:has(.reminder-composer-menu[hidden]) .reminder-composer-top"; do
  if [ -n "$(rule_body "$keeper")" ]; then
    ok "kept: ${keeper} (mentions [hidden], but is not a hide rule)"
  else
    bad "kept: ${keeper}" \
        "deleting it changes behaviour - it hides a SIBLING or repositions a row"
  fi
done

echo
echo "=================================="
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1