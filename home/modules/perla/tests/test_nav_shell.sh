#!/usr/bin/env bash
# Wraps the two sidebar-shell JS harnesses. run.sh globs only test_*.sh, so the
# suites need a .sh sibling to be executed at all - the same arrangement
# test_code_copy.sh and test_question_cards.sh already use for their .js suites.
# Teaching run.sh a new extension would make the runner's contract worse for every
# other suite; a wrapper costs a few lines.
#
# THERE ARE TWO HARNESSES, AND THE SEAM IS DELIBERATE:
#
#   nav_dom_test.js         STRUCTURE and CASCADE. Questions you answer by
#                           READING the sources - does the element exist, what
#                           attributes does it carry, what does the cascade
#                           resolve to. It owns the HTML/CSS parser, which
#                           nav_focus_effect_test.js requires rather than
#                           duplicating.
#   nav_focus_effect_test.js BEHAVIOUR. Questions you can only answer by RUNNING
#                           the shipped overlay functions - where focus landed,
#                           which hidden flags flipped, did onClose fire.
#
# The split is not tidiness; it is the difference between the two classes of
# defect the review of Task 6 found. The focus bug (focus() landing on a
# display:none control) was invisible to every reading assertion, because a
# reading assertion cannot see it - jsdom sets activeElement regardless of
# visibility, so a jsdom smoke test agreed with all of them. And the four
# capabilities that decide whether a phone can open the sheet, focus it, close
# it and get its sidebar back were each green when deleted outright, because
# `popOverlay();` appears in three places and a name matching itself proves
# nothing about what it does.
#
# THE COMPLETION GATE IS A SENTINEL, NOT A SUMMARY. Each harness prints
# `DONE <name> <count>` as its final act, and this wrapper requires that line to
# be present AND the count to be the one expected for that harness. Everything
# that shaped this is in the two comments at the gate below; read them before
# changing it.
#
# Neither harness nor jsdom has a layout engine, so nothing here can observe
# pixel geometry or visual appearance - which is why the responsive assertions
# parse rule bodies out of a max-width: 640px block instead of measuring a
# rendered box. That is the same technique test_scales.sh section 4 uses for the
# header-height relationship.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
JS="$HERE/../perla-companion.js"

