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

# --- how many times is a selector declared, and which body is in effect ---
# NOT `rule_body`. That helper takes the FIRST match, which is the wrong end of
# the cascade: appending
#
#     @media (max-width: 640px) { .btn[data-size="pill"] { height: 60px; } }
#
# renders both image-editor buttons 60px tall below 640px wide and left every pin
# in this section green at 241/241. Section 7 cannot catch it either - it skips
# `@`-rules by design, so an @media body is invisible to it. So the bodies pinned
# here and in section 19 are read through this helper, which answers the two
# questions separately: the COUNT, and the LAST body (the one that renders).
#
# A count of one is the invariant, and it is asserted rather than assumed because
# a second copy is dead code whether or not it happens to render the right pixels
# - someone editing it later would change nothing.
#
# The table key is the selector SET, and the `[^{}]` scan has no idea whether a
# rule sits inside an @media wrapper: it drops the prelude. That is precisely the
# property wanted, because a media-scoped override then COLLIDES with its
# top-level twin instead of landing in a second bucket. It is also why the check
# is scoped to the selectors named on the command line rather than swept
# file-wide: 22 selector sets in this stylesheet are declared more than once
# (mostly @keyframes percentage stops, which this scan flattens, plus the
# ordinary responsive overrides), and a file-wide duplicate check would fire
# constantly on a correct file.
#
# It lives at the top rather than beside its first caller because this file treats
# a helper introduced after its first use as not a helper (see the note on
# `rule_body` above) - and section 2c needs it 1700 lines earlier than section 18
# did.
#
# One line per selector: "<selector>|<occurrences>|<last body>". No selector
# contains a "|", so the shell can split on it with `cut`.
py_axis_rules() { # py_axis_rules <selector> [<selector>...]
  python3 - "$CSS" "$@" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
rules = {}
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    # A LIST, not setdefault-overwrite: the last entry is the body the cascade
    # applies, and len() is what makes a shadowed copy visible at all.
    rules.setdefault(frozenset(s.strip() for s in m.group(1).split(",")),
                     []).append(" ".join(m.group(2).split()))
for sel in sys.argv[2:]:
    bodies = rules.get(frozenset([sel]), [])
    print("%s|%d|%s" % (sel, len(bodies), bodies[-1] if bodies else "<no rule>"))
PY2
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
# Read the COMMENT-STRIPPED copy, not the raw file. A why-comment that names a
# class is prose about a rule, not the rule, and grepping the raw stylesheet
# counted the two as the same thing - so a primitive could be deleted outright
# and this loop stayed green as long as some comment still mentioned it.
#
# The stripped copy is computed once, into $STRIPPED_CSS, and shared by every
# section below that greps for a name rather than reading a rule body: 2, 2b, 3a,
# 3b, the text-button collapse and the badge collapse each computed their own
# identical copy. Four of those six are unaffected either way; section 2 is the
# one that changes, and it is the only one that was wrong.
#
# It goes to a FILE rather than a variable that each loop pipes into grep. `grep
# -q` exits the moment it finds its first match, printf takes SIGPIPE, and under
# `set -o pipefail` that failure becomes the pipeline's exit status - so the loop
# reported "not defined" for names that were defined, and did so only for the
# names grep found early enough to win the race. A file has neither race nor pipe.
STRIPPED_CSS="$(mktemp)"
trap 'rm -f "$STRIPPED_CSS"' EXIT
python3 -c "import re,sys;open(sys.argv[2],'w',encoding='utf-8').write(re.sub(r'/\*[\s\S]*?\*/','',open(sys.argv[1],encoding='utf-8').read()))" "$CSS" "$STRIPPED_CSS"
# Mutation: rename any of these selectors in the stylesheet -> red.
for t in divider divider-vertical scroll-area spinner empty status \
         input input-sunken textarea radio checkbox \
         btn-icon btn-icon-outline btn-icon-accent btn-icon-square \
         btn-icon-28 btn-icon-30 btn-icon-32 btn-icon-34 btn-icon-lg \
         btn btn-xs btn-sm btn-md btn-block \
         btn-primary btn-outline btn-ghost btn-solid btn-destructive \
         btn-destructive-flat \
         badge badge-outline badge-solid badge-label \
         sidebar sidebar-rail sidebar-header sidebar-content sidebar-group \
         sidebar-group-label sidebar-menu sidebar-menu-button sidebar-footer \
         sidebar-trigger \
         sheet sheet-overlay input-underline content-frame content-frame-header \
         content-frame-body alert-dialog alert-dialog-title \
         alert-dialog-description alert-dialog-actions; do
  # Match .name as a WHOLE token. A plain `\.name` also matches the `.checkbox`
  # inside `.radio, .checkbox`, so renaming only the standalone rule would have
  # left this assertion green - verified by mutation.
  #
  # The pill is NOT in this list and its absence is the point, not an omission:
  # it welded a size to a shape and is now two attribute selectors, registered in
  # section 18 because this loop can only name a CLASS.
  #
  # The shell family (sidebar / sheet / content frame / alert dialog) is here on
  # the same terms, and the reason it matters is the one this file exists to
  # catch: NOTHING in it has a consumer yet. Tasks 6-12 write the markup. Until
  # one of them does, a primitive in this stylesheet that is not on this list is
  # invisible to this suite - it can be deleted outright, or renamed, and every
  # section here stays green. So the list is the ONLY thing making them real.
  #
  # Five names beyond the fifteen the brief listed, all of them selectors the
  # brief's own CSS block added and its registry snippet omitted:
  # .content-frame-header, .content-frame-body, .alert-dialog-title,
  # .alert-dialog-description and .alert-dialog-actions. Each is a rule with no
  # consumer and no other guard, which is precisely the shape that goes missing.
  #
  # KNOWN LIMIT of this loop, found by mutation - deleting each of the fifty-five
  # registered names' base rules one at a time and watching this loop - and NOT
  # fixable with a better pattern: it asks whether `.name` occurs anywhere as a
  # whole token, so a DESCENDANT selector, a STATE or PSEUDO selector, a second
  # declaration of the same selector, or a SELECTOR LIST keeps a name alive after
  # its own rule is gone. Only a name's own BASE rule going missing looks like
  # this, and that is a strictly smaller question than "is this primitive real".
  #
  # Of the twenty names this layer added, EXACTLY THREE stay green:
  #
  #   .sidebar-group-label   the collapsed-state rule names it as a descendant
  #                          (`.sidebar[data-collapsed="true"] .sidebar-group-label`)
  #   .sidebar-menu-button   its own `:hover` / `[aria-current]` / `svg` selectors
  #   .input-underline       its own `::placeholder` and `:focus` rules
  #
  # All three are genuinely shadowed by another rule, which is the floor for a
  # name-based check. Section 19 catches all three, because it keys on the exact
  # selector set rather than on the name. The other seventeen go red here.
  #
  # ACROSS ALL FIFTY-FIVE, deleting each name's base rule in turn: 36 red / 19
  # green on the stripped copy this loop reads. The same measurement against the
  # RAW file - which is what it used to read, and what let a mention in prose
  # stand in for a rule - is 29 red / 26 green. (It was 30 / 25 before the
  # .sidebar-rail why-comment landed; that comment names .sidebar, so the raw
  # reading rescues one more name. Re-measure after editing anything here rather
  # than carrying either pair of figures forward.)
  # The seven that changed are .divider-vertical, .btn-icon-square, .btn-sm,
  # .btn-md, .sidebar, .sidebar-rail and .sheet-overlay - every one of them
  # alive only because a why-comment named it. That is the whole value of reading
  # the stripped copy: a mention in prose is not a rule.
  #
  # The other sixteen green names are all pre-existing, and all the same three
  # shapes: a state or pseudo rule on the name (.scroll-area::-webkit-scrollbar,
  # .input:focus, .textarea::placeholder, .status:empty, .radio:checked, and the
  # :hover / :active / :disabled rules behind the nine green names of the button
  # family - .btn-icon, .btn-icon-outline, .btn-icon-accent, .btn, .btn-primary,
  # .btn-ghost, .btn-solid, .btn-destructive and .btn-destructive-flat), a second
  # declaration of the SAME selector (.spinner is re-declared inside a
  # prefers-reduced-motion block, so the top-level rule can go without the name
  # going with it), or a member of a selector list (.radio and .checkbox - each
  # has exactly ONE single-part rule of its own, and each also appears inside
  # `.radio, .checkbox` and `.radio:checked, .checkbox:checked`, so deleting the
  # single-part rule leaves the list occurrence and the `:checked` pseudo rules
  # to match). Not one of the nineteen is held up by prose.
  if grep -qE "(^|[ ,])\.$t([ ,:{]|$)" "$STRIPPED_CSS"; then
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
# ($STRIPPED_CSS is computed above section 2, which needs it too.)
for legacy in \
  '.reminder-composer input[type="text"]' \
  '.reminder-composer input[type="datetime-local"], .reminder-composer select' \
  '.drive-new-folder-row input' \
  '.qa-input-row input' \
  '.dropdown-row' \
  '.qac-input' \
  '#textInput {'; do
  n=$(grep -cF "$legacy" "$STRIPPED_CSS" || true)
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
echo "=== 2c. the underline collapse STAYS collapsed ==="
# The two underline fields - the gate password and the elevation token - each
# wrote the whole recipe out longhand: transparent background, no border, a 1px
# bottom rule, the foreground colour, the font, the outline, the transition and
# a focus colour. That is .input-underline. Their class application replaced it.
#
# `.drive-path-edit-row input` was named as the third copy and is deliberately
# NOT converted, so it is deliberately NOT on the list below. It is not a third
# underline: it has no bottom rule at all, because it sits INSIDE a bordered,
# rounded, sunken pill (`.drive-path-edit-row`), so an underline would draw a
# border inside a border. It shares only the borderless half of the recipe, at a
# different size and in --font-mono. Whether the path editor becomes an
# underline field is a Layer 3 decision about the Drive redesign, not a
# side-effect of a de-duplication sweep - which is also why the primitive's
# `border-bottom` has to stay asserted below rather than being left implicit.
#
# Mutation: add `background: transparent; border: none; border-bottom: 1px solid
#            var(--border); outline: none;` back to either selector -> red.
# Mutation: drop `input-underline` from #gatePassword -> red.
# Mutation: delete .input-underline's border-bottom -> red (see section 14).
#
# Asked as DECLARATIONS, not as the selector's absence: both selectors
# legitimately survive, because each site keeps what is genuinely its own (see
# the two pins below). A plain `grep -F` on the selector name would also have
# matched the surviving `:focus` rule - `.gate-card input[type="password"]:focus`
# contains the string - so it would have called a half-collapsed duplicate
# collapsed. What has to go is the SHARED half.
#
# DEPENDS ON THE COUNT ASSERTION BELOW, incidentally rather than by design: this
# loop reads through `rule_body`, which takes the FIRST match, so a media-scoped
# or otherwise second copy of either selector is invisible here - the recipe
# check would score the top-level rule and pass. That is survivable only because
# the pins below ask the COUNT of both selectors and fail on anything but one,
# and they sit BELOW this loop, so they must not be deleted or reordered out of
# the file without moving this dependency with them. It is a coupling, not a hole;
# it is written down here so that deleting the count assertion does not silently
# restore a green suite on a duplicated rule.
for spec in \
  '.gate-card input[type="password"]' \
  '.elevate-composer input[type="password"]'; do
  _body="$(rule_body "$spec")"
  _left=""
  for _decl in 'background:' 'border:' 'border-bottom' 'color:' 'outline:' 'transition:'; do
    case "$_body" in *"$_decl"*) _left="$_left $_decl" ;; esac
  done
  if [ -z "$_left" ]; then
    ok "$spec restates none of the shared recipe"
  else
    bad "$spec restates none of the shared recipe" "still declares:$_left"
  fi
