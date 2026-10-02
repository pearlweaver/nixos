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
missing = sorted(tokens - known)
print(len(missing))
for x in missing:
    print("#   ." + x)
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
         btn-icon btn-icon-outline btn-icon-28 btn-icon-30 btn-icon-32 btn-icon-34; do
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
# Three chrome dividers became .divider / .divider-vertical. .md hr is
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
SIZES = {"btn-icon-28", "btn-icon-30", "btn-icon-32", "btn-icon-34"}
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

# .btn-icon sets display:inline-flex, which outranks a bare [hidden] attribute
# on specificity alone. #voiceDraftPlay is hidden by that rule.
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    if ".btn-icon[hidden]" in m.group(1):
        sys.exit(0 if "display: none !important" in " ".join(m.group(2).split()) else 1)
sys.exit(1)
PY
then
  ok ".btn-icon[hidden] still wins over the class's display"
else
  bad ".btn-icon[hidden] still wins over the class's display" \
      "a hidden icon button (voiceDraftPlay) would stay visible"
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
for v in btn-icon btn-icon-outline; do
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
.qa-input-cancel|padding|the cancel button is narrower than the paired go button
.qa-input-cancel|color|it is a neutral ghost, so it drops the go button's accent text
.qa-input-cancel|background|ditto - flat instead of the accent gradient
.retry-btn|color|retry sits on an already-failed message, so it wears the destructive tint
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
    # Key on each selector in the list INDIVIDUALLY: `.md-table th, .md-table td`
    # and a later bare `.md-table td` are the same selector for one member, and
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
rule_body() { # rule_body <selector> [<selector>...]
  # Matches when the rule's selector SET equals the arguments, so a rule written
  # as `.a,\n.b` is found by either name. A single-name lookup failed on exactly
  # that shape and reported a correct rule as missing.
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
# ...and the token is load-bearing: the three composer controls must read it, or
# resizing one would silently desync from the draft's min-height.
n=0
for sel in ".send-btn" ".mic-btn" ".attach-btn"; do
  case "$(rule_body "$sel")" in *var\(--control-lg\)*) n=$((n + 1)) ;; esac
done
if [ "$n" -eq 3 ]; then
  ok "all three composer controls read --control-lg"
else
  bad "all three composer controls read --control-lg" \
      "only $n of 3 do - resizing a control desyncs the draft's min-height"
fi

echo
echo "=================================="
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1