# harness file : harness name : expected assertion count
#
# The expected count is PER HARNESS and named, which is what the earlier shape
# could not be. A single total - floor plus exact - cannot say WHICH half is
# wrong, and its two numbers are not a coupled pair, so editing one without the
# other produces a false accusation. Two named numbers have no such coupling: each
# is updated in the same commit as the assertions IT gained or lost.
#
#   nav_dom_test          137  structure and cascade
#   nav_focus_effect_test  36  overlay-stack behaviour, the Chat route, and focus
#
# 127 -> 137 for the two centring bugs, which are the +10 below; nav_focus_effect_test
# is unchanged at 36 because the fix is entirely CSS and this harness reads no
# stylesheet.
# nav_dom_test gained 10, and NONE were removed - checked by diffing the assertion
# NAMES against the ux-fix-4 snapshot rather than by arithmetic, because "+10" is
# exactly the number that has been wrong before:
#   1 the shell publishing the content column's left edge as ONE custom property,
#     and that property being the grid's own first track;
#   2 #qaDrawer's box being bounded by that column - auto margins, the card's own
#     width cap, no transform of its own - and the property actually REACHING it
#     through the ancestor chain;
#   3 .toast-stack's box reading the same property, still clearing the header band,
#     and still self-centring, which is the transform the arithmetic depends on;
#   4 the card, the sheet and the stack sharing ONE centre at four expanded widths,
#     a half-sidebar RIGHT of the window's midpoint;
#   5 the same three coinciding with the window's midpoint when collapsed, with the
#     published inset zeroed and that zero checked by arithmetic, not read;
#   6 the same below 640px, at three phone widths;
#   7 the sheet still flush to the viewport's bottom with no `top`;
#   8 the sheet's flush edge carrying no border while its vertical edges do;
#   9 --z-toast still resolving below --z-header ON THE TWO ELEMENTS, which is the
#     half test_scales.sh section 2 cannot see;
#  10 .dropdown-panel's drop animation creating a containing block and
#     #quickActionsPanel declaring none of the six - the static fact behind a
#     KNOWN defect (#qaDrawer is measured from the panel for 200ms and from the
#     viewport for the rest), which is why the rule's comment has to stay true.
#
# Most of the ten are arithmetic or resolution rather than presence: each reads the
# value the cascade applies, and the expanded one compares the card's centre -
# computed from the grid's track plus the card's own `width`/`max-width` - against
# each surface's, computed from its own `left`. A broken evaluator therefore shows
# up as a disagreement rather than as a shared wrong number.
#
# ONE of the ten REWROTE an existing assertion's check while keeping its name, so
# the count cannot show it and only the diff can: the collapsed-grid check used to
# ask whether the collapsed rule mentions `var(--sidebar-width)` ANYWHERE in its
# body, which is a different question from "is the first track still the sidebar",
# and the rule now also publishes the inset. It reads `grid-template-columns` out of
# the body now. The radius VALUE on #qaDrawer is pinned by test_scales.sh section 7
# and is deliberately not asserted a second time here.
#
# 122 -> 127 and 30 -> 36 for the three UX bugs. nav_dom_test gained 5: the
# cascade RESOLVER (`.sidebar-trigger`'s effective display on a desktop, the same
# inside the 640px block, the `[hidden]` soundness condition that resolver's one
# skip depends on, `.app-card`'s resolved cross size being DEFINITE, and
# `<main class="page">` carrying tabindex="-1"). Each of the three resolves
# something the old assertions only read: the trigger's `display: none` existed
# and lost to `.btn-icon`, and the card's `max-width: 820px` existed and was
# never reached. The two assertions that were already true - that .content-wrap
# is a child of .app-card, and that the trigger declares display:none and is
# revealed inside the query - are kept and NOT duplicated: the first was never
# the bug (the tree was already correct), and the second cannot see the cascade.
# nav_focus_effect_test gained 6: releaseSidebarFocus compiling out of the
# shipped source, focus leaving the sidebar on collapse, it landing on the
# transcript, expanding leaving focus alone, focus outside the sidebar not being
# stolen, and the no-`<main>` fallback not being dead code.
#
# 112 -> 118 for the hover split, which is the +6 below; 86 -> 112 for the four UX
# fixes and 24 -> 30 for the same round's effect half. nav_dom_test gained 6 in
# this correction: the split's two ABSENCE checks (no unguarded `:hover`, no
# unguarded `:focus-within` slide-out) and the two arms' `:not(:has(…))` guards
# counted as one, the hit-area arithmetic (the flank beside each icon and the
# header band), the touch arm inside `@media (hover: none)`, and the rewritten
# chip-family count. The four UX-fix assertions it REPLACED are inside those
# numbers rather than added on top: `hover and :focus-within slide the full
# sidebar out`, `every ::after rule is scoped…`, `the chip appears on
# focus-visible and is suppressed on hover` and `the slide has ONE body` are all
# stronger questions about the same three rules, not four more questions about
# five.
#
# nav_focus_effect_test is UNCHANGED at 30: the split is entirely CSS and the
# JS single-writer, aria-expanded and overlay-stack assertions do not read the
# stylesheet.
#
# 86 -> 112 and 24 -> 30 for the four UX fixes. nav_dom_test gained 26: the card
# and its parent chain (4), the card's own recipe, its staticness and its refusal
# to take a background (3), the collapsed rail being out of the flow and the
# collapsed grid being one column (2), hover/:focus-within opening it plus the
# one-body and no-dimming claims (3), the reduced-motion arms (3), the sheet's
# slide-in and its keyframes (2), the six tooltip claims plus the collapse
# control's collapsed placement, the click-through header and the rail's z rung
# (7), and `.sidebar-rail`'s rule being struck (1). Plus the argv[2] check, which
# the wrapper adds by passing the script path and a bare `node nav_dom_test.js`
# does not run - so 112 here and 111 by hand, and that difference is the count
# gate doing its job rather than a mistake.
# nav_focus_effect_test gained 6: both flags in both states, the toggle in both
# directions, the single-writer count, and the overlay-stack decision.
#
# 137 -> 140 and 36 -> 41 for ux-fix-5, and BOTH halves gained rather than one
# gaining and the other losing. Verified by diffing assertion NAMES against the
# ux-fix-4 snapshot, not by arithmetic.
#
# nav_dom_test gained 5 and lost 2, for a net 3:
#   lost - "#statusIndicator is inside .sidebar-footer" and "...keeps class=..."
#     (the element was removed at the user's request, so these asserted a rule
#     for an element that does not exist);
#   lost - the collapsed-rail hiding of ".status-indicator" (same reason);
#   added - the status row's elements are gone from the markup, as an ABSENCE,
#     because the risk inverted when it was removed: a writer left behind a
#     removed element throws, and an element left behind a removed writer renders
#     nothing;
#   added - the group labels stay VISIBLE when collapsed, shortened with
#     font-size: 0 rather than hidden, and their short form is generated from
#     attr(data-short) (Item 2 - the previous assertion here checked the exact
#     opposite and would have gone GREEN on the regression the user reported);
#   added - every group label's data-short is a prefix of its own text, and the
#     open column restores the label's type and stops generating the short form;
#   added - the chip is retired by `content: none` declared AFTER its recipe on
#     the same selector, and that selector is the family's only writer of
#     `content` (Item 3 - the chip's rules are all retained, so "retained" needed
#     a check of its own or the retirement was unfalsifiable);
#   added - the hover lock has exactly one pointerleave subscription to a named
#     clearHoverLock, and exactly one writer and one deleter (Item 4);
#   added - no UNGUARDED slide-out exists anywhere else. This clause was LOST in
#     this round and mutation s41 found it: ux-fix-2's assertion of that name
#     bundled two claims, the row carve-out and the absence of a second
#     slide-out rule, and rewriting it for the chip's retirement kept the first
#     and dropped the second. The two live arms are pinned BY SELECTOR, so an
#     appended plain `.sidebar[data-collapsed="true"]:hover { width: ... }`
#     slides past every pin in this file and reopens Item 4's bug under a
#     different selector. Scoped to `.sidebar`-level arms, with the two pinned
#     arms and the FOCUS arm exempt - the focus arm carries no hover lock on
#     purpose, because the lock means "the pointer is on the rail".
# REWRITTEN, keeping its name where the question survived and changing the
# expected answer because the answer changed: "the rail expands on hover anywhere"
# (was: no unguarded :hover, and both arms guarded by :not(:has(<a row>)) - now
# the exact inverse, because the chip those guards existed for is gone); the chip
# family count (five SELECTORS, and the comment says so, because the retirement
# added a sixth DECLARATION under the base selector and a count of selectors
# cannot see it); the chip suppression (arms are now required to be the LIVE
# open-state selectors rather than the frozen old compounds, so a restored chip
# is still suppressed); and M6's specificity pins, (0,6,1) -> (0,5,1) with the
# focus arm now legitimately tying at (0,4,1) because there is no row carve-out
# left for it to resolve.
#
# Item 5 ("the icons jump a lot when the sidebar is hovered") gained 3, and they
# are three different questions rather than three spellings of one:
#   - while collapsed, all THREE regions declare a width, once each;
#   - that width IS the panel's own content box at rest, computed from both sides
#     (256 - 1px border - 200px padding, and 56 - 1px border), so it is an
#     identity rather than a second number to keep in step;
#   - the icon's centre computed from the REGION's own declared width, through the
#     same centring model as the two assertions above, is the rail's midpoint.
# The third is the one that can fail for a reason that is not a spelling, and the
# counterfactual is recorded at it: the same model fed the open end of the slide
# reports 127.5px, which is exactly where the icons used to fly from (measured in
# Firefox 156: 127.5 -> 27.5 on the way out, and the collapse control 235 -> 27.5).
# STRENGTHENED, not added: the open-column restore table now requires `width: auto`
# on the header and footer and adds a `.sidebar-content` row for it, because the
# pin's failure mode is one-sided - without the restore the rail is still a rail and
# every centring assertion here passes while the open column's regions stay 55px
# wide inside a 256px panel.
#
# nav_focus_effect_test gained 5, all in one new block:
#   - collapsing with the pointer ON the rail arms data-hover-suppressed;
#   - collapsing with the pointer ELSEWHERE does not arm it, and still releases
#     focus, so the keyboard path is unaffected and cannot strand a flag;
#   - clearHoverLock compiles out of the shipped source (a scan floor, placed
#     before the assertions that need it rather than after, so a missing function
#     is a diagnosis and not a cascade of downstream reds);
#   - clearing on pointerleave, and the next collapse re-arming it;
#   - expanding neither arms nor clears the flag, deliberately.
# The parser grew `hoverState`, `matches()`, a real listener registry and
# `__fire()` to support them - all four documented at their definitions, and the
# registry is a real one because an assertion that passes with the shipped
# listener never bound is not an assertion.
# REWRITTEN, keeping its name: the overlay-stack decision's "no pointer hook" half
# was a regex over EVENT NAMES, which is a proxy for the real question, and
# Item 4's pointerleave listener - which has nothing to do with the stack - made
# it red. It now asks the real thing of each pointer subscription: does the
# handler's own BODY name pushOverlay/popOverlay/closeTopOverlay? A handler that
# cannot name them cannot touch the stack, whatever event it listens for.
HARNESSES=(
  "nav_dom_test.js:nav_dom_test:144"
  "nav_focus_effect_test.js:nav_focus_effect_test:41"
)

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