done
# Two rules that were pure copies of the primitive's own and are simply gone:
# the elevate placeholder colour (verbatim `.input-underline::placeholder`) and
# the gate focus colour (verbatim `.input-underline:focus`). The gate's is the
# one that would have been missed - it is a different selector that says exactly
# what the primitive already says.
if [ -z "$(rule_body '.elevate-composer input[type="password"]::placeholder')" ]; then
  ok "the elevate placeholder rule is gone (it duplicated .input-underline::placeholder)"
else
  bad "the elevate placeholder rule is gone" "it duplicates .input-underline::placeholder verbatim"
fi
if [ -z "$(rule_body '.gate-card input[type="password"]:focus')" ]; then
  ok "the gate focus rule is gone (it duplicated .input-underline:focus)"
else
  bad "the gate focus rule is gone" "it duplicates .input-underline:focus verbatim"
fi
# Both fields must actually carry the class. Without this the deletions above
# are silent and catastrophic: an <input> with no matching rule renders as the
# UA default box, on the two screens a user meets before anything else works.
for id in gatePassword elevateInput; do
  if grep -qE "<input[^>]*id=\"$id\"[^>]*class=\"[^\"]*\binput-underline\b" "$HTML"; then
    ok "#$id carries .input-underline"
  else
    bad "#$id carries .input-underline" \
        "its longhand rule is gone and the class is not on the element, so the field renders bare"
  fi
