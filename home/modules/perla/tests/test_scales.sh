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
for t in font-text font-mono; do
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
echo "=================================="
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1