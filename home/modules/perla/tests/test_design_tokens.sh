#!/usr/bin/env bash
# Guards the shadcn-style semantic token layer in perla-companion.css.
#
# What this locks down:
#   1. Every token is named by ROLE (background/foreground, primary, muted-…),
#      not by appearance (--ink-faint). Appearance names leak meaning: "ink"
#      says what it looks like, not what it is for, and they cannot be
#      re-themed without renaming everything.
#   2. shadcn's pairing convention holds — a surface token X has an
#      X-foreground, because the text colour that sits on a surface is part of
#      the token, not a separate decision at each call site.
#   3. The PALETTE did not drift. This phase is a rename, not a restyle: the
#      brand colours must be the same values that were there before. A test that
#      didn't check this would happily let a hue shift through.
#   4. Borders and focus rings are set once, globally — shadcn's
#      `* { border-border; outline-ring/50 }` is the reason its UI looks
#      coherent, and Perla had zero :focus-visible rules.
#   5. Radii derive from a single --radius rather than being hardcoded per
#      component.
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

echo "=== 1. role-named tokens exist ==="
for t in background foreground card card-foreground popover popover-foreground \
         primary primary-foreground secondary secondary-foreground \
         muted muted-foreground accent accent-foreground destructive \
         destructive-foreground border input ring radius; do
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
echo "=== 3. the palette did NOT drift (this phase is a rename) ==="
# The values Perla shipped before the token layer existed. A rename must
# preserve them exactly; a hue shift here would be an unrequested restyle.
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
  n=$(grep -o "var(--$old)" "$CSS" "$JS" 2>/dev/null | wc -l)
  [ "$n" = 0 ] && ok "var(--$old) is gone" || bad "var(--$old) is gone" "$n reference(s) remain"
done
n=$(grep -oE "^\s*--(bg|rule|ink|brass|wax)[a-z-]*\s*:" "$CSS" | wc -l)
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
for step in sm md lg xl; do
  defines "radius-$step" && ok "--radius-$step exists" || bad "--radius-$step exists" "absent"
done

echo
echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