done
# What each site legitimately keeps. These are the declarations the primitive
# cannot know, and they are what makes the two fields still render exactly as
# they did - so if they are dropped, the collapse has become a restyle.
#
# Read through `py_axis_rules`, NOT `rule_body` and NOT grep. `rule_body` breaks
# on the FIRST match and CSS applies the LAST, so it cannot see a second
# declaration at all - and the gate's `width: 100%` is the same token as many
# unrelated declarations, so a plain grep on the value would be no better. The
# two pins below therefore ask the COUNT and the BODY separately, exactly as
# section 18 does for the two size/shape axes and section 19 for the twenty
# shell primitives.
#
# The count is the half that was missing. Appending
#
#     @media (max-width: 640px) {
#       .gate-card input[type="password"] { letter-spacing: 0.4em; padding: 20px 8px; }
#     }
#
# renders both wrong below 640px wide - the real values are 0.15em and 10px 4px -
# and this whole section stayed green at 299/299 on a first-match read, because
# the body it compares is the top-level rule and the shadowing copy is never
# opened. The section 12 override-declaration check does not close it either: it
# skips `@`-rules outright, on purpose, because @media is the responsive pattern.
# So a media-scoped copy of either selector is now its own failure rather than
# something to notice in the value.
#
# Mutation: append that @media block -> red, on the count alone.
# Mutation: append a second plain rule for either selector -> red, on the count.
for spec in \
  '.gate-card input[type="password"]|width: 100%; font-size: var(--text-lg); text-align: center; padding: 10px 4px; letter-spacing: 0.15em;' \
  '.elevate-composer input[type="password"]|padding: 8px 2px;'; do
  sel="${spec%%|*}"; want="${spec#*|}"
  report="$(py_axis_rules "$sel")"
  count="${report#*|}"; count="${count%%|*}"
  got="$(rule_body "$sel")"
  if [ "$count" -eq 1 ]; then
    ok "$sel is declared exactly once"
  else
    bad "$sel is declared exactly once" \
        "$count declarations - the LAST one is what renders and the rest are dead code; look for an @media override"
  fi
  # The body is compared against rule_body, i.e. the PRIMARY rule, and only once
  # the count above has established there is no second one to be the real body:
  # comparing the LAST body here instead would report a shadowed copy as the
  # wanted value and leave the count assertion carrying the whole finding.
  if [ "$got" = "$want" ]; then
    ok "$sel keeps only what is its own"
  else
    bad "$sel keeps only what is its own" "got: ${got:-<no rule>}"
  fi
done
# And the one place the elevate composer overrides the primitive's own focus
# colour: an elevation token that fails to validate says so on its own
# underline, in the destructor's colour, not the neutral primary.
got="$(rule_body '.elevate-composer input[type="password"]:focus')"
if [ "$got" = "border-bottom-color: var(--destructive);" ]; then
  ok "the elevate field overrides the focus underline with --destructive"
