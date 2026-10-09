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
JS="$HERE/../perla-companion.js"
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
    if any(eval(pred, {"p": p, "re": re}) for p in parts):
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
# The invariant is DERIVATION, not a count. This used to be spelled ">= 4 calc
# steps", which pinned the SIZE of the scale rather than the property that
# matters, so it went red when --radius-sm/-2xl/-3xl were retired along with
# their last consumers - a retirement that was the point of the sweep, not a
# regression. What has to hold is that no radius step is an independent number:
# each one either derives from --radius or IS --radius.
derived=$(grep -cE "calc\(var\(--radius\) \* *[0-9.]+\)" "$CSS")
# ...with a floor, so it cannot pass vacuously on a single derived step.
[ "$derived" -ge 2 ] && ok "the radius scale derives from it ($derived derived step(s))" \
  || bad "the radius scale derives from it" "only $derived derived step(s), expected >= 2"
for step in md lg xl; do
  defines "radius-$step" && ok "--radius-$step exists" || bad "--radius-$step exists" "absent"
done
# A radius step carrying its own hard-coded length is the monocraft defect in
# token form, and it is invisible to the count above. `declared but not derived`
# is what it looks like.
#
# --radius-full is exempt, and necessarily so: it is the "round" role, and 9999px
# is what makes a circle or a pill. Deriving it from --radius would redefine
# "round" as "a very round 8px corner" and quietly un-circle every avatar,
# pill and icon button in the file. It is a terminal value by definition.
hardcoded=$(sed -n '/:root *{/,/^ *}/p' "$CSS" \
  | grep -E "^\s*--radius-[a-z0-9]+\s*:" \
  | grep -vE "calc\(var\(--radius\)|var\(--radius\)|^\s*--radius-full\s*:" || true)
if [ -z "$hardcoded" ]; then
  ok "every radius step derives from --radius rather than spelling a length"
else
  bad "every radius step derives from --radius" "$(echo "$hardcoded" | tr '\n' ' ')"
fi

echo
echo "=== 7. radii are tokenised (circles and micro-elements excepted) ==="
# Two exemptions, both deliberate:
#   * a percentage radius is a circle or a pill, not a corner size;
#   * `var(--space-1)` is the micro-element exemption, and it is NOT a radius
#     step and must not quietly become one. This used to be three bare 3px/2px/
#     1px cases and the exemption was a `[0-3]px` pattern; binding them to
#     --space-1 (2px) instead renders identically - CSS scales corner radii
#     down to fit the side, so 1px and 2px are the same fully-rounded end on a
#     1.5px bar - while keeping the reason they are exempt legible.
#     --radius-sm (4.8px) is what would round them into pebbles and semicircles.
#     See the why-comments at .voice-wave i and .mic-stop-square.
#
#     TWO, not three: the hamburger's bars used to be a third case, and went with
#     #menuBtn when the sidebar shell replaced it - the trigger is an SVG now, so
#     the micro-element exemption has two users rather than three.
mapfile -t radius_literals < <(literals_of "border-radius" \
  'not p.endswith("%") and p != "0" and not p.startswith("var(--radius") and p != "var(--space-1)"')
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
echo "=== 9. the chat surface is flat: no gradients, alpha or elevation ==="
# Scope is deliberately narrow. A naive selector matching 'entry|bubble|composer'
# also catches .qa-drawer-* (the question cards) and .elevate-composer-icon,
# which are OTHER surfaces — including them produced two wrong counts in the
# design spec's own self-review. Keep this exclusion list in sync with the spec.
chat_scope() {
  python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
CHAT = re.compile(r"entry|bubble|composer|#textInput|send-btn|mic-btn")
# Other surfaces, excluded on purpose.
OUT = re.compile(r"qa-drawer|qa-btn|elevate-composer-icon|\.prose\b")
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    sel = " ".join(m.group(1).split())
    if not CHAT.search(sel) or OUT.search(sel):
        continue
    print(sel + "\t" + " ".join(m.group(2).split()))
PY
}
mapfile -t chat_rules < <(chat_scope)

scan() {  # scan <pattern> <human name>
  local pat="$1" name="$2" hits=0
  for r in "${chat_rules[@]}"; do
    if grep -qE "$pat" <<<"$r"; then hits=$((hits + 1)); fi
  done
  [ "$hits" = 0 ] && ok "no $name in the chat surface" \
    || bad "no $name in the chat surface" "$hits rule(s) still have it"
}
scan '(linear|radial)-gradient' "gradient"
scan 'rgba?\(|hsla?\(' "raw colour literal"
scan 'box-shadow' "box-shadow"
echo "        (scanned ${#chat_rules[@]} chat rules)"

defines "primary-subtle" && ok "--primary-subtle is defined" || bad "--primary-subtle is defined" "absent"
subtle=$(value_of primary-subtle)
case "$subtle" in
  *"var(--primary)"*) ok "--primary-subtle derives from --primary ($subtle)" ;;
  *) bad "--primary-subtle derives from --primary" "got '$subtle' — it must not be an independent colour" ;;
esac
defines "primary-hover" && ok "--primary-hover is defined" || bad "--primary-hover is defined" "absent"

echo
echo "=== 10. bubbles are rounded, and the user's bubble is readable ==="
# The tail corner is GONE: the user asked for the rounded, solid-fill treatment of
# the reference screenshot. Section 7's radius rule is what stops a bare pixel
# value from creeping back in, so the value here has to be the token.
#
# Two later changes, both deliberate, and both narrower than they look:
#
#   * The token moved from --radius-bubble to --radius-lg. --radius-bubble was a
#     symmetric 20px, which is a LOT of corner on a short reply - "ok" in a 20px
#     bubble reads as a visibly lopsided rounded rect, because 20px of radius is
#     most of the bubble's height. --radius-lg (8px) fixes that and is the same
#     rung every other control & surface in the file uses.
#   * A task brief also proposed adding a cut-back tail corner to
#     .entry-user .entry-bubble, on top of the radius change. That was NOT done:
#     the "tail corner is GONE" decision above is a user decision, recorded here
#     precisely so it would survive being re-derived, and re-introducing it
#     because a plan mentioned it would quietly undo it. The radius change is
#     independent of the tail and stands on its own.
bubble_decl() {  # bubble_decl "<selector>" "<property>"  -> value, or "" if absent
  python3 - "$CSS" "$1" "$2" <<'PY'
import re, sys
# argv: [ "-", CSS, selector, property ]
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
sel, prop = sys.argv[2], sys.argv[3]
m = re.search(re.escape(sel) + r"\s*\{([^}]*)\}", css)
d = re.search(re.escape(prop) + r":\s*([^;]+)", m.group(1)) if m else None
print(d.group(1).strip() if d else "")
PY
}
bubble_radius() { bubble_decl "$1" "border-radius"; }
# All four corners equal AND the value is the token. Checking only "not
# asymmetric" would happily pass a square 4px box, so both are tested.
is_rounded() {  # is_rounded "<radius>"
  [ "$1" = "var(--radius-lg)" ] || return 1
  local parts=($1) p
  local first="${parts[0]}"
  for p in "${parts[@]}"; do [ "$p" != "$first" ] && return 1; done
  return 0
}
# Asserts the EFFECTIVE radius: the variant's own declaration if it has one,
# otherwise the base it inherits. Checking only the variant would have failed
# when the three duplicated `border-radius` declarations collapsed into one.
# The base is what every variant now leans on, so it is asserted directly.
_base_r="$(bubble_radius ".entry-bubble")"
if is_rounded "$_base_r"; then
  ok "the bubble base states the radius once for every variant ($_base_r)"
