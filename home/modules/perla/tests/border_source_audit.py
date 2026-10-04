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


def _paints(body: str) -> bool:
    """True if this declaration block establishes a VISIBLE border.

    A border paints only when border-style is not `none`:
      border: none            -> nothing
      border: 0               -> nothing (width 0)
      border: 1px solid red    -> paints
      border-style: solid     -> paints (width defaults to medium)
      border-width: 1px alone -> NOTHING, style is still none
    """
    for style, val in re.findall(r"(?:^|;)\s*border(-style)?\s*:([^;]+)", body):
        val = val.strip().lower()
        if val.startswith("none") or val in ("0", "0px"):
            continue
        if style == "-style" or not re.fullmatch(r"[\d.]+(px|rem|em)?", val):
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
        if not re.search(r"(^|;)\s*border-color\s*:", body):
            continue
        if re.search(r"(^|;)\s*border(-width|-style)?\s*:", body):
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