else
  bad "the elevate field overrides the focus underline with --destructive" \
      "got: ${got:-<no rule>} - it now falls back to .input-underline's --primary"
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
for legacy in menu-divider editor-divider drive-toolbar-divider; do
  n=$(grep -c "\.$legacy" "$STRIPPED_CSS" || true)
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
  n=$(grep -cF "$legacy" "$STRIPPED_CSS" || true)
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
    # The lookbehind is what keeps `data-class="..."` from being read as the
    # class: without it this matches the FIRST `class="` in the tag, so a
    # data-class placed before the real one is scored as the class list and the
    # button's true classes are never seen.
    cm = re.search(r'(?<![\w-])class="([^"]*)"', attrs)
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
# NOT in this list, because these two are state hooks rather than styles and are
# still load-bearing: .history-tier-btn carries its `.active` selected state and
# the JS reads `.active` off it; .history-daypicker-btn carries `.open` and the
# rotated caret. Their geometry comes from .btn, but the names are queried.
for legacy in '.gate-card button' '.qac-btn' '.qac-btn-primary' '.qac-btn-destructive' \
              '.editor-pill-btn' '.elevate-submit' '.qa-input-go' '.qa-drawer-clear' \
              '#reminderAddBtn'; do
  n=$(grep -cF "$legacy" "$STRIPPED_CSS" || true)
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
    # Lookbehind, for the reason at line 256: a bare `class="` matches the FIRST
    # one in the tag, so `data-class="..."` placed first would be read as this
    # button's class list and the real one would never be examined.
    cm = re.search(r'(?<![\w-])class="([^"]*)"', m.group(0))
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
#
# A size is EITHER a class (.btn-xs/.btn-sm/.btn-md) or the named size axis the
# image editor's two buttons moved onto in section 18 - `data-size="pill"`. That
# is an attribute selector, so it cannot appear in a class list and has to be
# read off the TAG; reading it off the class value reported both of them as
# unsized, which is the assertion failing on correct markup. It also used to be
# `btn-pill`, which was a size AND a shape - so the set below lost an entry when
# the two axes were split, and a bare `.btn` is now unsized on either axis.
report=$(python3 - "$HTML" "$JS" <<'PYX'
import re, sys
SIZES = {"btn-xs", "btn-sm", "btn-md"}
# The size AXIS is matched by VALUE, not merely by presence: `data-size="pill"`
# is a rung, `data-size="enormous"` is a typo, and "the element has some
# data-size attribute" would wave both through.
SIZE_ATTR = r'data-size="(?:xs|sm|md|pill)"'
bad = []
# Static markup: read the class VALUE, not the raw attribute blob (the size class
# sits inside the quotes, and a whitespace-delimited match on the blob fails on
# the closing quote and reports every button as unsized) - but read the size AXIS
# off the whole tag, which is where a data-attribute selector lives.
for m in re.finditer(r"<button[^>]*>", open(sys.argv[1], encoding="utf-8").read()):
    # The lookbehind matters most HERE of the three sites in this file: read the
    # FIRST `class="` and a `data-class="..."` ahead of the real one is scored as
    # the class list, so this button reads as sized (or unsized) on the wrong
    # attribute and the genuine classes are never seen.
    cm = re.search(r'(?<![\w-])class="([^"]*)"', m.group(0))
    if not cm:
        continue
    classes = set(cm.group(1).split())
    # Only controls that really are text buttons: .btn present as a whole token,
    # and not one of the .btn-icon* family.
    if "btn" in classes and "btn-icon" not in classes \
       and not (classes & SIZES) and not re.search(SIZE_ATTR, m.group(0)):
        bad.append(cm.group(1))
# The question card builds its six in JS, where there is no tag to read. Matching
# `btn` as a set member is what keeps "btn-icon" out: a regex with \b would match
# at the hyphen and call every icon button unsized.
for m in re.finditer(r'className = "([^"]*)"', open(sys.argv[2], encoding="utf-8").read()):
    classes = set(m.group(1).split())
    if "btn" in classes and "btn-icon" not in classes and not (classes & SIZES):
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
#
# .btn-md is the interesting one. It used to be 0.85rem - 13.6px, which sat
# between the --text-sm (13px) and --text-md (14px) rungs with no rung to land
# on, so it was hand-typed and off-scale. It takes --text-sm, which makes it the
# same SIZE as .btn-sm; what still separates the three buttons is the height
# token, not the type size, and that is asserted above.
for t in xs sm md; do
  case $t in
    xs)       fs="var(--text-xs)" ;;
    sm|md)    fs="var(--text-sm)" ;;
  esac
  if [ "$(rule_body ".btn-$t")" = "height: var(--btn-height-$t); padding: 0 $( [ $t = xs ] && echo 8 || { [ $t = sm ] && echo 12 || echo 14; } )px; font-size: $fs;" ]; then
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
for legacy in '.tier-badge' '.tier-timer' '.menu-item-badge' \
              '.menu-item-badge.locked' '.menu-item-badge.unread'; do
  n=$(grep -cF "$legacy" "$STRIPPED_CSS" || true)
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
# The radius is now --radius-lg rather than the retired --radius-bubble; see
# test_design_tokens.sh section 10 for why, and for why the tail corner was NOT
# re-added when the sweep brief asked for one.
if [ "$(rule_body ".entry-bubble")" = "padding: 10px 14px; border-radius: var(--radius-lg);" ]; then
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
# The 10px gap is the 10px rung of the spacing scale now; the two-value padding
# shorthand keeps its literal because only single-value declarations were adopted.
for want in "display: flex" "align-items: center" "gap: var(--space-5)" "flex-shrink: 0"; do
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
#
# The seven are now ALIASES onto the global --text-* scale rather than a second
# ladder of literals, which is what let the rest of the UI drift. That means
# there are two separate failure modes here and they need two separate
# assertions: a step that has been DELETED, and a step that has drifted BACK to
# a bare rem. The first count used to be `--qac-text-[a-z]+:\s*[\d.]+rem`, which
# matched only the literal form - so aliasing the seven onto --text-*, the whole
# point of the migration, turned it red on a correct stylesheet. It now counts
# declarations of any shape, and the alias form is asserted separately below.
#
# Both helpers match the token name with `[a-z0-9]+`, not `[a-z]+`, and the
# reason is narrow: it is what makes the COUNT sensitive to a numeric suffix.
# Under `[a-z]+`, `--qac-text-sub2` does not match at all (the `2` is outside the
# class), so bolting an eighth step onto the seven would still report 7 and this
# section would stay green on a stylesheet carrying a step nobody declared on
# purpose. `[a-z0-9]+` matches it, the count comes back 8, and the assertion
# goes red. That is the whole of what the widening buys: a DIFFERING COUNT. It
# does NOT make a failure name the missed token - the message is "found N" and
# always has been. Same character class the alias TARGET already uses.
py_qac_scale_defs() { python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
print(len(re.findall(r"--qac-text-[a-z0-9]+\s*:\s*[^;}]+", css)))
PY2
}
if [ "$(py_qac_scale_defs)" -eq 7 ]; then
  ok "the card-local scale declares all 7 steps"
else
  bad "the card-local scale declares all 7 steps" "found $(py_qac_scale_defs)"