else
  bad "the bubble base states the radius once" \
      "got '$_base_r' - the variants no longer declare their own, so bubbles would be square"
fi
# And no variant may go back to repeating it: that duplication is what hid the
# failed-entry border bug (three rules set border-style:none while a fourth set
# only a border-COLOUR, which cannot render without a style).
_dup=0
for _sel in ".entry-perla .entry-bubble" ".entry-user .entry-bubble"; do
  [ -n "$(bubble_radius "$_sel")" ] && _dup=$((_dup + 1))
done
if [ "$_dup" -eq 0 ]; then
  ok "no bubble variant re-declares the radius (the duplication stays collapsed)"
else
  bad "no bubble variant re-declares the radius" "$_dup of 2 do again"
fi
for spec in ".entry-perla .entry-bubble:Perla's" \
            ".entry-user .entry-bubble:the user's" \
            ".entry-question .entry-bubble:the question card" \
            ".entry-failed .entry-bubble:the failed"; do
  sel="${spec%:*}"; who="${spec##*:} bubble"
  r=$(bubble_radius "$sel")
  [ -n "$r" ] || r=$(bubble_radius ".entry-bubble")
  if is_rounded "$r"; then
    ok "$who is fully rounded ($r)"
  else
    bad "$who is fully rounded" "got '$r' — expected var(--radius-lg) with all corners equal"
  fi
done
# The typing indicator is the same shape of thing; a square one right above a
# row of rounded bubbles is the kind of inconsistency nobody notices until it is
# pointed out.
r=$(bubble_radius ".thinking")
is_rounded "$r" && ok "the typing indicator is rounded too ($r)" \
  || bad "the typing indicator is rounded too" "got '$r'"

# GEOMETRY, NOT JUST THE VALUE. A previous version of this section asserted
# `var(--radius-pill)` and passed while the UI was visibly broken: at 9999px the
# browser clamps the radius to height/2, so on a tall bubble the left and right
# edges bow inward far enough that the first and last lines of text render
# OFF the fill, on the page background. A value assertion cannot see that. This
# models the clamp and fails if the arc eats into the first line.
#
# For a box of height H and a single radius R (clamped to H/2), the corner arc
# at horizontal distance d from the left edge starts R - sqrt(R^2 - (R-d)^2)
# below the top edge. Measured against that:
#     r=9999  ->  40px intrusion at h=176  (the shipped bug)
#     r=8     ->   2.7px intrusion at any height  (--radius-lg today)
# A fixed radius is height-independent, which is exactly why it is safe. The
# threshold is 3px: a sub-pixel-to-few-pixel bite at the very corner of the
# padding box is invisible, and tightening it further only rejects radii that
# render correctly.
#
# The radius is RESOLVED THROUGH THE TOKEN CHAIN rather than read as a literal,
# because there is no literal to read any more: .entry-bubble says
# var(--radius-lg), which is var(--radius), which is 0.5rem. Reading the token
# name out of :root the way this used to read --radius-bubble would have gone
# quiet the moment the middle step was renamed, which is the failure mode this
# whole section exists to prevent.
# .entry-bubble's padding is the two-value shorthand `10px 14px`, and both values
# are still literals: the spacing sweep deliberately adopted only single-value
# padding/margin/gap declarations, so the horizontal stays 14px. test_primitives.sh
# section 13 asserts that exact string.
pad=14          # .entry-bubble horizontal padding
line=26         # height of the first text line, generously
tolerance=3     # px of arc intrusion tolerated at the corner
radius=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
m = re.search(r":root\s*\{", css); d, i = 1, m.end()
while d:
    d += (css[i] == "{") - (css[i] == "}"); i += 1
decls = dict(re.findall(r"(--[a-z0-9-]+)\s*:\s*([^;}]+)", css[:i]))
def resolve(tok, depth=0):
    """Follow var() and calc() references until a length is reached, in px."""
    v = decls.get(tok, "").strip()
    if not v or depth > 8:
        return None
    ref = re.fullmatch(r"var\(\s*(--[a-z0-9-]+)\s*\)", v)
    if ref:
        return resolve(ref.group(1), depth + 1)
    mult = re.fullmatch(r"calc\(\s*var\(--radius\)\s*\*\s*([0-9.]+)\s*\)", v)
    if mult:
        base = resolve("--radius", depth + 1)
        return base * float(mult.group(1)) if base else None
    for unit, factor in (("rem", 16.0), ("px", 1.0)):
        num = re.fullmatch(r"([0-9.]+)" + unit, v)
        if num:
            return float(num.group(1)) * factor
    return None
r = resolve("--radius-lg")
print(f"{r:g}" if r else "")
PY
)
if [ -z "$radius" ]; then
  bad "--radius-lg resolves to a fixed px value" \
      "could not resolve --radius-lg through :root to a length - the bubble radius is unpinned"