[ -f "$JS" ] || { echo "  FAIL  script exists" "not found: $JS"; exit 1; }
for spec in "${HARNESSES[@]}"; do
  [ -f "$HERE/${spec%%:*}" ] || { echo "  FAIL  ${spec%%:*} exists" "not found: $HERE/${spec%%:*}"; exit 1; }
done

if ! command -v node >/dev/null 2>&1; then
  # A missing runtime is a FAILURE, not a skip. These suites are the only guard on
  # the sidebar shell's structure AND its overlay behaviour, and suites that quietly
  # did not run read exactly like coverage that happened - which is the mistake
  # run.sh already warns about for an empty glob.
  echo "  FAIL  node is available to run the DOM suites" "node not found in PATH"
  exit 1
fi

for spec in "${HARNESSES[@]}"; do
  IFS=: read -r h name want <<< "$spec"
  dom_out="$(node "$HERE/$h" "$JS" 2>&1)"; dom_status=$?
  printf '\n--- %s ---\n' "$h"
  printf '%s\n' "$dom_out"
  local_fail=0
  while IFS= read -r line; do
    case "$line" in
      "  PASS  "*) ok "${line#  PASS  }" ;;
      "  FAIL  "*) bad "${line#  FAIL  }" "see the harness output above"; local_fail=1 ;;
    esac
  done <<< "$dom_out"

  # The completion gate, in two halves, because neither alone works.
  #
  # HALF 1 - the DONE line must exist. It is the last thing each harness prints,
  # after every assertion, so nothing but reaching the end can produce it.
  #
  # Why a summary line is not enough, and this is the whole reason for the
  # sentinel rather than a tidy-up: `process.exit()` inside a REQUIRED module
  # kills the requiring module too. So delete `if (require.main !== module)
  # return;` from nav_dom_test.js and the effect harness dies inside its own
  # `require` - after the structure half has printed all 74 of its PASS lines, so
  # every count check based on printed lines is satisfied, both processes exit 0,
  # and NO FAIL line appears anywhere. Verified by mutation: the whole suite stayed
  # green with 13 assertions silently never run. The at-least floor could not see
  # it (the 74 lines are real, just printed by the wrong process), and the exact
  # count could not either, for the same reason.
  #
  # The same shape as a crash AFTER the last assertion: every PASS line is already
  # out, the summary is out, only the sentinel is missing. That is why a crash is
  # only detectable this way and not by ordering.
  #
  # HALF 2 - the count of assertions RUN must be the expected one. A harness can
  # reach its end having run the WRONG NUMBER: a lost one, or - the duplication
  # case - one that ran twice because the split seam lost its require.main guard.
  # Both are invisible to a floor, and both are invisible to a total for the same
  # reason. Per-harness, the message names the half: "nav_focus_effect_test
  # reported 74, expected 24" is legible in a way "the harnesses reported 148,
  # expected 110" never was.
  #
  # WHY THE COUNT IS `pass + fail` AND NOT `pass`, which is what it used to be.
  # That printed the number of assertions that PASSED, which made this gate answer
  # two questions with one number and misdiagnose the common case: a single
  # genuinely failing assertion dropped the count, so this reported "a lost
  # assertion, or a DOUBLE-RUN one" - naming two causes when the cause was neither.
  # The real failure had already been counted as a FAIL one line earlier, and the
  # run was correctly red; the count gate then re-reported a known failure as a
  # bookkeeping discrepancy, which is how a real defect gets filed as noise.
  #
  # `pass + fail` is what the gate is actually asking - how many assertions did
  # this harness RUN - and it is invariant under a legitimate failure, so nothing
  # is given up to buy a cleaner diagnosis. Both defects this half exists for are
  # still caught, because a lost assertion is not run and a double-run one runs
  # twice, and neither changes with pass/fail split:
  #
  #   crash mid-harness       -> no DONE line at all          (half 1)
  #   stubbed to print nothing -> no DONE line at all          (half 1)
  #   require.main guard gone   -> no DONE line at all          (half 1; see below)
  #   one assertion DELETED     -> count short by one           (half 2)
  #   one assertion FAILS       -> FAIL line only; count UNCHANGED, so this gate
  #                                stays quiet and does not misattribute it
  #