fi
# ...and all seven must read FROM the global scale. A literal rem here is the
# exact defect this section was written for: it still renders at the right size,
# so only the hierarchy is lost, and nothing else in the stylesheet can join a
# scale it has no name for.
#
# The helper counts as well as checks, because "every declaration is an alias" is
# trivially true of ZERO declarations: delete all seven and a shape-only helper
# finds nothing wrong and passes. The seven `.qac-X reads --qac-text-X`
# assertions do not catch that either - they read the call sites, which are
# untouched by a deletion. So the count lives here too, and an empty or short set
# is reported as a defect of its own rather than as an absence of defects.
#
# Mutation: delete all seven --qac-text-* declarations -> red.
py_qac_aliases() { python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
bad = []
found = re.findall(r"(--qac-text-[a-z0-9]+)\s*:\s*([^;}]+)", css)
if len(found) != 7:
    bad.append("expected 7 declarations, found %d" % len(found))
for name, value in found:
    if not re.fullmatch(r"var\(--text-[a-z0-9]+\)", value.strip()):
        bad.append(name + " = " + value.strip())
print(len(bad))
for b in bad:
    print("#   " + b)
PY2
}
# Split off the detail lines before the integer compare, the way every other
# count-plus-detail helper in this file does: passing the whole multi-line report
# to `-eq` prints an "integer expected" shell error next to the real failure.
report=$(py_qac_aliases)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "all 7 steps exist and are aliases onto the global --text-* scale"
else
  bad "all 7 steps exist and are aliases onto the global --text-* scale" "$report"
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
echo "=== 18. the pill is a SHAPE and a SIZE, not one welded class ==="
# The image editor's two buttons were the only control in this family that
# declared its own geometry: one class carried the height (34px), the padding,
# the roundness AND the font-size together, so it could not compose with .btn-sm
# or .btn-md, and it had to bring an off-scale type size along to do it. It is
# now two axes, the split .btn-icon-{20,24,28,30,32,34} plus .btn-icon-square
# already used:
#
#   size  -> .btn[data-size="pill"]   reads --btn-height-pill
#   shape -> .btn[data-shape="pill"]  reads --radius-full, and nothing else
#
# Two separate assertions carry that, because there are two separate ways to get
# it wrong: the shape body is pinned EXACTLY (so a size welded onto it is red)
# and the size body is pinned exactly AND asserted to set no radius at all (so a
# shape welded onto it is red). One of the two passing is not a split.
#
# Mutation: reintroduce `.btn-pill { ... }` -> red on the first assertion.
# Mutation: move `border-radius` off [data-shape="pill"] and back onto the size
#           rule -> red on BOTH bodies.
# Mutation: point the size rule at var(--btn-height-sm) -> red on its body.
# Mutation: drop data-size/data-shape from either HTML button -> red.
# Mutation: append an @media override of either axis -> red.
#
# The two bodies below are read through `py_axis_rules`, defined at the top of
# this file with `rule_body` for the reasons set out there.
if grep -qF '.btn-pill' "$CSS"; then
  bad ".btn-pill is gone: the shape is data-shape, the size is data-size" \
      "the welded class is back in the stylesheet - it is what section 18 exists to delete"
else
  ok ".btn-pill is gone: the shape is data-shape, the size is data-size"
fi

# Registered here because section 2's loop can only name a CLASS, and these two
# primitives are attribute selectors. They are as much the primitive registry as
# anything in that list is.
#
# Read through py_axis_rules, not rule_body: a media-scoped second declaration of
# either axis would be invisible to a first-match read, and the LAST body is the
# one that renders. The `<no rule>` sentinel is compared explicitly rather than
# tested for emptiness, because the helper prints that literal - a truthiness test
# would report a deleted rule as "present".
_size_line="$(py_axis_rules '.btn[data-size="pill"]')"
_shape_line="$(py_axis_rules '.btn[data-shape="pill"]')"
size_n="$(printf '%s' "$_size_line" | cut -d'|' -f2)"
size_body="$(printf '%s' "$_size_line" | cut -d'|' -f3)"
shape_n="$(printf '%s' "$_shape_line" | cut -d'|' -f2)"
shape_body="$(printf '%s' "$_shape_line" | cut -d'|' -f3)"
if [ "$size_body" != "<no rule>" ] && [ "$shape_body" != "<no rule>" ]; then
  ok "both axes exist as rules (.btn[data-size=pill], .btn[data-shape=pill])"
else
  bad "both axes exist as rules (.btn[data-size=pill], .btn[data-shape=pill])" \
      "size='$size_body' shape='$shape_body'"
fi
# Declared exactly once each, and asserted separately from the bodies above
# because the two failure modes are different: a wrong body is a wrong value,
# while a second declaration is a shadowed copy whose values the browser ignores
# and a later edit would change nothing in.
for axis in "$size_n:.btn[data-size=pill]" "$shape_n:.btn[data-shape=pill]"; do
  n="${axis%%:*}"; sel="${axis#*:}"
  if [ "$n" -eq 1 ]; then
    ok "$sel is declared exactly once"
  else
    bad "$sel is declared exactly once" \
        "$n declarations - the LAST one is what renders and the rest are dead code; look for an @media override"
  fi
done
if [ "$size_body" = "height: var(--btn-height-pill); padding: 0 14px; font-size: var(--text-sm);" ]; then
  ok ".btn[data-size=pill] is the whole size recipe, and reads the height token"
else
  bad ".btn[data-size=pill] is the whole size recipe, and reads the height token" \
      "got: $size_body - a shadowed second declaration, or a size naming its own height; the count assertion above says which"
fi
case "$size_body" in
  *border-radius*)
    bad "the size axis sets no radius" \
        "got: $size_body - that is the weld this section deleted, back on the other axis" ;;
  *)
    ok "the size axis sets no radius" ;;
esac
if [ "$shape_body" = "border-radius: var(--radius-full);" ]; then
  ok ".btn[data-shape=pill] is the roundness and nothing else"
else
  bad ".btn[data-shape=pill] is the roundness and nothing else" \
      "got: $shape_body - a shadowed second declaration, or a shape carrying a size too; the count assertion above says which"
fi