else
  for H in 45 90 176; do
    intrusion=$(python3 -c "
import math
R = min($radius, $H / 2); d = $pad
print(max(0.0, R - math.sqrt(max(R * R - (R - d) ** 2, 0))))")
    if [ "$(python3 -c "print(1 if $intrusion <= $tolerance else 0)")" = 1 ]; then
      ok "radius ${radius}px keeps the first line on the fill at h=${H}px (arc intrudes ${intrusion}px, tolerance ${tolerance}px)"
    else
      bad "radius keeps the first line on the fill at h=${H}px" \
          "the arc intrudes ${intrusion}px — past the ${tolerance}px tolerance, so the first line would render off the bubble"
    fi
  done
  # The real regression guard: a pill-sized radius must be rejected outright,
  # because its intrusion grows with height rather than staying fixed.
  if [ "$(python3 -c "print(1 if $radius < 100 else 0)")" = 1 ]; then
    ok "radius is bounded (${radius}px), so intrusion does not scale with bubble height"
  else
    bad "radius is bounded" "${radius}px clamps to height/2 — a tall bubble's first and last lines fall off the fill"
  fi
fi

# Solid fill means no border is left to hide behind.
# No .entry-system here any more: nothing builds that class, so the lookup
# returned "" and took the empty-string branch below - a pass that asserted
# nothing at all. Empty IS still fine for these three, because the variants
# no longer declare `border: none`, they simply do not declare a border.
for spec in ".entry-perla .entry-bubble:Perla's" \
            ".entry-user .entry-bubble:the user's"; do
  sel="${spec%:*}"; who="${spec##*:} bubble"
  b=$(bubble_decl "$sel" "border")
  case "$b" in
    none|0|"") ok "$who has no border (it no longer needs one)" \
            || bad "$who has no border" "got '$b'" ;;
    *)          bad "$who has no border" "got '$b'" ;;
  esac
done

fill=$(bubble_decl ".entry-user .entry-bubble" "background")
[ "$fill" = "var(--primary-solid)" ] && ok "the user's bubble uses the darkened --primary-solid fill" \
  || bad "the user's bubble uses the darkened --primary-solid fill" "got '$fill'" \
      "--primary itself is too light for white text (3.13:1) and is still the send button"

# CONTRAST REGRESSION. The sender bubble is a solid fill, so the cream
# --foreground that every other bubble uses is only 4.12:1 on it — under AA's
# 4.5 for body copy. --primary-foreground is white, at 5.46:1. If someone later
# 'tidies' this rule away, the text dims without anything looking broken.
ink=$(bubble_decl ".entry-user p" "color")
[ "$ink" = "var(--primary-foreground)" ] \
  && ok "text on the solid fill uses --primary-foreground = white (5.46:1)" \
  || bad "text on the solid fill uses --primary-foreground" "got '$ink'"

# The trap this assertion fell into first time: `.entry-user p` existed TWICE,
# the later one quietly setting --foreground. Checking only the first match
# passed while the cascade actually resolved to the unreadable colour. So assert
# that EVERY rule with this selector agrees, and that there is only one of them.
dupes=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
out = []
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    sel = " ".join(m.group(1).split())
    if sel != ".entry-user p":
        continue
    c = re.search(r"(?<!-)\bcolor:\s*([^;]+)", m.group(2))
    out.append(c.group(1).strip() if c else "(no color)")
print("|".join(out))
PY
)
count=$(tr '|' '\n' <<<"$dupes" | grep -c .)
if [ "$count" = 1 ] && [ "$dupes" = "var(--primary-foreground)" ]; then
  ok "exactly one .entry-user p rule, and it sets the readable ink (no cascade conflict)"
else
  bad "exactly one .entry-user p rule, and it sets the readable ink" \
      "found $count rule(s): $dupes — a later duplicate silently wins the cascade"
fi

# Inline code is the same trap one level down, and the direction flips with the
# text colour. The code text is now WHITE, so the plate must be DARKER than the
# bubble: mixing toward --foreground would leave it 1.1:1 against the fill and
# it would stop reading as a chip at all. This measures the composited result
# rather than trusting the token, and checks BOTH that white code text clears
# AA and that the plate stays visibly distinct from the bubble behind it.
contrast=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
tok = dict(re.findall(r"(--[a-z-]+):\s*([^;]+);", css.split("}")[0] + "}"))

def hx(h):
    h = h.strip().lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def chan(c):
    c /= 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
def lum(r):
    return 0.2126 * chan(r[0]) + 0.7152 * chan(r[1]) + 0.0722 * chan(r[2])
def ratio(a, b):
    l1, l2 = sorted([lum(a), lum(b)], reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)

def mix(toward, pct, base):
    """Resolve color-mix(in srgb, var(--toward) N%, <base>) over an opaque base."""
    t, b = hx(tok["--" + toward]), hx(base)
    return tuple(pct * t[i] + (1 - pct) * b[i] for i in range(3))

# The bubble fill itself, resolved through --primary-solid.
fill = mix("primary", float(re.search(r"var\(--primary\)\s+([0-9.]+)%",
      tok["--primary-solid"]).group(1)) / 100, tok["--background"])
white = (255, 255, 255)

# The code plate is alpha, so what the eye sees is it composited over the fill.
pct = float(re.search(r"var\(--background\)\s+([0-9.]+)%",
      tok["--primary-code-bg"]).group(1)) / 100
plate = mix("background", pct, "#" + "".join(f"{round(c):02x}" for c in fill))

# Two separate things can go wrong, and they pull in OPPOSITE directions, so both
# are measured:
#   * too light a plate -> white code text falls below AA
#   * too light a plate -> it also blends into the fill and stops reading as code
# Note the distinctness ratio only ever RISES as the plate darkens (1.14:1 at 10%,
# 2.64:1 at 75%), so an over-dark plate can never be caught by contrast - it just
# looks like a heavy chip. That is a taste call, not a defect, and 26% is the
# chosen value. The floor is the direction that actually fails.
print(f"{ratio(white, plate):.2f} {ratio(fill, plate):.2f}")
PY
)
code_cr=${contrast%% *}
plate_cr=${contrast##* }
if [ -n "$code_cr" ] && awk "BEGIN{exit !($code_cr >= 4.5)}"; then
  ok "inline code on the solid fill clears AA ($code_cr:1, needs 4.5)"
else
  bad "inline code on the solid fill clears AA" \
      "got '${code_cr:-unknown}:1' — with WHITE code text the plate must be darker than the bubble"
fi
if [ -n "$plate_cr" ] && awk "BEGIN{exit !($plate_cr >= 1.3)}"; then
  ok "the code plate stays visibly distinct from the bubble ($plate_cr:1, needs 1.3)"
else
  bad "the code plate stays visibly distinct from the bubble" \
      "got '${plate_cr:-unknown}:1' — too close to the fill, so it no longer reads as code"
fi

# The fill must be dark enough for white at all. Measured rather than asserted
# against a literal, so re-tinting --primary cannot silently break the sender
# text the way it did when the bubble was filled with raw --primary (3.13:1).
fill_cr=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
tok = dict(re.findall(r"(--[a-z-]+):\s*([^;]+);", css.split("}")[0] + "}"))
def hx(h):
    h = h.strip().lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def chan(c):
    c /= 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
def lum(r):
    return 0.2126 * chan(r[0]) + 0.7152 * chan(r[1]) + 0.0722 * chan(r[2])
pct = float(re.search(r"var\(--primary\)\s+([0-9.]+)%", tok["--primary-solid"]).group(1)) / 100
p, b = hx(tok["--primary"]), hx(tok["--background"])
fill = tuple(pct * p[i] + (1 - pct) * b[i] for i in range(3))
l1, l2 = sorted([lum(fill), lum((255, 255, 255))], reverse=True)
print(f"{(l1 + 0.05) / (l2 + 0.05):.2f}")
PY
)
if [ -n "$fill_cr" ] && awk "BEGIN{exit !($fill_cr >= 4.5)}"; then
  ok "the fill is dark enough for white text ($fill_cr:1, needs 4.5)"
