#!/usr/bin/env bash
# Guards the design-token layer in perla-companion.css.
#
# Phase 1 (token layer) locks down:
#   1. Tokens are named by ROLE (background/foreground, primary, muted-…), not
#      by appearance (--ink-faint). Appearance names leak meaning: "ink" says
#      what a colour looks like, not what it is for.
#   2. shadcn's pairing convention — a surface token X has an X-foreground,
#      because the text colour on a surface belongs to the token, not to each
#      call site.
#   3. The PALETTE did not drift. That phase was a rename, not a restyle, so
#      the brand colours must still be the pre-token values. A test that
#      didn't check this would happily let a hue shift through.
#   4. Borders and focus are set once, globally.
#
# Phase 2 (scale adoption) locks down:
#   7. Corner radii come from the scale rather than 17 hardcoded px values.
#      Percentages are exempt: those are circles and pills, not corner sizes.
#   8. Transitions share one duration/easing token instead of ad-hoc 0.15s/0.2s.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CSS="$HERE/../perla-companion.css"
JS="$HERE/../perla-companion.js"

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

[ -f "$CSS" ] || { echo "  FAIL  stylesheet exists" "not found: $CSS"; exit 1; }
root=$(sed -n '/:root *{/,/^ *}/p' "$CSS")

defines() { grep -qE "^\s*--$1\s*:" <<<"$root"; }
value_of() { sed -n "s/^\s*--$1\s*:\s*\([^;]*\);.*/\1/p" <<<"$root" | head -1; }
# Collect the distinct values a CSS property still spells out by hand.
literals_of() {  # literals_of <property-regex> <predicate-python-expr-over-parts>
  python3 - "$CSS" "$1" "$2" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
prop, pred = sys.argv[2], sys.argv[3]
bad = set()
for m in re.finditer(prop + r"\s*:\s*([^;}]+)", css):
    parts = m.group(1).strip().split()
    if any(eval(pred, {"p": p}) for p in parts):
        bad.add(m.group(1).strip())
for b in sorted(bad):
    print(b)
PY
}

echo "=== 1. role-named tokens exist ==="
for t in background foreground card card-foreground popover popover-foreground \
         primary primary-foreground secondary secondary-foreground \
         muted muted-foreground accent accent-foreground destructive \
         destructive-foreground border input ring radius duration ease; do
  defines "$t" && ok "--$t is defined" || bad "--$t is defined" "absent from :root"
done

echo
echo "=== 2. shadcn's pairing convention: X implies X-foreground ==="
for pair in card popover primary secondary muted accent destructive; do
  if defines "$pair" && ! defines "$pair-foreground"; then
    bad "--$pair has a --$pair-foreground" "surface token with no foreground pair"
  else
    ok "--$pair has a --$pair-foreground"
  fi
done

echo
echo "=== 3. the palette did NOT drift (phase 1 was a rename) ==="
check_value() {
  local tok="$1" want="$2" got
  got="$(value_of "$tok")"
  [ "$got" = "$want" ] && ok "--$tok is still $want" \
    || bad "--$tok is still $want" "got '$got'"
}
check_value background        "#17131a"
check_value card              "#201a23"
check_value popover           "#29212c"
check_value border            "#453a49"
check_value input             "#322a36"
check_value foreground        "#e9dfc7"
check_value muted-foreground  "#a3906c"
check_value accent-foreground "#6e5f45"
check_value primary           "#c97b8d"
check_value ring              "#e4a2b2"

echo
echo "=== 4. no appearance-named tokens are left behind ==="
for old in bg bg-panel bg-panel-2 rule rule-faint ink ink-dim ink-faint \
           brass brass-bright brass-dim wax wax-bright; do
  n=$(grep -F -o "var(--$old)" "$CSS" "$JS" 2>/dev/null | wc -l)
  [ "$n" = 0 ] && ok "var(--$old) is gone" || bad "var(--$old) is gone" "$n reference(s) remain"
done
n=$(grep -cE "^\s*--(bg|rule|ink|brass|wax)[a-z-]*\s*:" "$CSS")
[ "$n" = 0 ] && ok "no appearance-named token definitions remain" \
  || bad "no appearance-named token definitions remain" "$n definition(s) remain"

