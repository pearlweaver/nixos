#!/usr/bin/env bash
# Guards the SCALE layer added to perla-companion.css: the type, shadow and
# stacking scales, and the rule that a colour is only spelled out inside :root.
#
# Why this file exists separately from test_design_tokens.sh: that suite locks
# the PALETTE (ten named values, unchanged by this work) and the flatness of
# four surfaces. This one locks everything that was hand-typed *around* that
# palette - 15 raw z-index literals, 21 hand-tuned box-shadows, 85 accent and
# status tints written as raw rgba(), a magic 58px repeated four times, and two
# fonts named in the stylesheet that were not installed.
#
# Every assertion here has been mutation-tested: introduce the defect it exists
# to catch, confirm this suite goes red, revert. See the note beside each.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CSS="$HERE/../perla-companion.css"
JS="$HERE/../perla-companion.js"
FONTS="$HERE/../../../../system/modules/fonts.nix"

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

[ -f "$CSS" ] || { echo "  FAIL  stylesheet exists" "not found: $CSS"; exit 1; }
[ -f "$FONTS" ] || { echo "  FAIL  fonts module exists" "not found: $FONTS"; exit 1; }

# Read a token's value straight out of :root.
token_value() { # token_value <name-without-dashes>
  python3 - "$CSS" "$1" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
m = re.search(r"--" + re.escape(sys.argv[2]) + r"\s*:\s*([^;}]+)", css)
print(m.group(1).strip() if m else "")
PY
}
# Resolve one declaration for one selector, reading the cascade.
rule_decl() { # rule_decl <selector> <property>
  python3 - "$CSS" "$1" "$2" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
    if sys.argv[2] in [s.strip() for s in m.group(1).split(",")]:
        d = re.search(re.escape(sys.argv[3]) + r"\s*:\s*([^;}]+)", m.group(2))
        if d:
            print(d.group(1).strip())
            break
PY
}