else
  bad "the fill is dark enough for white text" \
      "got '${fill_cr:-unknown}:1' — lighten --primary-solid and the sender text drops below AA"
fi

# White must actually BE white, not a near-white that reads as cream elsewhere.
fg=$(value_of primary-foreground)
[ "$fg" = "#ffffff" ] && ok "--primary-foreground is pure white ($fg)" \
  || bad "--primary-foreground is pure white" "got '$fg'"

echo
echo "=== 11. the question/permission card surface is flat and tokenised ==="
# Same treatment section 9 gave the chat, applied to the card. This surface used
# to be built from ~24 inline style.* assignments in the JS with hand-mixed
# rgba(201,123,141,...) plum tints, so there was nothing here to assert until
# the styles were moved into real classes. That move is the point of this
# section: if it is ever undone, these fail again rather than silently
# regressing to inline styles.
card_scope() {
  python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
CARD = re.compile(r"entry-question|entry-permission|qac-")
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    sel = " ".join(m.group(1).split())
    if CARD.search(sel):
        print(sel + "\t" + " ".join(m.group(2).split()))
PY
}
mapfile -t card_rules < <(card_scope)
if [ "${#card_rules[@]}" -gt 0 ]; then
  ok "the card surface has real CSS rules (${#card_rules[@]} found, not inline styles)"
else
  bad "the card surface has real CSS rules" "no .entry-question/.entry-permission rules — styles are inline in the JS again"
fi
cscan() {  # cscan <pattern> <name>
  local pat="$1" name="$2" hits=0
  # Scanning zero rules would vacuously "pass". Report that as the failure it
  # is, so a surface that loses its stylesheet cannot look clean.
  if [ "${#card_rules[@]}" -eq 0 ]; then
    bad "no $name on the card surface" "no card rules exist to scan — vacuous pass"
    return
  fi
  for r in "${card_rules[@]}"; do
    grep -qE "$pat" <<<"$r" && hits=$((hits + 1))
  done
  [ "$hits" = 0 ] && ok "no $name on the card surface (scanned ${#card_rules[@]} rules)" \
    || bad "no $name on the card surface" "$hits rule(s) still have it"
}
cscan '(linear|radial)-gradient' "gradient"
cscan 'rgba?\(|hsla?\(' "raw colour literal"
cscan 'box-shadow' "box-shadow"
cscan 'style=' "inline style attribute"

# The selected state must change BOTH fill and border. Changing only the fill is
# what the old plum-tint buttons did, and at a 1.09:1 fill step it was invisible.
# --accent is only 1.09:1 from --card (and --muted is byte-identical to --card),
# so the stock neutral tokens cannot carry this; --card-selected is the token
# that does, and --primary on the border is what actually reads.
defines "card-selected" && ok "--card-selected is defined" || bad "--card-selected is defined" "absent"
sel_fill=$(value_of card-selected)
case "$sel_fill" in
  *"var(--primary)"*|*"var(--card)"*) ok "--card-selected derives from the palette ($sel_fill)" ;;
  *) bad "--card-selected derives from the palette" "got '$sel_fill'" ;;
esac
# The option descriptions sit on the selected fill too, so the tint has to stay
# light enough for --muted-foreground to clear AA. This is the constraint that
# stopped the fill matching the reference's 1.34:1 exactly.
desc_cr=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
tok = dict(re.findall(r"(--[a-z-]+):\s*([^;]+);", css.split("}")[0] + "}"))
def hx(h):
    h = h.strip().lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def chan(c):
    c /= 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
def lum(r):
    return 0.2126 * chan(r[0]) + 0.7152 * chan(r[1]) + 0.0722 * chan(r[2])
pct = float(re.search(r"var\(--primary\)\s+([0-9.]+)%", tok["--card-selected"]).group(1)) / 100
p, c = hx(tok["--primary"]), hx(tok["--card"])
fill = tuple(pct * p[i] + (1 - pct) * c[i] for i in range(3))
mf = hx(tok["--muted-foreground"])
l1, l2 = sorted([lum(fill), lum(mf)], reverse=True)
print(f"{(l1 + 0.05) / (l2 + 0.05):.2f}")
PY
)
if [ -n "$desc_cr" ] && awk "BEGIN{exit !($desc_cr >= 4.5)}"; then
  ok "option descriptions clear AA on the selected fill ($desc_cr:1, needs 4.5)"
else
  bad "option descriptions clear AA on the selected fill" \
      "got '${desc_cr:-unknown}:1' — a stronger tint than this is what breaks the description text"
fi

# The selected border must be a real step up from the resting border, since it
# is carrying the selection signal that the fill cannot.
brd_cr=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
tok = dict(re.findall(r"(--[a-z-]+):\s*([^;]+);", css.split("}")[0] + "}"))
def hx(h):
    h = h.strip().lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def chan(c):
    c /= 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
def lum(r):
    return 0.2126 * chan(r[0]) + 0.7152 * chan(r[1]) + 0.0722 * chan(r[2])
a, b = hx(tok["--border"]), hx(tok["--primary"])
l1, l2 = sorted([lum(a), lum(b)], reverse=True)
print(f"{(l1 + 0.05) / (l2 + 0.05):.2f}")
PY
)
if [ -n "$brd_cr" ] && awk "BEGIN{exit !($brd_cr >= 2.0)}"; then
  ok "the selected border is a clear step from the resting border ($brd_cr:1, needs 2.0)"