# The token has to exist AND be used. Existence alone was the brief's assertion
# and it is satisfied by a declaration nothing reads - which is exactly the Layer
# 0 defect the type scale was adopted to remove, where four of six --text-* rungs
# had no references at all. A named size with no caller is the same failure in
# miniature, so the reference is asserted and not inferred from the rule above.
#
# It also has to be declared EXACTLY ONCE. A custom property may be declared
# repeatedly and the LAST declaration wins, so a bare re.search scores whichever
# copy comes first - which is the one the cascade throws away. Appending
# `--btn-height-pill: 60px` after the real one rendered both image-editor buttons
# 60px tall and left this section 241/241 green. So the declarations are COLLECTED
# and anything but exactly one is reported as its own failure, rather than a count
# quietly picking the shadowed copy.
#
# Mutation: delete the --btn-height-pill declaration -> red.
# Mutation: change it to 32px -> red.
# Mutation: replace its one use with a literal 34px -> red (unused).
# Mutation: add a second --btn-height-pill declaration -> red, naming both.
py_btn_pill_height() { python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
# findall, not search: every declaration is collected, because the one that
# matters is the last and a single-match read cannot tell it from the first.
decls = [d.strip() for d in re.findall(r"--btn-height-pill\s*:\s*([^;}]+)", css)]
uses = len(re.findall(r"var\(\s*--btn-height-pill\s*\)", css))
if len(decls) == 1:
    value = decls[0]
elif not decls:
    value = "<absent>"
else:
    # Reported through the VALUE field rather than a separate channel, so the
    # existing `-eq`/`-ge` comparisons downstream keep receiving a well-formed
    # report: a bare `raise SystemExit` here would leave the use-count half of
    # the string unparseable and turn this into a shell error, not a diagnostic.
    value = "<%d declarations: %s - the LAST one is the one that renders>" % (
        len(decls), "; ".join(decls))
print("%s|%d" % (value, uses))
PY2
}
_pill="$(py_btn_pill_height)"
_pill_value="${_pill%%|*}"; _pill_uses="${_pill##*|}"
if [ "$_pill_value" = "34px" ]; then
  ok "--btn-height-pill is 34px (the height it replaced, unchanged)"
else
  bad "--btn-height-pill is 34px" "got '$_pill_value' - every pill-sized control moves with it"
fi
if [ "$_pill_uses" -ge 1 ] 2>/dev/null; then
  ok "--btn-height-pill is referenced ($_pill_uses use(s)), not just declared"
else
  bad "--btn-height-pill is referenced" \
      "$_pill_uses references - a named size nothing reads is a rung with no call site"
fi

# Both HTML call sites, by id. Counted, because the plan and the brief each said
# "one site" and there are TWO (the crop editor's Apply crop and the editor's
# Save) - so a count is what stops a third from appearing unnoticed, and naming
# them by id is what stops the assertion passing against the wrong element.
for pair in "applyCrop:Apply crop" "editorSave:Save"; do
  i="${pair%%:*}"; label="${pair#*:}"
  tag=$(grep -o "<button[^>]*id=\"$i\"[^>]*>" "$HTML" || true)
  if [ -z "$tag" ]; then
    bad "$label carries both axes" "no <button id=\"$i\"> in the markup"
    continue
  fi
  miss=""
  case "$tag" in *'data-shape="pill"'*) ;; *) miss="$miss data-shape" ;; esac
  case "$tag" in *'data-size="pill"'*)  ;; *) miss="$miss data-size"  ;; esac
  case "$tag" in *'btn-solid'*)          ;; *) miss="$miss btn-solid" ;; esac
  case "$tag" in *'btn-pill'*)           miss="$miss AND-STILL-BTN-PILL" ;; esac
  if [ -z "$miss" ]; then
    ok "$label carries both axes and keeps .btn-solid"
  else
    bad "$label carries both axes and keeps .btn-solid" "missing:$miss - $tag"
  fi
done
n=$(grep -o 'data-shape="pill"' "$HTML" | wc -l | tr -d ' ')
if [ "$n" -eq 2 ]; then
  ok "exactly 2 elements are pill-shaped (the two image-editor buttons)"
else
  bad "exactly 2 elements are pill-shaped" "found $n - a new call site needs both axes, not one"
fi

# --- the icon boxes stay the size they were chosen to be ---
# .btn-icon-{20,24,28,30,32,34} are six hit-target boxes and they are the one
# thing in this family NOT on a scale. They were considered for --space-*, whose
# rungs are 2/4/6/8/10/12/16/24px: the nearest ones are 10px and 16px, so binding
# a 20px button to --space-5 would halve it and a 32px one to --space-7 would
# halve that too. --space-8 is 24px exactly and would be pixel-identical, but it
# is a SPACING rung - retuning the gap scale would silently resize every icon
# button in the app - so the numbers stay literals.
#
# Which means nothing else guards them: test_scales.sh section 7 covers
# font-size, durations and border-radius, not width or height. So the values are
# pinned HERE instead, in the same spirit as that section's pinned --text-*
# values - a literal nothing watches is the one kind of number a retune can move
# by accident.
#
# Mutation: change any of the six to a neighbouring size -> red.
# Mutation: delete any of the six rules -> red.
# Mutation: declare any of the six TWICE -> red, on the duplicate itself.
py_icon_boxes() { python3 - "$CSS" <<'PY2'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
rules, dupes = {}, {}
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    key = frozenset(s.strip() for s in m.group(1).split(","))
    # Plain assignment, not setdefault: where two rules share a selector the LAST
    # one is the one that renders, so the table has to hold the last. setdefault
    # held the first - the shadowed copy - which is how a duplicate
    # `.btn-icon-20 { width: 40px }` scored a clean 20px here while the buttons
    # rendered 40x40. A duplicate is also reported in its own right: the shadowed
    # copy is dead code that a later edit would silently change nothing in.
    if key in rules:
        dupes.setdefault(key, 0)
        dupes[key] += 1
    rules[key] = " ".join(m.group(2).split())
bad = []
for n in (20, 24, 28, 30, 32, 34):
    sel = ".btn-icon-%d" % n
    key = frozenset([sel])
    got = rules.get(key, "")
    want = "width: %dpx; height: %dpx;" % (n, n)
    if got != want:
        bad.append("%s -> %s" % (sel, got or "<no rule>"))
    if key in dupes:
        bad.append("%s declared %d times - the last copy wins, the rest are dead code"
                   % (sel, dupes[key] + 1))
print(len(bad))
for b in bad:
    print("#   " + b)
PY2
}
_icon="$(py_icon_boxes)"
if [ "${_icon%%#*}" -eq 0 ]; then
  ok "the six icon hit-targets are still 20/24/28/30/32/34px (0 off-target)"
else
  bad "the six icon hit-targets are still 20/24/28/30/32/34px" "$_icon"
fi