echo "=== 1. every font the stylesheet PROMISES is actually installed ==="
# The regression that motivated this: the mono stack asked for "JetBrains Mono"
# and "Fira Code", neither installed, while `monocraft` sat installed and
# referenced by nothing. Both stacks silently degraded to the generic fallback
# and the stylesheet still looked correct.
#
# Only the LEADING family of each stack is checked. The families after it are
# fallbacks for platforms this repo does not control - the phone over Tailscale
# will never have this repo's fonts.nix - so demanding they appear there would
# be an assertion that can only ever fail. What matters is that the font we
# promise is the one we install, and that each stack ends in a generic so an
# unknown platform still renders something.
#
# KNOWN LIMIT, stated so nobody assumes otherwise: dropping a FALLBACK from
# fonts.nix does not fail this. `liberation_ttf` supplies Liberation Sans and
# Liberation Mono, which are third and fourth in the stacks - rename or remove
# it and this section stays green. That is the intended trade: the leading
# family is the promise this repo makes, the tail is insurance for platforms it
# does not own. If a fallback ever becomes load-bearing on this machine, promote
# it to leading and let this catch it.
#
# Mutation: remove `inter` from system/modules/fonts.nix -> this goes red.
report=$(python3 - "$CSS" "$FONTS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
nix = open(sys.argv[2], encoding="utf-8").read()
GENERIC = set("""serif sans-serif monospace cursive fantasy system-ui ui-monospace
ui-rounded ui-sans-serif -apple-system BlinkMacSystemFont math emoji inherit
initial unset revert""".split())
# "JetBrains Mono" is the family; `jetbrains-mono` is the package. Compare them
# as whole normalised identifiers, NOT as substrings - a substring test would
# happily accept `jetbrains-mono-nerd-font` and quietly prove nothing.
norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
pkg = re.search(r"fonts\.packages\s*=\s*with\s+pkgs;\s*\[([^\]]*)\]", nix, re.S)
if not pkg:
    print("#   could not find fonts.packages in fonts.nix")
    print(1); sys.exit(0)
# Strip comments, then each entry is one package name.
entries = [l.split("#")[0].strip() for l in pkg.group(1).split("\n")]
installed = {norm(e) for e in entries if e}
# A META-package bundles families whose names do not contain the package name,
# so an exact match would report "Noto Serif" as uninstalled while noto-fonts
# sits right there in the list. These are the only such cases in this file, and
# they are spelled out rather than guessed at, because a wrong entry here would
# quietly exempt a font that genuinely is missing.
BUNDLES = {
    "notofonts": {"notosans", "notoserif", "notosansmono", "notoserifdisplay"},
}
for pkgname, fams in BUNDLES.items():
    if pkgname in installed:
        installed |= fams
# `liberation_ttf` provides Liberation Sans AND Liberation Mono, so a package
# name is not always a family name either.
def provides(fam):
    n = norm(fam)
    return n in installed or any(
        i.startswith(n) and i[len(n):] in ("ttf", "otf") for i in installed)
stacks = re.findall(r"(--font-[a-z]+)\s*:\s*([^;}]+)", css)
if not stacks:
    print("#   no --font-* token found")
    print(1); sys.exit(0)
bad = 0
for tok, stack in stacks:
    fams = [f.strip().strip('"').strip("'") for f in stack.split(",")]
    fams = [f for f in fams if f]
    lead = fams[0] if fams else ""
    if not lead or lead.startswith("var("):
        print(f"#   {tok} names no concrete leading family"); bad += 1
    elif not provides(lead):
        print(f"#   {tok} leads with \"{lead}\", which fonts.nix does not install"); bad += 1
    if not any(f.lower() in GENERIC for f in fams[-1:]):
        print(f"#   {tok} does not end in a generic family"); bad += 1
print(bad)
PY
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "every stack leads with an installed font and ends in a generic ($count defects)"
else
  bad "every stack leads with an installed font and ends in a generic" "$report"
fi

# A stack that is entirely generic, or a self-reference, would satisfy the above
# while naming no installable face at all.
for t in font-text font-sans font-mono; do
  stack=$(token_value "$t")
  if [ -z "$stack" ]; then
    bad "--$t is defined" "absent from :root"
  elif [[ "$stack" == *"var("* || "$stack" == *"inherit"* ]]; then
    bad "--$t is a literal stack" "got '$stack' - it must name families, not re-reference itself"
  else
    ok "--$t is defined and is a literal stack"
  fi
done

echo
echo "=== 2. stacking order comes from the scale, not from literals ==="
# Mutation: change any `z-index: var(--z-*)` back to a bare number -> red.
report=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
hits = [m.group(1).strip() for m in re.finditer(r"z-index\s*:\s*([^;}]+)", css)
        if not m.group(1).strip().startswith("var(")]
print(len(hits))
for h in sorted(set(hits)):
    print("#   " + h)
PY
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "every z-index is a --z-* token ($count checked)"
else
  bad "every z-index is a --z-* token" "$report"
fi

# The scale is only worth having if the ORDER survives it. --z-toast must sit
# below --z-header, which is how toasts pass under the fixed header today.
# Mutation: swap the two values -> red.
z_toast=$(token_value z-toast); z_header=$(token_value z-header)
if [ "$z_toast" -lt "$z_header" ]; then
  ok "--z-toast ($z_toast) stays below --z-header ($z_header)"
else
  bad "--z-toast stays below --z-header" \
      "toast=$z_toast header=$z_header - this would promote toasts above the header"
fi
z_ov=$(token_value z-overlay); z_top=$(token_value z-top)
if [ "$z_top" -gt "$z_ov" ]; then
  ok "--z-top ($z_top) stays above --z-overlay ($z_ov) - the image editor over the lightbox"
else
  bad "--z-top stays above --z-overlay" "overlay=$z_ov top=$z_top"
fi

echo
echo "=== 3. elevation comes from the scale ==="
# Mutation: hand-write any box-shadow value -> red.
# `none` is allowed: it is the absence of a shadow, not a hand-written recipe,
# and a variant that has to CANCEL an inherited one has no other way to say so.
report=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
FORM = re.compile(r'(?:none|var\(--[a-z0-9-]+\)(?:,\s*var\(--[a-z0-9-]+\))*)\s*\Z')
hits = [m.group(1).strip() for m in re.finditer(r"box-shadow\s*:\s*([^;}]+)", css)
        if not FORM.match(m.group(1).strip())]
print(len(hits))
for h in sorted(set(hits)):
    print("#   " + h)
PY
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "every box-shadow is composed from tokens ($count checked)"
else
  bad "every box-shadow is composed from tokens" "$report"
fi

for t in shadow-sm shadow-md shadow-lg shadow-xl shadow-drawer \
         glow-success glow-destructive scrim-crop select-ring; do
  if [ -n "$(token_value "$t")" ]; then
    ok "--$t is defined"
  else
    bad "--$t is defined" "absent from :root"
  fi
done

# The rest of Task 1's tokens, same shape of check. These are the ones a
# refactor could quietly drop: nothing renders them yet, or their only consumer
# is one hand-written rule, so a missing declaration shows up as an empty
# var() rather than a visibly wrong pixel.
#
# Mutation: delete `--space-6` from :root -> red.
# Mutation: rename `--duration-slower` -> red.
for t in duration-slower ease-out sidebar-width sidebar-rail-width; do
  if [ -n "$(token_value "$t")" ]; then
    ok "--$t is defined"
  else
    bad "--$t is defined" "absent from :root"
  fi
done
for t in 1 2 3 4 5 6 7 8; do
  if [ -n "$(token_value "space-$t")" ]; then
    ok "--space-$t is defined"
  else
    bad "--space-$t is defined" "absent from :root"
  fi
done

echo
echo "=== 4. the header's height is stated, and .app reserves the same one ==="
# This is the assertion that earns the token. .app-header used to size itself
# (14px padding + content) while .app reserved a literal 58px. They agreed only
# while the type scale left the content at 30px - and the mobile keyboard
# handler rewrites .app's height from visualViewport on the assumption they
# agree. jsdom has no layout engine, so this reads the cascade instead, the
# same approach selection_dom_test.js uses for geometry.
# Mutation: drop `height:` from .app-header, or point .app's padding-top at a
# literal -> red.
hh=$(token_value header-height)
if [ -n "$hh" ]; then
  ok "--header-height is defined ($hh)"
else
  bad "--header-height is defined" "absent from :root"
fi
for sel in .app-header .app; do
  prop=height; [ "$sel" = ".app" ] && prop=padding-top
  got=$(rule_decl "$sel" "$prop")
  if [ "$got" = "var(--header-height)" ]; then
    ok "$sel { $prop } resolves to --header-height"
  else
    bad "$sel { $prop } resolves to --header-height" \
        "got '$got' - the header and the space reserved for it can disagree"
  fi
done

echo
echo "=== 5. a colour is only spelled out inside :root ==="
# test_design_tokens.sh section 9 forbids `rgba?(` on the chat surface. That
# grep cannot see color-mix(), so an inline color-mix would have satisfied it
# while making the surface LESS flat - defeating the assertion instead of
# satisfying it. So outside :root the only legal color-mix is the derived-tint
# form: a palette token at a bare percentage over transparent. Anything else -
# two colours, a percentage of something not in the palette, an rgb() - is red.
# Mutation: inline `color-mix(in srgb, #ff0000 40%, #0000ff)` anywhere -> red.
report=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
m = re.search(r":root\s*\{", css); d, i = 1, m.end()
while d:
    d += (css[i] == "{") - (css[i] == "}"); i += 1
palette = set(re.findall(r"(--[a-z0-9-]+)\s*:", css[:i]))
ALLOWED = re.compile(r'\Acolor-mix\(in srgb, var\((--[a-z0-9-]+)\) [0-9]{1,3}%, transparent\)\Z')
hits = []
# One level of nesting: color-mix(in srgb, var(--x) 14%, transparent) has a
# closing paren inside the var() reference, so [^;}]*?\) would stop early.
NESTED = re.compile(r"color-mix\((?:[^()]|\([^()]*\))*\)")
# Two legal shapes, both pre-existing in this stylesheet: a palette token
# tinted over transparent (the 85 replacements), and a palette token blended
# into another palette token (.qa-btn-danger:hover). Both name only tokens and
# only bare percentages - which is the whole point. A raw colour in either
# position is what would let someone defeat section 9 of the other suite.
ALLOWED = re.compile(
    r'\Acolor-mix\(in srgb, var\((--[a-z0-9-]+)\) [0-9]{1,3}%, '
    r'(?:transparent|var\((--[a-z0-9-]+)\))\)\Z')
for cm in NESTED.finditer(css[i:]):
    t = cm.group(0)
    mm = ALLOWED.match(t)
    if not mm or mm.group(1) not in palette or (mm.group(2) and mm.group(2) not in palette):
        hits.append(t)
print(len(hits))
for h in sorted(set(hits))[:6]:
    print("#   " + h)
PY
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "every color-mix() outside :root is a derived palette tint ($count checked)"
else
  bad "every color-mix() outside :root is a derived palette tint" "$report"
fi

# And no raw literal may reappear outside :root for a colour the palette already
# names. That is the 85 hand-written rgba() tints this replaced.
# Mutation: write `rgba(201, 123, 141, 0.14)` back into any rule -> red.
report=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
m = re.search(r":root\s*\{", css); d, i = 1, m.end()
while d:
    d += (css[i] == "{") - (css[i] == "}"); i += 1
root, outside = css[:i], css[i:]
palette_hex, palette_rgb = set(), set()
for h in re.findall(r"#[0-9a-fA-F]{3,8}\b", root):
    palette_hex.add(h.lower())
    if len(h) == 7:
        palette_rgb.add((int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)))