else
  bad "the selected border is a clear step from the resting border" \
      "got '${brd_cr:-unknown}:1' — selection would be carried by the fill alone"
fi

# Deny/Reject must stay destructive, but flat: a token, not a hand-mixed red.
# Checked with python rather than grep: these rules span several lines and grep
# is line-oriented, so a line-based pattern silently fails to match them.
qac_uses() {  # qac_uses <class> <token>
  python3 - "$CSS" "$1" "$2" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
m = re.search(r"\." + re.escape(sys.argv[2]) + r"\s*\{([^}]*)\}", css)
print("yes" if m and re.search(r"var\(--" + re.escape(sys.argv[3]) + r"\)", m.group(1)) else "no")
PY
}
# Re-baselined when the question card's buttons moved to the .btn primitive.
# This used to grep .qac-btn-destructive, which is the card's PRIVATE name; the
# styling is now .btn-destructive-flat. The INTENT is unchanged - the destructive
# option must come from the token, not a hand-mixed red - so the assertion was
# re-pointed at the canonical class rather than deleted. Mutation-verified:
# swap the token for a literal colour and this goes red.
if [ "$(qac_uses btn-destructive-flat destructive)" = "yes" ]; then
  ok "the destructive option is styled from --destructive"
else
  bad "the destructive option is styled from --destructive" ".btn-destructive-flat is missing or does not use the token"
fi
# The primary action must NOT be the inverted near-white of the reference: on
# Perla that would be a second light-on-dark language and would collide with the
# sender bubble, which is the only such element.
# Same re-baseline: the card's solid accent is now .btn-solid.
if [ "$(qac_uses btn-solid primary-solid)" = "yes" ]; then
  ok "the card's primary action uses --primary-solid, not an inverted white"
else
  bad "the card's primary action uses --primary-solid, not an inverted white" ".btn-solid is missing or has the wrong fill"
fi
# And nothing on the card may reintroduce a hand-mixed near-white.
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
CARD = re.compile(r"entry-question|entry-permission|qac-")
bad = [s for s in re.findall(r"([^{}]+)\{([^}]*)\}", css)
       if CARD.search(" ".join(s[0].split())) and re.search(r"#e5e5e5|#fafafa|#fff\b", s[1])]
sys.exit(1 if bad else 0)
PY
then
  ok "no inverted near-white crept onto the card surface"
else
  bad "no inverted near-white crept onto the card surface" "a literal #e5e5e5/#fafafa/#fff appeared in a card rule"
fi

echo
echo "=== 12. the quick-actions surface is flat and tokenised ==="
# The 38 quick-action buttons were the largest remaining concentration of the
# pre-Phase-3 vocabulary: 12 gradients, 36 raw colour literals, a radial glow
# pseudo-element, a translateY(-3px) scale(1.02) hover lift, and three
# hand-mixed status ring colours applied with !important.
#
# Excluded on purpose: .qa-drawer* is the Output panel chrome, not a button, and
# .qa-input-* is the inline text field inside two buttons. Both are separate
# surfaces with their own scope.
qa_scope() {
  python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
# The button and its parts, not the drawer or the inline input.
KEEP = re.compile(r"\.qa-btn|\.qa-icon|\.qa-label")
OUT = re.compile(r"qa-drawer|qa-input")
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    sel = " ".join(m.group(1).split())
    if KEEP.search(sel) and not OUT.search(sel):
        print(sel + "\t" + " ".join(m.group(2).split()))
PY
}
mapfile -t qa_rules < <(qa_scope)
if [ "${#qa_rules[@]}" -gt 0 ]; then
  ok "the quick-action buttons have real CSS rules (${#qa_rules[@]} found)"
else
  bad "the quick-action buttons have real CSS rules" "no .qa-btn rules found"
fi
qscan() {  # qscan <pattern> <name>
  local pat="$1" name="$2" hits=0
  if [ "${#qa_rules[@]}" -eq 0 ]; then
    bad "no $name on the quick-action buttons" "no rules to scan — vacuous pass"
    return
  fi
  for r in "${qa_rules[@]}"; do
    grep -qE "$pat" <<<"$r" && hits=$((hits + 1))
  done
  [ "$hits" = 0 ] && ok "no $name on the quick-action buttons (scanned ${#qa_rules[@]} rules)" \
    || bad "no $name on the quick-action buttons" "$hits rule(s) still have it"
}
qscan '(linear|radial)-gradient' "gradient"
qscan 'rgba?\(|hsla?\(' "raw colour literal"
qscan 'box-shadow' "box-shadow"
# The glow lived in a ::before pseudo-element; a pseudo-element rule is matched
# here because the selector text carries .qa-btn.
qscan 'radial-gradient' "glow pseudo-element"
# The lift. Scaling a tile inside a fixed grid makes its neighbours jump, and
# 38 buttons moving at once is noise rather than feedback.
# Checked in python, not grep: the earlier version used a line-based pattern
# that could only see a transform sitting on the SAME line as the selector, so
# the ordinary multi-line form of the rule passed vacuously.
if python3 - "$CSS" <<'PYLIFT'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
# Only rules whose SUBJECT is the tile. `.qa-btn:hover .qa-icon` scales the
# glyph inside a fixed-size tile, which does not move the grid and is kept on
# purpose; only a transform on the tile itself is the lift being removed.
hits = []
for sel, body in re.findall(r"([^{}]+)\{([^}]*)\}", css):
    parts = " ".join(sel.split()).split()
    # A single compound means the rule targets the tile itself. A descendant
    # selector such as `.qa-btn:hover .qa-icon` scales the glyph inside a
    # fixed-size tile, which does not move the grid and is kept deliberately.
    if len(parts) != 1:
        continue
    subject = parts[0]
    if not re.search(r"\.qa-btn\b", subject):
        continue
    for d in body.split(";"):
        if d.strip().startswith("transform"):
            hits.append("  " + subject + " -> " + d.strip())
print("\n".join(hits))
sys.exit(1 if hits else 0)
PYLIFT
then
  ok "no hover lift on the quick-action buttons"
else
  bad "no hover lift on the quick-action buttons" "a transform is back on a .qa-btn rule"
fi
# Status feedback used box-shadow rings with !important. A ring is still wanted,
# but as a tokenised outline rather than a shadow override.
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
bad = [s for s in re.findall(r"([^{}]+)\{([^}]*)\}", css)
       if re.search(r"\.qa-btn", s[0]) and "!important" in s[1]]
sys.exit(1 if bad else 0)
PY
then
  ok "no !important overrides on the quick-action buttons"