# All five measured on the current tree; the transcript is in the report.
  #
  # Mutation: delete `if (require.main !== module) return;` -> red on half 1, not
  #            half 2. Re-measured, because this comment used to say half 2 and was
  #            wrong: with the guard gone, nav_dom_test's assertion half runs inside
  #            the REQUIRE, and its `process.exit()` then kills nav_focus_effect_test
  #            before that file prints its own DONE. So the double-run is caught by
  #            the MISSING SENTINEL, and nav_dom_test's own count is unchanged
  #            because its two runs print into the same captured output. Still red,
  #            still caught, caught by the half that actually applies.
  # Mutation: throw after the last assertion of nav_dom_test.js -> red on half 1.
  # Mutation: stub a harness to print nothing and exit 0 -> red on half 1.
  # Mutation: DELETE one assertion without updating the count -> red on half 2.
  # Mutation: make an assertion fail (e.g. delete `aria-current="page"` from the
  #            Chat row) -> red on its OWN FAIL line, and BOTH count gates stay
  #            green, which is the whole point of counting `pass + fail`.
  done_line="$(printf '%s\n' "$dom_out" | grep "^DONE $name " | tail -1)"
  if [ -n "$done_line" ]; then
    got="${done_line##* }"
    if [ "$got" -eq "$want" ] 2>/dev/null; then
      ok "$h reached its end and ran its full set of $want assertions"
    else
      bad "$h ran its full set of $want assertions" \
          "it ran $got and finished - a LOST assertion, or a DOUBLE-RUN one (a split seam that lost its require.main guard). Neither is an ordinary failing assertion: this counts assertions RUN, so a plain failure does not move it. Both defects leave the run green, which is why this is checked rather than assumed."
    fi
  else
    bad "$h reached its end" \
        "no 'DONE $name <count>' line: node exited $dom_status${local_fail:+ with failures}${local_fail:- with none printed} - it crashed, or its own summary is not proof. A sentinel is the only thing that cannot be printed without reaching the end."
  fi

  # The old crash gate, kept because the sentinel does not cover this case: a
  # harness that fails an assertion AND dies. Scoped to "printed no failures", or
  # it would double-count every real failure.
  if [ "$local_fail" -eq 0 ] && [ "$dom_status" -ne 0 ]; then
    echo "  FAIL  $h exited cleanly" \
        "node exited $dom_status having printed no failures - a crash before or between assertions, not a verdict on the markup"
    fail=$((fail + 1))
  fi
done

echo
echo "=================================="
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1