#!/usr/bin/env python3
"""Prints any border-colour-only rule whose element has no border to paint.

The `* { border-color: ... }` rule means every element carries a border colour,
so a rule setting only a colour LOOKS effective while border-style is still
`none`. Resolution has to consider every other class on the same element in real
markup, or elements like `.history-daypicker-btn.open` (which is also a `.btn`)
come back as false positives.

Exit 0 and print nothing when the stylesheet is clean.
"""
import re
import sys

# One CSS border property, in the two shapes it comes in:
#
#   border            border-style        border-width        border-color
#   border-bottom     border-bottom-style border-bottom-width border-bottom-color
#
# The pattern is `border` + an OPTIONAL side + an OPTIONAL longhand, in that
# order, which is the order CSS itself spells them in.
#
# It has to name all of them. It used to be `border(-style)?`, which matched
# neither a per-side longhand nor `border-color` - and the two blind spots it
# left are what kept this guard from seeing the file's underline fields at all.
# `.input-underline { border: none; border-bottom: 1px solid var(--border) }`
# reported NO border (the shorthand was `none`, the longhand was invisible), and
# `.input-underline:focus { border-bottom-color: ... }` was never even a
# candidate, because the colour trigger spelled `border-color` and a longhand
# does not contain it. Both holes were pre-existing; .input-underline is simply
# the first rule in the file whose ONLY border is a longhand, so it is the first
# rule they could swallow.
#
# Two patterns, not one, and the split is load-bearing. `_paints` asks "does
# this block ESTABLISH a border", and a `-color` longhand never does: a colour
# paints nothing on its own. Folding it in - the obvious way to widen this -
# makes `.input-underline:focus` count as the border source for
# `.input-underline:focus`, so the rule satisfies its own resolution and is
# NEVER flagged no matter what else happens to the field. That was caught by
# mutation (delete `.input-underline`'s border-bottom, expect section 14 to go
# red; it stayed silent) and it is exactly the defect this file exists to find,
# reproduced inside the fix for it. So the scan pattern omits `-color` and the
# candidate test in main() keeps it.
BORDER = r"border(?:-(?:top|right|bottom|left))?(?:-(?:style|width|color))?\s*:"
# The same, minus the colour longhand: a colour cannot establish a border.
BORDER_PAINT = r"border(?:-(?:top|right|bottom|left))?(?:-(?:style|width))?\s*:"


def _paints(body: str) -> bool:
    """True if this declaration block establishes a VISIBLE border.

    A border paints only when border-style is not `none`:
      border: none            -> nothing
      border: 0               -> nothing (width 0)
      border: 1px solid red    -> paints
      border-style: solid     -> paints (width defaults to medium)
      border-bottom: 1px solid red   -> paints, and so does its -style sibling
      border-width: 1px alone -> NOTHING, style is still none
      border-bottom-color: red      -> NOTHING (this is the point of BORDER_PAINT)
    """
    for m in re.finditer(r"(?:^|;)\s*" + BORDER_PAINT + r"([^;]+)", body):
        prop = m.group(0).split(":")[0].strip().lower()
        val = m.group(1).strip().lower()
        if val.startswith("none") or val in ("0", "0px"):
            continue
        if prop.endswith("-style") or not re.fullmatch(r"[\d.]+(px|rem|em)?", val):
            return True
    return False


def main() -> int:
    css_path, html_path, js_path = sys.argv[1:4]
    css_raw = open(css_path, encoding="utf-8").read()
    css = re.sub(r"/\*[\s\S]*?\*/", "", css_raw, flags=re.S)
    blob = open(html_path, encoding="utf-8").read() + open(js_path, encoding="utf-8").read()

    # Classes whose rules establish a VISIBLE border.
    #
    # "Declares a border property" is not the same thing, and conflating them
    # made this guard blind in exactly the way it exists to prevent: counting
    # `border: none` as a border source, so neutering a base rule (`.toast {
    # border: none }`) left every colour-only state looking fine.
    #
    # A border paints only when border-style is not `none`:
    #   border: none            -> nothing
    #   border: 1px solid red    -> paints
    #   border-style: solid     -> paints (width defaults to medium)
    #   border-width: 1px alone -> NOTHING, style is still none
    #   border-bottom: 1px solid red -> paints (a per-side longhand is a border)
    #   border-bottom-color: red     -> NOTHING (a colour establishes nothing)
    provides = set()
    for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
        if _paints(m.group(2)):
            for sel in m.group(1).split(","):
                provides.update(re.findall(r"\.([A-Za-z][\w-]*)", sel))
    # Bare elements that some rule gives a VISIBLE border, e.g. `.prose pre`.
    # Derived, not hardcoded - a fixed set would assert `pre` paints whether or
    # not any rule actually gives it one, which is the bug this file hunts.
    elem_paints = set()
    for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
        body = m.group(2)
        if not _paints(body):
            continue
        for sel in m.group(1).split(","):
            for tag in re.findall(r"(?:^|\s)([a-z][a-z0-9]*)\s*$", " ".join(sel.split())):
                elem_paints.add(tag)

    out = []
    for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
        sel = " ".join(m.group(1).split())
        body = m.group(2)
        # `*` is the SOURCE of the default border colour, not a consumer of one:
        # it exists so any element that declares a border gets --border without
        # repeating it. Flagging it would be flagging the mechanism itself.
        if {p.strip() for p in sel.split(",")} <= {"*"}:
            continue
        if not re.search(r"(^|;)\s*" + BORDER, body) \
           or not re.search(r"border(?:-\w+)*-color\s*:", body):
            continue  # sets no border at all, or sets no border COLOUR
        if re.search(r"(^|;)\s*border(?:-(?:width|style))?\s*:", body):
            continue  # declares its own width/style, so it is fine
        classes = re.findall(r"\.([A-Za-z][\w-]*)", sel)
        tags = set(re.findall(r"(?:^|[\s,>+~])([a-z][a-z0-9]*)(?=[\s,:{.#]|$)", sel))
        co = set()
        for c in classes:
            for mm in re.finditer(r'class="([^"]*\b' + re.escape(c) + r'\b[^"]*)"', blob):
                co.update(mm.group(1).split())
            for mm in re.finditer(r'className\s*=\s*"([^"]*\b' + re.escape(c) + r'\b[^"]*)"', blob):
                co.update(mm.group(1).split())
        if ((co & provides) or (tags & elem_paints) or (set(classes) & provides)) \
           and (tags <= elem_paints or not tags):
            continue
        out.append(sel)
    for sel in out:
        print(sel)
    return 0


if __name__ == "__main__":
    sys.exit(main())