else
  bad "no !important overrides on the quick-action buttons" "an !important crept back into a .qa-btn rule"
fi
# The success green existed as a bare literal in exactly one rule.
defines "success" && ok "--success is defined" || bad "--success is defined" "absent"
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
sys.exit(0 if re.search(r"\.qa-btn\.is-success[^{]*\{[^}]*var\(--success\)", css) else 1)
PY
then
  ok "the success state is styled from --success"
else
  bad "the success state is styled from --success" ".qa-btn.is-success missing or not using the token"
fi
# Danger must read as danger from the token alone, with no red gradient.
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
m = re.search(r"\.qa-btn-danger\s*\{([^}]*)\}", css)
sys.exit(0 if m and "var(--destructive)" in m.group(1) else 1)
PY
then
  ok "the danger button is styled from --destructive"
else
  bad "the danger button is styled from --destructive" ".qa-btn-danger missing or not using the token"
fi
# The icon chip's hover text colour was a hardcoded #ffd6e0, a value that
# existed nowhere else in the palette.
if grep -q "ffd6e0" "$CSS"; then
  bad "the icon hover colour is a token" "#ffd6e0 is still hardcoded"
else
  ok "the icon hover colour is a token"
fi

echo
echo "=== 13. the attachment surface is flat and tokenised ==="
# Attachments were 64x64 squares: a bordered thumb with no filename, and a chip
# with a 20px icon over a 10px centred truncated name. No type, no size. They are
# now labelled image cards and full-width file rows.
att_scope() {
  python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
# The attachment parts only. .attach-btn is the composer's paperclip trigger and
# .attach-menu is the popover around it — separate surfaces.
KEEP = re.compile(r"\.attach-(thumb|file|preview|meta|row|size|uploading)|\.entry-attachments")
OUT = re.compile(r"\.attach-btn|\.attach-menu")
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    sel = " ".join(m.group(1).split())
    if KEEP.search(sel) and not OUT.search(sel):
        print(sel + "\t" + " ".join(m.group(2).split()))
PY
}
mapfile -t att_rules < <(att_scope)
if [ "${#att_rules[@]}" -gt 0 ]; then
  ok "the attachment surface has real CSS rules (${#att_rules[@]} found)"
else
  bad "the attachment surface has real CSS rules" "no .attach-* rules found"
fi
ascan() {  # ascan <pattern> <name>
  local pat="$1" name="$2" hits=0
  if [ "${#att_rules[@]}" -eq 0 ]; then
    bad "no $name on the attachment surface" "no rules to scan — vacuous pass"
    return
  fi
  for r in "${att_rules[@]}"; do
    grep -qE "$pat" <<<"$r" && hits=$((hits + 1))
  done
  [ "$hits" = 0 ] && ok "no $name on the attachment surface (scanned ${#att_rules[@]} rules)" \
    || bad "no $name on the attachment surface" "$hits rule(s) still have it"
}
ascan '(linear|radial)-gradient' "gradient"
ascan 'rgba?\(|hsla?\(' "raw colour literal"
ascan 'box-shadow' "box-shadow"

# A file row is a ROW now, not a 64px square: it must be full width.
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
m = re.search(r"\.attach-file-row\s*\{([^}]*)\}", css)
b = m.group(1) if m else ""
ok = bool(m) and "width" in b and "100%" in b
sys.exit(0 if ok else 1)
PY
then
  ok "the file row is full width, not a 64px square"
else
  bad "the file row is full width, not a 64px square" ".attach-file-row has no width: 100%"
fi
# The row must not be a fixed square any more.
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
m = re.search(r"\.attach-file-chip\s*\{([^}]*)\}", css)
b = m.group(1) if m else ""
sys.exit(1 if re.search(r"(width|height)\s*:\s*64px", b) else 0)
PY
then
  ok "the file chip is no longer a fixed 64px square"
else
  bad "the file chip is no longer a fixed 64px square" "a 64px width/height is still on .attach-file-chip"
fi
# The dismiss control is a flat ghost on the right of the row, not a red badge.
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
# Neutral, not destructive: the base is muted and it brightens on hover, which
# is the reference's behaviour. The invariant that matters is that red never
# appears here - it would compete with Reject on a permission card.
base = re.search(r"\.attach-file-remove\s*\{([^}]*)\}", css)
hov = re.search(r"\.attach-file-remove:hover\s*\{([^}]*)\}", css)
b = base.group(1) if base else ""
h = hov.group(1) if hov else ""
okrow = bool(base) and "destructive" not in b and "destructive" not in h and "--foreground" in h
sys.exit(0 if okrow else 1)
PY
then
  ok "the file row's dismiss is a neutral ghost, not a red badge"
else
  bad "the file row's dismiss is a neutral ghost, not a red badge" ".attach-file-remove missing, still destructive, or its hover does not brighten"
fi
# The metadata line must exist and be muted, so type·size is legible as secondary.
if python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
# The BASE rule only. `re.search` returns the first hit, and
# `.attach-file-chip-queued .attach-file-meta` now comes first and carries
# layout, not colour. Requiring an exact single-compound selector is what
# distinguishes them — "endswith" is not enough, it matches both.
base = None
for sel, body in re.findall(r"([^{}]+)\{([^}]*)\}", css):
    if " ".join(sel.split()) == ".attach-file-meta":
        base = body
        break
sys.exit(0 if base and "var(--muted-foreground)" in base else 1)
PY
then
  ok "the type·size line is styled from --muted-foreground"
else
  bad "the type·size line is styled from --muted-foreground" ".attach-file-meta missing or not muted"
fi

# The in-flight state must not invent a percentage: the body is one JSON fetch
# with the file inlined as a data URL, so no progress event exists. A fabricated
# number would be worse than none.
if grep -q "Uploading…" perla-companion.js 2>/dev/null || grep -q "Uploading…" "$JS" 2>/dev/null; then
  ok "the upload state is an indeterminate 'Uploading…'"
else
  bad "the upload state is an indeterminate 'Uploading…'" "not found in the JS"
fi
# Comments are stripped first: the source documents WHY there is no percentage,
# and a naive grep matches that explanation and fails the build.
if python3 - "$JS" <<'PYUPL'
import re, sys
js = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
js = re.sub(r"^\s*//.*$", "", js, flags=re.M)
sys.exit(1 if re.search(r"Uploading[: ]+[0-9]+%", js) else 0)
PYUPL
then
  ok "no fabricated upload percentage"