echo
echo "=== 5. borders and focus are set globally, once ==="
grep -qE "^\s*\*\s*\{" "$CSS" && ok "a universal selector exists to carry the border default" \
  || bad "a universal selector exists to carry the border default" "no bare * rule"
grep -q "border-color: *var(--border)" "$CSS" && ok "borders default to --border" \
  || bad "borders default to --border" "no global border-color rule"
n=$(grep -c "focus-visible" "$CSS")
[ "$n" -gt 0 ] && ok "focus-visible is styled ($n rule(s))" \
  || bad "focus-visible is styled" "no :focus-visible rule anywhere"
# grep is line-based, so a focus-visible rule that spans lines (as any real one
# does) cannot be matched with a single-line regex. Check it structurally.
if python3 - "$CSS" <<'PY'
import re, sys
css = open(sys.argv[1]).read()
for m in re.finditer(r"([^{}]*):focus-visible[^{}]*\{([^{}]*)\}", css):
    if "var(--ring)" in m.group(2):
        sys.exit(0)
sys.exit(1)
PY
then ok "focus rings use --ring"
else bad "focus rings use --ring" "no :focus-visible rule referencing --ring"
fi

echo
echo "=== 6. radii derive from a single --radius ==="
r=$(value_of radius)
[ -n "$r" ] && ok "--radius is set ($r)" || bad "--radius is set" "no --radius token"
derived=$(grep -cE "calc\(var\(--radius\) \* *[0-9.]+\)" "$CSS")
[ "$derived" -ge 4 ] && ok "the radius scale derives from it ($derived derived step(s))" \
  || bad "the radius scale derives from it" "only $derived derived step(s), expected >= 4"
for step in sm md lg xl 2xl; do
  defines "radius-$step" && ok "--radius-$step exists" || bad "--radius-$step exists" "absent"
done

echo
echo "=== 7. radii are tokenised (circles and micro-elements excepted) ==="
# Two exemptions, both deliberate:
#   * a percentage radius is a circle or a pill, not a corner size;
#   * a value under 4px is a decorative micro-element (hamburger lines, the
#     voice-wave bars, the mic-stop square) rather than a container corner.
#     Snapping a 2px-tall bar to the 4.8px `sm` step would round it into a
#     semicircle, so those stay literal.
mapfile -t radius_literals < <(literals_of "border-radius" \
  'not p.endswith("%") and p != "0" and not p.startswith("var(--radius") and not re.fullmatch(r"[0-3]px", p)')
if [ "${#radius_literals[@]}" -eq 0 ]; then
  ok "every border-radius is on the scale, a percentage, or a micro-element"
else
  bad "every border-radius is on the scale, a percentage, or a micro-element" \
      "still literal: ${radius_literals[*]}"
fi

echo
echo "=== 8. the two dominant transition durations are tokenised ==="
# Only 0.15s (x35) and 0.2s (x30) are tokenised. They are 65 of 78 durations,
# so this captures the coherence win while changing no timing at all. The
# remaining oddballs (0.05/0.12/0.16/0.18/0.22/0.25/0.3s) are left alone:
# they appear in deliberate multi-speed animations, and re-timing an animation
# is a judgement call best made by someone who can watch it.
defines "duration" && ok "--duration is defined" || bad "--duration is defined" "absent"
defines "duration-slow" && ok "--duration-slow is defined" || bad "--duration-slow is defined" "absent"
defines "ease" && ok "--ease is defined" || bad "--ease is defined" "absent"
d=$(value_of duration);   [ "$d" = "0.15s" ] && ok "--duration is 0.15s (unchanged timing)" \
  || bad "--duration is 0.15s (unchanged timing)" "got '$d'"
ds=$(value_of duration-slow); [ "$ds" = "0.2s" ] && ok "--duration-slow is 0.2s (unchanged timing)" \
  || bad "--duration-slow is 0.2s (unchanged timing)" "got '$ds'"
n=$(grep -cE "transition:[^;}]*\b0\.15s" "$CSS")
[ "$n" = 0 ] && ok "no transition spells out 0.15s any more" \
  || bad "no transition spells out 0.15s any more" "$n left"
n=$(grep -cE "transition:[^;}]*\b0\.2s\b" "$CSS")
[ "$n" = 0 ] && ok "no transition spells out 0.2s any more" \
  || bad "no transition spells out 0.2s any more" "$n left"

echo
echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