# --- and the two font sizes the brief listed as defects are on the scale ---
# Both were listed off-scale (`0.85rem` on .btn-md, a raw 14px on .btn-icon) and
# both are already tokens by the time this task ran - the type-scale sweep
# adopted them. .btn-md's whole body is pinned by section 3b; .btn-icon's is not,
# and it is the one that governs every icon button's glyph, so it is pinned here
# rather than left to review.
#
# Third and last consumer of the same first-match read the two axis pins above
# had, so it goes through py_axis_rules too: `@media (max-width: 640px) {
# .btn-icon { font-size: 14px } }` would have been scored on the top-level body
# and passed.
#
# Mutation: put a bare `font-size: 14px` back on .btn-icon -> red.
# Mutation: append a media-scoped font-size override of .btn-icon -> red.
_icon_line="$(py_axis_rules '.btn-icon')"
_icon_n="$(printf '%s' "$_icon_line" | cut -d'|' -f2)"
_icon_body="$(printf '%s' "$_icon_line" | cut -d'|' -f3)"
if [ "$_icon_n" -eq 1 ]; then
  ok ".btn-icon is declared exactly once"
else
  bad ".btn-icon is declared exactly once" \
      "$_icon_n declarations - the LAST one is what renders and the rest are dead code; look for an @media override"
fi
_icon_font="$(printf '%s' "$_icon_body" | tr -s ' ' | grep -o 'font-size:[^;]*' | head -1)"
if [ "$_icon_font" = "font-size: var(--text-sm)" ]; then
  ok ".btn-icon reads the type scale (--text-sm), not a bare px"
else
  bad ".btn-icon reads the type scale (--text-sm)" "got '${_icon_font:-no font-size}'"
fi

echo
echo "=== 19. the shell primitives declare what they claim ==="
# Section 2 says these rules EXIST. It says nothing about what is in them, and
# nothing else in the repo can see inside them either: no component uses any of
# them yet (Tasks 6-12 write the markup), no screenshot test runs, and the DOM
# suites have nothing to select. So a body that is present but wrong is
# indistinguishable from a correct one until it is consumed - by which point it
# is load-bearing and the mistake is expensive.
#
# Hence a value pin per load-bearing rule, and every one of them through
# `py_axis_rules`, not `rule_body`. `rule_body` breaks on the FIRST match and
# CSS applies the LAST, which is the bug three guards in sections 18 and 19
# already had to be rewritten for; a second `.sheet { ... }` inside a media
# query would render and this section would score the copy that does not.
# Each pin therefore asks TWO questions - how many declarations, and which body
# is the one that applies - and a count of anything but 1 is its own failure
# rather than something to notice in the value.
#
# The COUNT half is doing more work here than the brief assumed, and it was found
# by mutation rather than by reading. Section 2's loop matches `.name` as a whole
# token ANYWHERE in the stylesheet, so for three of the twenty new names it never
# goes red when the base rule is deleted:
#
#   .sidebar-group-label   survives in the collapsed-state descendant selector
#                          (`.sidebar[data-collapsed="true"] .sidebar-group-label`)
#   .sidebar-menu-button   survives in its own `:hover`, `[aria-current="page"]`
#                          and `svg` selectors
#   .input-underline       survives in its own `::placeholder` and `:focus` rules
#
# The other seventeen go red on section 2 alone (verified, one rule deleted at a
# time - the same sweep section 2's own comment records as 36 red / 19 green).
# These three needed a check that asks a stricter question - is the name the
# SUBJECT of a rule, rather than a component somewhere inside one - which is what
# keying on the exact selector set does. So all twenty names are listed below,
# and every one of them is asserted here, whether or not its body is pinned.
# Section 2 remains the registry; this is the part of it that section 2's own
# regex cannot be.
#
# Mutation: point .sheet-overlay's background at var(--scrim-crop) -> red.
#   (that is not a colour: it is a box-shadow value, `background` cannot parse
#    it, so the whole declaration is dropped and the scrim renders transparent)
# Mutation: swap --z-modal and --z-top between .sheet-overlay and .sheet -> red.
# Mutation: change .sidebar[data-collapsed="true"] to a bare 56px -> red.
# Mutation: drop font-weight from [aria-current="page"] -> red.
# Mutation: delete .sidebar-group-label's rule -> red here (section 2 misses it).
# Mutation: delete .alert-dialog-actions' rule -> red on both.
# Mutation: declare any selector below twice -> red, on the count alone.
# Process substitution, not a pipe: `py_axis_rules ... | while ... done` runs
# the body in a SUBSHELL, so every ok/bad inside it would increment counters
# this shell never sees and the section would report 0/0 while printing
# failures.
while IFS='|' read -r sel n body; do
  case "$sel" in
    '.sheet-overlay')
      want="position: fixed; inset: 0; z-index: var(--z-modal); background: color-mix(in srgb, var(--scrim) 85%, transparent);" ;;
    '.sheet')
      want="position: fixed; top: 0; bottom: 0; left: 0; z-index: var(--z-top); display: flex; flex-direction: column; background: var(--muted); box-shadow: var(--shadow-lg); width: var(--sidebar-width); max-width: 84vw;" ;;
    '.sidebar')
      want="display: flex; flex-direction: column; gap: var(--space-2); width: var(--sidebar-width); flex-shrink: 0; position: relative; background: var(--muted); border-right: 1px solid var(--border); overflow: hidden; transition: width var(--duration-slow) var(--ease);" ;;
    '.sidebar[data-collapsed="true"]')
      want="width: var(--sidebar-rail-width);" ;;
    '.sidebar-menu-button[aria-current="page"]')
      want="background: var(--primary-subtle); color: var(--ring); font-weight: 600;" ;;
    '.content-frame-body')
      want="flex: 1; min-height: 0; overflow-y: auto;" ;;
    # Declared exactly once, body not pinned here.
    #
    # WHY the body is left open, stated narrowly enough to be true. Two other
    # sections cover PART of these bodies, and it is worth being exact about
    # which part, because an earlier version of this comment claimed they
    # covered all of it and they do not.
    #
    # test_scales.sh section 7 sweeps exactly THREE properties: font-size,
    # durations (transition, transition-duration, animation, animation-duration)
    # and border-radius. Seven of these bodies set a font-size and three set a
    # border-radius, so those values are constrained - to the scale, not to a
    # number. Section 7 says nothing about any other property.
    #
    # test_scales.sh section 6 proves a `var(--x)` names a token that EXISTS. It
    # does not constrain which token, nor the token's value.
    #
    # So the following are pinned by NOTHING in this repo, and a change to any of
    # them is green everywhere: letter-spacing (.sidebar-group-label), max-width
    # (.alert-dialog), every border WIDTH in `border`, `border-top` and
    # `border-bottom`, which rung of the space scale each padding/gap/margin
    # names, every width/height/min-width/min-height/max-width, font-weight,
    # and the non-numeric properties (display, flex, position, cursor, overflow,
    # pointer-events, text-align, text-transform, white-space). Demonstrated by
    # mutation: letter-spacing 0.06em -> 0.4em, max-width 420px -> 200px and
    # border-top 1px -> 5px together leave test_primitives at 299/0,
    # test_scales at 45/0 and test_design_tokens at 148/0.
    #
    # That gap is accepted, and pinning a thirteen-declaration body here to
    # close it would only be a second copy to maintain - and a second copy is a
    # second thing to forget. The COUNT is the half nothing else sees: a second
    # `.alert-dialog` renders and takes precedence, and no other section would
    # say so.
    '.sidebar-menu-button'|'.input-underline'|'.alert-dialog'|'.sidebar-rail'|\
    '.sidebar-header'|'.sidebar-content'|'.sidebar-group'|'.sidebar-group-label'|\
    '.sidebar-menu'|'.sidebar-footer'|'.sidebar-trigger'|'.content-frame'|\
    '.content-frame-header'|'.alert-dialog-title'|'.alert-dialog-description'|\
    '.alert-dialog-actions')
      want="" ;;
    *)
      bad "$sel is a selector this section pins" \
          "py_axis_rules returned a name with no expected body - add one or drop the selector"
      continue ;;
  esac
  if [ "$n" -ne 1 ]; then
    bad "$sel is declared exactly once" \
        "$n declarations - the LAST one is what renders and the rest are dead code; look for an @media override"
    continue
  fi
  # An empty `want` is the count-only case explained above.
  if [ -z "$want" ]; then
    ok "$sel is declared exactly once (body covered by the scale sections)"
  elif [ "$body" = "$want" ]; then
    ok "$sel states its whole recipe, and reads the tokens"
  else
    bad "$sel states its whole recipe, and reads the tokens" "got: $body"
  fi