else
  bad "no fabricated upload percentage" "a 'Uploading: NN%' string exists in code but no progress event feeds it"
fi

echo
echo "=== 14. attachment queue vs delivered, and the nine layout rules ==="
# Each of these maps to a specific reported defect. Scoped to single-compound
# selectors where a modifier of the same name exists, so a layout override is
# never mistaken for the base rule.
# The body of a rule whose SELECTOR IS EXACTLY the argument. Anything looser
# matches a descendant modifier of the same name, which is how a check ends up
# asserting against layout CSS instead of the rule it meant to read.
rule_body() {  # rule_body "<exact selector>"
  python3 - "$CSS" "$1" <<'PYR'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
for sel, body in re.findall(r"([^{}]+)\{([^}]*)\}", css):
    if " ".join(sel.split()) == sys.argv[2]:
        sys.stdout.write(body)
        sys.exit(0)
sys.exit(1)
PYR
}
has() { rule_body "$1" 2>/dev/null | grep -qE "$2"; }

# (1) A queued file is a FIXED square, the same size as the queued image tile,
# so a mixed queue is one tidy row instead of squares above full-width bars.
q=$(rule_body ".attach-file-chip-queued" 2>/dev/null || true)
if [ -n "$q" ] && echo "$q" | grep -q "width: 104px" && echo "$q" | grep -q "height: 104px"; then
  ok "(1) a queued file is a fixed 104x104 square"
else
  bad "(1) a queued file is a fixed 104x104 square" "got: $(echo "$q" | tr '\n' ' ')"
fi
if has ".attach-thumb" "width: 104px"; then
  ok "(1) a queued image tile is the same 104px width"
else
  bad "(1) a queued image tile is the same 104px width" ".attach-thumb has no fixed width"
fi

# (3) One border around thumbnail + name + size, not just the image.
# The padding is the 4px rung of the spacing scale now, so it is asserted as the
# token rather than the literal it replaced.
if has ".attach-thumb" "border: 1px solid var\(--border\)" && has ".attach-thumb" "padding: var\(--space-2\)"; then
  ok "(3) the image card border wraps the thumbnail, name and size"
else
  bad "(3) the image card border wraps the thumbnail, name and size" ".attach-thumb has no border/padding of its own"
fi

# (6) A delivered row is a fixed width, not the message bubble's width.
r=$(rule_body ".entry-attachments .attach-file-row" 2>/dev/null || true)
if [ -n "$r" ] && echo "$r" | grep -q "width: 320px"; then
  ok "(6) a delivered attachment row has a fixed 320px width"
else
  bad "(6) a delivered attachment row has a fixed 320px width" "got: $(echo "$r" | tr '\n' ' ')"
fi
# The BASE .attach-file-row keeps width:100% on purpose — that is the composer's
# row, which should fill. What must not happen is the DELIVERED rule falling back
# to it, so the check belongs on the delivered selector, not the base one.
if echo "$r" | grep -qE "^\s*width: 100%\s*;?\s*$"; then
  bad "(6) the delivered row no longer inherits width:100% from the message" "width:100% is back on the delivered rule"
else
  ok "(6) the delivered row no longer inherits width:100% from the message"
fi

# (5) A real gap between the bubble and the bordered attachment rows.
a=$(rule_body ".entry-attachments" 2>/dev/null || true)
if echo "$a" | grep -qE "margin: [0-9]+px 0" || echo "$a" | grep -qE "margin-(top|bottom):"; then
  ok "(5) there is a margin between the message and its attachments"
else
  bad "(5) there is a margin between the message and its attachments" "got: $(echo "$a" | tr '\n' ' ')"
fi

# (9) A real spinner element, not the file icon rotating.
#
# Re-baselined when the spinner became the shared .spinner primitive: this used
# to grep for "attach-file-spinner", which was the attachment chip's private
# name for it. The INTENT is unchanged - a spinner element must exist in the
# markup, distinct from the icon - so the assertion was re-pointed at the
# canonical name rather than deleted. Mutation-verified: delete the
# `spinner.className = "spinner"` line in perla-companion.js and this goes red.
if grep -q 'className = "spinner"' "$JS" 2>/dev/null; then
  ok "(9) a spinner element exists in the markup"
else
  bad "(9) a spinner element exists in the markup" "not found in the JS"
fi
# ...and it must be the primitive, not a lookalike. Checked STRUCTURALLY: a
# bare `grep '\.spinner {'` is satisfied by the prefers-reduced-motion block
# further down the file, which sets one property and no geometry - so renaming
# the real rule while that block remained would still pass. The ring's two
# defining declarations have to appear in the SAME rule body.
if python3 - "$CSS" <<'PY9'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    sels = [s.strip() for s in m.group(1).split(",")]
    if ".spinner" not in sels:
        continue
    body = m.group(2)
    if ("border-radius: var(--radius-full)" in body
            and "border-top-color" in body
            and "animation: perla-spin" in body):
        sys.exit(0)
sys.exit(1)
PY9
then
  ok "(9) the spinner element resolves to the .spinner primitive"
else
  bad "(9) the spinner element resolves to the .spinner primitive" \
      "no single .spinner rule carries the ring's radius, top-border colour and animation"
fi
if grep -qE "\.attach-file-icon[^}]*\{" "$CSS" && python3 - "$CSS" <<'PYS9'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
# The file ICON must not be the thing that rotates any more.
bad = [s for s in re.findall(r"([^{}]+)\{([^}]*)\}", css)
       if re.search(r"attach-file-icon", s[0]) and "animation" in s[1]]
sys.exit(1 if bad else 0)
PYS9
then
  ok "(9) the file icon itself is no longer animated"
else
  bad "(9) the file icon itself is no longer animated" "an animation is on an .attach-file-icon rule"
fi

# (7) Delivered files open a viewer on click; download is a separate control.
if [ "$(python3 - "$JS" <<'PY7'
import re, sys
js = open(sys.argv[1]).read()
i = js.find("function buildDeliveredFileRow")
seg = js[i:i + 3000] if i != -1 else ""
print("yes" if seg and "openFileViewer" in seg and "attach-file-download" in seg else "no")
PY7
)" = "yes" ]; then
  ok "(7) a delivered file opens the viewer, with download as its own control"
else
  bad "(7) a delivered file opens the viewer, with download as its own control" \
      "buildDeliveredFileRow does not wire both openFileViewer and a download button"
fi

