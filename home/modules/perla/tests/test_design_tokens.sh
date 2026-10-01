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
OUT = re.compile(r"qa-drawer|qa-btn|elevate-composer-icon|\.md\b")
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
  [ "$1" = "var(--radius-bubble)" ] || return 1
  local parts=($1) p
  local first="${parts[0]}"
  for p in "${parts[@]}"; do [ "$p" != "$first" ] && return 1; done
  return 0
}
for spec in ".entry-perla .entry-bubble:Perla's" \
            ".entry-user .entry-bubble:the user's" \
            ".entry-system .entry-bubble:the system notice"; do
  sel="${spec%:*}"; who="${spec##*:} bubble"
  r=$(bubble_radius "$sel")
  if is_rounded "$r"; then
    ok "$who is fully rounded ($r)"
  else
    bad "$who is fully rounded" "got '$r' — expected var(--radius-bubble) with all corners equal"
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
#     r=20    ->   0.9px intrusion at any height
# A fixed radius is height-independent, which is exactly why it is safe. The
# threshold is 3px: a sub-pixel-to-few-pixel bite at the very corner of the
# padding box is invisible, and tightening it further only rejects radii that
# render correctly.
pad=14          # .entry-bubble horizontal padding
line=26         # height of the first text line, generously
tolerance=3     # px of arc intrusion tolerated at the corner
radius=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1]).read())
m = re.search(r"--radius-bubble:\s*([0-9.]+)px", css)
print(m.group(1) if m else "")
PY
)
if [ -z "$radius" ]; then
  bad "--radius-bubble is a fixed px value" "not found or not in px"
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
for spec in ".entry-perla .entry-bubble:Perla's" \
            ".entry-user .entry-bubble:the user's" \
            ".entry-system .entry-bubble:the system notice"; do
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
if [ "$(qac_uses qac-btn-destructive destructive)" = "yes" ]; then
  ok "the destructive option is styled from --destructive"
else
  bad "the destructive option is styled from --destructive" ".qac-btn-destructive is missing or does not use the token"
fi
# The primary action must NOT be the inverted near-white of the reference: on
# Perla that would be a second light-on-dark language and would collide with the
# sender bubble, which is the only such element.
if [ "$(qac_uses qac-btn-primary primary-solid)" = "yes" ]; then
  ok "the card's primary action uses --primary-solid, not an inverted white"
else
  bad "the card's primary action uses --primary-solid, not an inverted white" ".qac-btn-primary is missing or has the wrong fill"
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
echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