done < <(py_axis_rules '.sidebar' '.sidebar-rail' '.sidebar-header' \
                      '.sidebar-content' '.sidebar-group' '.sidebar-group-label' \
                      '.sidebar-menu' '.sidebar-menu-button' '.sidebar-footer' \
                      '.sidebar-trigger' '.sidebar[data-collapsed="true"]' \
                      '.sidebar-menu-button[aria-current="page"]' \
                      '.sheet' '.sheet-overlay' '.input-underline' '.content-frame' \
                      '.content-frame-header' '.content-frame-body' '.alert-dialog' \
                      '.alert-dialog-title' '.alert-dialog-description' \
                      '.alert-dialog-actions')

# A pin about a RELATION rather than a body, because the relation is what breaks
# and neither rule's text says anything about it.
#
# The scrim has to sit UNDER the sheet. Both take their rung from the --z-*
# scale, and test_scales.sh section 2 already pins the ten values, so what is
# left is that these two rules picked rungs whose ORDER puts the sheet on top.
# Swapping them leaves a fully visible sheet behind an all-but-invisible scrim:
# the sheet is opaque and the scrim is a tint, so the only thing that changes is
# how much the page behind it dims - the kind of difference that gets reported
# as "the backdrop feels light" and never traced.
_scrim_z=""; _sheet_z=""
while IFS='|' read -r sel n body; do
  z="$(printf '%s' "$body" | grep -o 'z-index:[^;]*' | head -1)"
  case "$sel" in
    '.sheet-overlay') _scrim_z="$z" ;;
    '.sheet')         _sheet_z="$z" ;;
  esac
done < <(py_axis_rules '.sheet-overlay' '.sheet')
if [ "$_scrim_z" = "z-index: var(--z-modal)" ] \
   && [ "$_sheet_z" = "z-index: var(--z-top)" ]; then
  # Resolved against the token VALUES, not by trusting the alphabetical order of
  # two strings, so the assertion is about the numbers the cascade will use.
  _z_modal=$(grep -oE '^[[:space:]]*--z-modal:[[:space:]]*[0-9]+' "$CSS" | grep -oE '[0-9]+')
  _z_top=$(grep -oE '^[[:space:]]*--z-top:[[:space:]]*[0-9]+' "$CSS" | grep -oE '[0-9]+')
  if [ -n "$_z_modal" ] && [ -n "$_z_top" ] && [ "$_z_modal" -lt "$_z_top" ]; then
    ok "the sheet (--z-top) sits above its own scrim (--z-modal), by token value"
  else
    bad "the sheet sits above its own scrim" \
        "--z-modal=$_z_modal --z-top=$_z_top - the scale's ORDER is the load-bearing part"
  fi
else
  bad "the sheet and its scrim both take a rung from the --z-* scale" \
      "overlay='${_scrim_z:-<none>}' sheet='${_sheet_z:-<none>}'"
fi

# .input-underline's bottom rule is not decoration: it is the ONLY border the
# field has (`border: none` sits directly above it), and it is what the focus
# rule recolours. Section 14 resolves a border-colour-only rule by asking
# whether some rule gives that element a border to paint, and it answers yes
# only because this declaration is here - so deleting it is invisible until
# section 14 goes red, and this says so at the site instead.
while IFS='|' read -r sel n body; do
  case "$body" in
    *border-bottom:*) ok ".input-underline's border is the bottom rule alone" ;;
    *) bad ".input-underline's border is the bottom rule alone" \
            "got: $body - without a bottom rule the focus colour has nothing to paint" ;;
  esac
done < <(py_axis_rules '.input-underline')

echo
echo "=================================="
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