hits = [h.lower() for h in re.findall(r"#[0-9a-fA-F]{3,8}\b", outside) if h.lower() in palette_hex]
for t in re.findall(r"rgba?\(\s*([0-9]{1,3})\s*,\s*([0-9]{1,3})\s*,\s*([0-9]{1,3})", outside):
    rgb = (int(t[0]), int(t[1]), int(t[2]))
    # Achromatic values are exempt, and deliberately so. rgba(255,255,255,.05)
    # hairlines and rgba(0,0,0,.45) scrims are neutral by intent - they are not
    # --primary-foreground or --background wearing a hat. --primary-foreground
    # is white because it sits on the pink primary, not because it is "white",
    # so treating the two as the same colour would be wrong. Every chromatic
    # palette tint is still caught: rgba(201, 123, 141, .14) fails.
    if rgb[0] == rgb[1] == rgb[2]:
        continue
    if rgb in palette_rgb:
        hits.append("rgba(%s, %s, %s)" % t)
print(len(hits))
for h in sorted(set(hits)):
    print("#   " + h)
PY
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "no palette colour is re-spelled outside :root ($count checked)"
else
  bad "no palette colour is re-spelled outside :root" "$report"
fi

echo
echo "=== 6. every var() in the stylesheet resolves ==="
# A token refactor is only safe if nothing points at a token that does not
# exist. The image editor and lightbox legitimately set eight of these at
# runtime via setProperty, so those resolve against the JS instead.
# Mutation: rename a --z-*/--shadow-* token in :root without updating its use
# sites -> red.
report=$(python3 - "$CSS" "$JS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())
js = open(sys.argv[2], encoding="utf-8").read()
m = re.search(r":root\s*\{", css); d, i = 1, m.end()
while d:
    d += (css[i] == "{") - (css[i] == "}"); i += 1
defined = set(re.findall(r"(--[a-zA-Z0-9-]+)\s*:", css[:i]))
runtime = set(re.findall(r"setProperty\(\s*['\"](--[a-zA-Z0-9-]+)", js))
missing = sorted(set(re.findall(r"var\(\s*(--[a-zA-Z0-9-]+)", css)) - defined - runtime)
print(len(missing))
for x in missing:
    print("#   " + x + (" (set at runtime by the JS)" if x in runtime else ""))
PY
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "every var() resolves to :root or to a runtime setProperty ($count checked)"
else
  bad "every var() resolves to :root or to a runtime setProperty" "$report"
fi

echo
echo "=== 7. no hand-typed size, duration or radius left in the stylesheet ==="
# The three scales only hold if nothing bypasses them. Before this pass the
# stylesheet carried 38 distinct font-size values (against a declared scale
# whose larger half had zero references), 6 durations outside the two tokens,
# and 8 border-radius values plus 3 literals (1px/2px/3px) across four different
# corner languages - which is why message bubbles and attachment chips each
# ended up with their own rounding.
#
# Mutation: change any `font-size: 13px` back to a raw value -> red.
# Mutation: change any `transition: ... 0.18s` to 0.2s -> red.
# Mutation: write `border-radius: 3px` anywhere -> red.
#
# The scale's VALUES are load-bearing and used to be unguarded. Before the
# adoption sweep only a handful of rules read a --text-* token, so a typo in
# one of the seven values would have moved two or three labels and nothing
# would have noticed. After the sweep roughly 35 hand-typed literals are bound
# to these seven tokens, so every one of the ~570 assertions in this repo can
# see a refactor but none of them can see a changed number. The numbers are
# pinned here in the same spirit as test_design_tokens.sh section 3, which locks
# the ten palette hex values for exactly the same reason: a rename layer is not
# a licence to restyle.
#
# Mutation: change --text-sm from 0.8125rem to 0.8rem -> red.
# Mutation: swap the --text-xs and --text-sm values -> red.
for spec in "text-2xs:0.6875rem" "text-xs:0.75rem" "text-sm:0.8125rem" \
            "text-md:0.875rem" "text-lg:1rem" "text-xl:1.125rem" \
            "text-2xl:1.375rem"; do
  tok="${spec%%:*}"; want="${spec#*:}"; got=$(token_value "$tok")
  if [ "$got" = "$want" ]; then
    ok "--$tok is $want"
  else
    bad "--$tok is $want" "got '$got' - every rule on this rung moves with it"
  fi
done

report=$(python3 - "$CSS" <<'PY'
import re, sys
css = re.sub(r"/\*[\s\S]*?\*/", "", open(sys.argv[1], encoding="utf-8").read())

# --- font-size: allowed values are inherit, 0, 1em, the scale tokens, and the
# --- handful of ICON-relative sizes which are a different axis entirely.
FONT_OK = {
    "inherit", "0", "1em",
    "var(--text-2xs)", "var(--text-xs)", "var(--text-sm)", "var(--text-md)",
    "var(--text-lg)", "var(--text-xl)", "var(--text-2xl)",
    "var(--qac-text-title)", "var(--qac-text-label)", "var(--qac-text-sub)",
    "var(--qac-text-desc)", "var(--qac-text-status)", "var(--qac-text-command)",
    "var(--qac-text-progress)",
}
bad_font = [m.group(1).strip() for m in
            re.finditer(r"font-size\s*:\s*([^;}]+)", css)
            if m.group(1).strip() not in FONT_OK]

# --- duration: a timing value is one of the three tokens, or a CYCLE length.
# --- A cycle length is how long one repetition of a LOOPING animation takes - a
# --- rotation, a breath, a blink - and it is not a response time. Binding it to
# --- --duration would retime the loop rather than the transition, and the damage
# --- is not subtle: perla-spin at 0.2s is a blur rather than a spin, and
# --- pulse-ring at 0.3s fires three ripples per breath instead of one.
# ---
# --- The allowance is keyed on the ANIMATION NAME, never on a bare list of
# --- numbers. Numbers made it two separate holes: `animation: fade-in 2s ease`
# --- sailed through on the strength of the one reduced-motion spinner, and a
# --- TRANSITION could carry a cycle length at all - a category error, since a
# --- transition has no repetition to be a cycle OF. So a `transition` may only
# --- use the tokens, and a literal time on an animation must be one this file
# --- has already justified at that animation's own call site.
# ---
# --- Note this is STRICTER than the allowlist it replaces, which also waved
# --- through bare 0.15/0.22/0.3s - those are precisely the values of the three
# --- tokens, so accepting them let a transition bypass the scale by spelling
# --- out the number the scale already says.
DUR_TOKENS = ("var(--duration)", "var(--duration-slow)", "var(--duration-slower)")
CYCLE_OK = {
    "perla-spin":   {"0.7", "0.8", "1"},   # rotation rate; slower on bigger icons
    "shake":        {"0.4"},              # one COMPLETE shake, 4 keyframe stops
    "pulse-ring":   {"1.8", "0.6"},       # 1.8 breath period, 0.6 ring stagger
    "blink-wax":    {"1.6"},              # dim-and-return cadence
    "think-bounce": {"1.1"},              # the gap between bounces
}
bad_dur = []
# Byte ranges of the prefers-reduced-motion bodies, so the single longhand cycle
# allowance below can be scoped to the rule that actually needs it.
reduced = []
for m in re.finditer(r"@media\s*\(\s*prefers-reduced-motion\s*:\s*reduce\s*\)\s*\{", css):
    d, i = 1, m.end()
    while d:
        d += (css[i] == "{") - (css[i] == "}"); i += 1
    reduced.append((m.start(), i))
in_reduced = lambda pos: any(a <= pos < b for a, b in reduced)

# A transition is a RESPONSE time, so the tokens are its only legal value - no
# exceptions. The longhand is checked too: a shorthand-only scan cannot see
# `transition-duration: 0.09s` at all.
for m in re.finditer(r"(transition|transition-duration)\s*:\s*([^;}]+)", css):
    for d in re.findall(r"(\d*\.?\d+)m?s", m.group(2)):
        if d not in DUR_TOKENS:
            bad_dur.append(f"{m.group(1)}: {d}s")
# An animation may additionally carry a cycle length, but only one its own name
# is entitled to.
for m in re.finditer(r"animation\s*:\s*([^;}]+)", css):
    parts = m.group(1).split()
    name = parts[0] if parts else ""
    allowed = set(CYCLE_OK.get(name, set())) | set(DUR_TOKENS)
    for d in re.findall(r"(\d*\.?\d+)m?s", m.group(1)):
        if d not in allowed:
            bad_dur.append(f"animation {name or '<empty>'}: {d}s")
# `animation-duration` names no animation, so it cannot be keyed on one. There is
# exactly one of them in the file - .spinner's reduced-motion slow-down - and the
# allowance is scoped to that block, so the same number anywhere else still
# fails.
for m in re.finditer(r"animation-duration\s*:\s*([^;}]+)", css):
    for d in re.findall(r"(\d*\.?\d+)m?s", m.group(1)):
        if d not in DUR_TOKENS and not (d == "2" and in_reduced(m.start())):
            bad_dur.append(f"animation-duration: {d}s")

# --- border-radius: exactly the four roles, plus the micro-elements and the one
# --- compound the file actually argues for at its own call site.
# --- Deliberately NOT allowlisted: any asymmetric form built on --radius-sm.
# --- There were three such slots here, commented as "reserved for a bubble tail
# --- corner", and they pre-approved a shape that test_design_tokens.sh section
# --- 10 records as having been removed AT THE USER'S REQUEST. A future editor
# --- reading this section first would have found the slots waiting with no
# --- explanation; read section 10 before proposing one.
RAD_OK = (
    "var(--radius-md)", "var(--radius-lg)", "var(--radius-xl)", "var(--radius-full)",
    "50%", "9999px", "0",
    # #qaDrawer is a bottom sheet: top corners lifted, bottom flush with the
    # viewport. Tokenised from radius-2xl without moving which corners round.
    "var(--radius-lg) var(--radius-lg) 0 0",
    # --space-1 is NOT a radius step and is not used as one: it is the three
    # decorative micro-elements (11px mic-stop square, 2px wave bars, 1.5px
    # hamburger lines) whose own dimensions are ~2px. Binding those to
    # --radius-sm (4.8px) would round them into pebbles and semicircles.
    "var(--space-1)",
)
bad_rad = [m.group(1).strip() for m in
           re.finditer(r"border-radius\s*:\s*([^;}]+)", css)
           if m.group(1).strip() not in RAD_OK]

total = len(bad_font) + len(bad_dur) + len(bad_rad)
print(total)
for v in sorted(set(bad_font)):
    print(f"#   font-size: {v}")
for v in sorted(set(bad_dur)):
    print(f"#   duration: {v}")
for v in sorted(set(bad_rad)):
    print(f"#   border-radius: {v}")
PY
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "no off-scale font-size, duration or border-radius ($count defects)"
else
  bad "no off-scale font-size, duration or border-radius" "$report"
fi

echo
echo "=== 8. the stylesheet is structurally sound ==="
# Every other section here is text/regex based, which is exactly why destroyed
# declarations shipped green: section 7 regex-matches `property: value` on text a
# browser throws away. CSS error recovery discards a malformed declaration AND
# the next one up to its `;`, so in-rule why-comments written without their
# `/* */` markers silently took out real declarations - #qaDrawer's
# `position: fixed` (the Quick-Actions bottom sheet became in-flow document
# content), .chat-dropzone-active::after's `content: ""` (which deletes the
# dropzone highlight outright - a ::after with no `content` generates no box at
# all), and .floating-menu's `display: flex`.
#
# So there are TWO things to reject, and the first round only had the first:
#
#   1. a fragment that is not shaped like `property: value` at all, where
#      property is a plain identifier or a custom property. This catches prose
#      that happens to start with a word and no colon.
#   2. a fragment whose VALUE contains a second `identifier:` pair. This is the
#      one that matters, because an unmarked comment reading
#      `overlay: a dialog` SATISFIES rule 1 - it really is `word: text` - and so
#      sailed through a clean report while eating the `width: 100%` after it.
#      A real declaration's value never carries a second colon-separated
#      identifier.
#
# @keyframes is excluded because its inner blocks are percentage STOPS
# (`0%, 80% { ... }`), which are not declarations.
#
# KNOWN LIMIT, stated so nobody assumes otherwise: a value carrying a URL with a
# scheme - `url(data:image/svg+xml,...)` or `url(https://...)` - WOULD trip rule
# 2, because the scheme's colon looks like a second identifier. Neither exists in
# this stylesheet (no `url(` at all), and the failure would be a confusing red
# rather than a wrong pass. If a data-URI background is ever added, narrow rule 2
# to skip inside `url(...)` then; do not weaken it for anything else.
#
# Mutation: remove the `/* */` from any one in-rule why-comment -> red.
# Mutation: drop a comment's closing `*/` -> red on the marker-count assertion.
report=$(python3 - "$CSS" <<'PY'
import re, sys
raw = open(sys.argv[1], encoding="utf-8").read()
# Blank comments while PRESERVING OFFSETS, so a stray body fragment still shows
# up in the parsed text AND keeps its real line number for the report.
css = re.sub(r"/\*[\s\S]*?\*/", lambda m: " " * (m.end() - m.start()), raw)
PROP = re.compile(r"\A-{0,2}[A-Za-z][A-Za-z0-9-]*\s*:")
# A second colon-separated identifier inside an already-matched value.
SECOND_IDENT = re.compile(r"[A-Za-z][A-Za-z0-9-]*\s*:")
# Byte ranges of every @keyframes body, which the declaration rule does not apply to.
kf = []
for m in re.finditer(r"@keyframes\s+[\w-]+\s*\{", css):
    d, i = 1, m.end()
    while d:
        d += (css[i] == "{") - (css[i] == "}"); i += 1
    kf.append((m.start(), i))
bad, scanned = [], 0
for m in re.finditer(r"([^{}]*)\{([^{}]*)\}", css):
    if any(a <= m.start() < b for a, b in kf):
        continue
    sel = " ".join(m.group(1).split())
    for frag in m.group(2).split(";"):
        f = frag.strip()
        if not f:
            continue
        scanned += 1
        mm = PROP.match(f)
        if not mm:
            # Not shaped like a declaration at all: prose that never reached a colon.
            bad.append((raw.count("\n", 0, m.start()) + 1, sel[:40],
                        "unmarked text: " + " ".join(f.split())[:48]))
        elif SECOND_IDENT.search(f[mm.end():]):
            # Shaped like one, but the value carries a second `identifier:` - which
            # is what an unmarked comment like `overlay: a dialog` looks like once
            # the declaration it swallowed is glued onto the end of it.
            bad.append((raw.count("\n", 0, m.start()) + 1, sel[:40],
                        "second identifier in value: " + " ".join(f.split())[:40]))
print(len(bad))
# The floor is what stops this passing by scanning nothing. It sits far below
# the real figure but far above zero, so deleting most of the stylesheet, or
# breaking the parser so it matches no bodies, is caught rather than reported
# as "clean".
print(f"# scanned={scanned} keyframes_excluded={len(kf)}")
if scanned < 1500:
    print(f"# SCAN FLOOR: only {scanned} fragments scanned, expected >= 1500")
for ln, sel, f in bad[:8]:
    print(f"#   line {ln}: {sel} -> \"{f}\"")
PY
)
scanned=$(printf '%s\n' "$report" | sed -n 's/^# scanned=\([0-9]*\) .*/\1/p' | head -1)
if printf '%s\n' "$report" | grep -q "^# SCAN FLOOR"; then
  bad "every rule body is nothing but declarations" \
      "$(printf '%s\n' "$report" | grep "^#" | head -2)"
elif [ "${report%%#*}" -eq 0 ]; then
  ok "every rule body is nothing but declarations ($scanned fragments scanned)"
else
  bad "every rule body is nothing but declarations" "$report"
fi

# An unpaired comment marker is the other way this defect shows up, and it is
# worse: an unclosed `/*` comments out everything after it, leaving section 7
# scanning an empty file and cheerfully reporting zero defects. So the marker
# counts are asserted, which is what keeps section 8 from passing vacuously.
report=$(python3 - "$CSS" <<'PY'
import re, sys
raw = open(sys.argv[1], encoding="utf-8").read()
opens, closes = len(re.findall(r"/\*", raw)), len(re.findall(r"\*/", raw))
# A `/*` inside an already-open comment is invalid CSS and swallows the closer.
nested = [m.start() for m in re.finditer(r"/\*[\s\S]*?\*/", raw) if m.group(0).count("/*") > 1]
# `opens` and `closes` are already ints from len(), so the imbalance is
# `opens - closes` - calling len() on either raised TypeError and took the
# detail line below with it. The branch still failed closed, but a diagnostic
# that cannot execute is not a diagnostic.
print(opens - closes if opens != closes else (len(nested) or 0))
if opens != closes:
    print(f"#   {opens} '/*' vs {closes} '*/' - an unclosed comment swallows the rest of the file")
for p in nested[:3]:
    print(f"#   nested '/*' inside an open comment at line {raw.count(chr(10), 0, p) + 1}")
PY
)
count=${report%%#*}
if [ "$count" -eq 0 ]; then
  ok "every comment is opened and closed exactly once"
else
  bad "every comment is opened and closed exactly once" "$report"
fi

echo
echo "=================================="
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1