# (8) YOUR sent images keep their thumbnails; Perla's sent files are rows.
# These were briefly conflated — flattening a sent image into a file row removed
# the image bar and made a picture indistinguishable from a document.
if [ "$(python3 - "$JS" <<'PY8'
import re, sys
js = open(sys.argv[1]).read()
i = js.find("function addUserMessageEntry")
j = js.find("function addSentFileEntry")
seg = js[i:j] if j > i else js[i:i + 6000]
your_image_thumb = "buildImageCard" in seg
perla_files_are_rows = "buildDeliveredFileRow" in js[js.find("function addSentFileEntry"):]
print("yes" if your_image_thumb and perla_files_are_rows else "no")
PY8
)" = "yes" ]; then
  ok "(8) your sent images stay thumbnails; Perla's sent files stay rows"
else
  bad "(8) your sent images stay thumbnails; Perla's sent files stay rows" \
      "a sent image is being flattened into a file row, or a Perla file lost its row"
fi

# (2) Images are inserted ABOVE the other file row in a sent message.
if [ "$(python3 - "$JS" <<'PY2'
import re, sys
js = open(sys.argv[1]).read()
i = js.find("function addUserMessageEntry")
j = js.find("function addSentFileEntry")
seg = js[i:j] if j > i else js[i:i + 6000]
print("yes" if re.search(r"attachments\.insertBefore\(row, attachments\.firstChild\)", seg) else "no")
PY2
)" = "yes" ]; then
  ok "(2) the images row is inserted above the other files"
else
  bad "(2) the images row is inserted above the other files" "no insertBefore(...firstChild) on attachments"
fi

# (4) Perla's attachments go below the bubble; yours stay above.
if [ "$(python3 - "$JS" <<'PY4'
import re, sys
js = open(sys.argv[1]).read()
def order(fn, stop):
    i = js.find(fn)
    j = js.find(stop, i) if stop else len(js)
    seg = js[i:j]
    b = seg.find("entry.appendChild(bubble)")
    a = seg.find("entry.appendChild(attachments)")
    return (b != -1 and a != -1 and b < a)
# Perla's own send: bubble first, then attachments => attachments below.
perla_below = order("function addSentFileEntry", "function buildDeliveredImageRow")
# The user's send: attachments first, then bubble => attachments above.
i = js.find("function addUserMessageEntry"); j = js.find("function addSentFileEntry")
u = js[i:j]
user_above = u.find("entry.appendChild(attachments)") < u.find("entry.appendChild(bubble)")
# The history replay must no longer insertBefore firstChild.
hist = js[js.find("function addHistoryFileEntry"):]
hist_below = "insertBefore(attachments, entry.firstChild)" not in hist[:1200] and "entry.appendChild(attachments)" in hist[:1200]
print("yes" if (perla_below and user_above and hist_below) else "no")
PY4
)" = "yes" ]; then
  ok "(4) Perla's attachments sit below the message, yours above"
else
  bad "(4) Perla's attachments sit below the message, yours above" \
      "an ordering path still disagrees"
fi

echo
echo "=== 15. the Drive/overlay surface is flat and tokenised ==="
# Drive is where the flatness gap showed. Twelve gradient fills accumulated
# across the Drive toolbar, Drive rows, the menus, the drawer, the file-viewer
# panels and the toasts, and NOTHING scanned any of it - sections 11-13 each
# name one narrow surface, and Drive was not one of them. So the rule is here
# now, and it is deliberately WIDE: every surface rule except the three
# declared decorative exceptions (body's ambient wash, and the two logo marks).
drive_scope() {
  python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
SURFACE = re.compile(r"drive-|floating-menu|reminder-card|toast|qa-drawer|file-viewer-(panel|modal-card)|gate-card|surface-raised")
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    sel = " ".join(m.group(1).split())
    if SURFACE.search(sel):
        print(sel + "\t" + " ".join(m.group(2).split()))
PY
}
mapfile -t drive_rules < <(drive_scope)
if [ "${#drive_rules[@]}" -gt 0 ]; then
  ok "the Drive/overlay surface has real CSS rules (${#drive_rules[@]} found)"
else
  bad "the Drive/overlay surface has real CSS rules" "no Drive/overlay rules found"
fi
scan_drive() {  # scan_drive "<fixed-string>" "<human name>"
  local pat="$1" name="$2" hits=0
  for r in "${drive_rules[@]}"; do
    case "$r" in *"$pat"*) hits=$((hits+1)) ;; esac
  done
  if [ "$hits" -eq 0 ]; then
    ok "$name"
  else
    bad "$name" "$hits rule(s) still match"
  fi
}
scan_drive "-gradient(" "no gradient on the Drive/overlay surface"
scan_drive "!important" "no !important overrides on the Drive/overlay surface"
# Lift on an OVERLAY is functional - it is what says the thing sits above the
# content - so box-shadow is allowed there. What is not allowed is a shadow on
# an in-page surface, which is .surface-raised's job.
if rule_body ".surface-raised" | grep -q 'box-shadow'; then
  bad "the in-page raised surface has no shadow" "got: $(rule_body ".surface-raised")"
else
  ok "the in-page raised surface has no shadow (overlays keep theirs)"
fi

echo
echo "=== 16. radius and space tokens are USED, not just declared ==="
# An unused token is dead weight that reads as intent. fonts.nix carries a
# comment about an installed font nothing referenced; this is the same defect
# in the stylesheet. A token with no consumer is either a mistake or a scale
# entry that has not been adopted yet - both are worth failing on.
#
# The scale only earns its keep on the call sites, so this is what makes the
# adoption sweep stick. Deleting the last `var(--space-8)` is invisible to
# section 7 (which only asks that no *literal* radius appears) and to section 3
# (which only asks that the palette did not drift), yet it turns the whole
# spacing ladder back into eight declarations of intent.
#
# Mutation: add `--radius-9xl: 99px;` to :root -> red.
# Mutation: delete the last `var(--space-8)` -> red.
report=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
m = re.search(r":root\s*\{", css); d, i = 1, m.end()
while d:
    d += (css[i] == "{") - (css[i] == "}"); i += 1
root = css[:i]
declared = set(re.findall(r"(--(?:radius|space)-[a-z0-9-]+)\s*:", root))
used = set(re.findall(r"var\(\s*(--(?:radius|space)-[a-z0-9-]+)", css))
unused = sorted(declared - used)
print(len(unused))
for u in unused:
    print(f"#   {u} is declared in :root but never referenced")
PY
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "every radius/space token has a consumer ($count unused)"
else
  bad "every radius/space token has a consumer" "$report"
fi

echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
