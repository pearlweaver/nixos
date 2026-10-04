#!/usr/bin/env bash
# Tests markdown table rendering (web) and table speech (TTS).
#
# Both halves are testable without a DOM: renderMarkdown returns
# out.join("") (a plain string) and speech_text returns a string, so each is
# extracted from the real source and called directly. No jsdom, no deps.
#
# Why the two halves are asserted together: they must agree on what a table
# IS. A renderer that emits a table the speech path reads as gibberish (or the
# reverse) is the failure this file exists to prevent.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
JS="$HERE/../perla-companion.js"
PY="$HERE/../perla-companion.py"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

# ---------------------------------------------------------------- extract JS
# renderMarkdown is defined at indent 4 and closes at indent 4; every nested
# block is deeper, so the first /^    }$/ after the definition is its end.
python3 - "$JS" "$WORK/render.js" <<'PY'
import sys
lines = open(sys.argv[1]).read().split("\n")
start = next(i for i, l in enumerate(lines) if l.strip() == "function renderMarkdown(text) {")
end = next(i for i in range(start + 1, len(lines)) if lines[i] == "    }")
body = "\n".join(lines[start:end + 1])
assert "return out.join" in body, "extraction missed the return"
open(sys.argv[2], "w").write(body + "\n")
print(f"  extracted renderMarkdown: {end - start + 1} lines")
PY

render() {  # render <markdown> -> html on stdout
  MD="$1" node -e '
    const fs = require("fs");
    const src = fs.readFileSync(process.argv[1], "utf8");
    const renderMarkdown = eval("(" + src + ")");
    process.stdout.write(renderMarkdown(process.env.MD));
  ' "$WORK/render.js"
}

# -------------------------------------------------------------- extract python
# Grab the named top-level functions plus any private helpers, by name.
python3 - "$PY" "$WORK/speech.py" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().split("\n")

def take(name):
    try:
        s = next(i for i, l in enumerate(lines) if l.startswith(f"def {name}("))
    except StopIteration:
        return None
    for j in range(s + 1, len(lines)):
        l = lines[j]
        if l and not l[0].isspace() and not l.lstrip().startswith("#"):
            return "\n".join(lines[s:j])
    return "\n".join(lines[s:])

def take_const(name):
    for i, l in enumerate(lines):
        if re.match(rf"^{name}\s*=", l):
            return l
    return None

# The threshold is extracted from the real source, not hardcoded here, so the
# test tracks the shipped value instead of a copy of it.
const = take_const("TABLE_SPEAK_MAX_ROWS")
if const is None:
    print("  NOTE TABLE_SPEAK_MAX_ROWS not present yet")
    const = "TABLE_SPEAK_MAX_ROWS = 6"

want = ["_describe_code_block", "_speak_code_span", "_flatten_inline",
        "_table_cells", "_is_delimiter_row", "_speak_table", "speech_text"]
chunks, missing = [const], []
for n in want:
    c = take(n)
    if c is None:
        missing.append(n)
    else:
        chunks.append(c)
open(sys.argv[2], "w").write("import re\n\n" + "\n\n\n".join(chunks) + "\n")
if missing:
    print(f"  NOTE not present yet: {', '.join(missing)}")
print(f"  extracted {len(chunks)} python blocks; {const}")
PY

speak() {  # speak <markdown> -> spoken text on stdout
  MD="$1" python3 - "$WORK/speech.py" <<'PY'
import os, runpy, sys
ns = runpy.run_path(sys.argv[1])
print(ns["speech_text"](os.environ["MD"]))
PY
}

contains() { grep -qF -- "$2" <<<"$1"; }

# ============================================================ RENDERER
echo
echo "=== renderer: a GFM table becomes a real <table> ==="
html=$(render '| Name | Qty |
| --- | --- |
| Apples | 3 |
| Pears | 7 |')
contains "$html" "<table" && ok "emits a <table>" || bad "emits a <table>" "got: ${html:0:120}"
contains "$html" "<th>Name</th>" && ok "header cells become <th>" || bad "header cells become <th>" "got: ${html:0:160}"
contains "$html" "<td>Apples</td>" && ok "body cells become <td>" || bad "body cells become <td>" "got: ${html:0:200}"
contains "$html" 'class="prose-table-wrap"' && ok "wrapped for horizontal scroll" || bad "wrapped for horizontal scroll" "no prose-table-wrap"

echo
echo "=== renderer: alignment is honoured ==="
html=$(render '| L | C | R |
| :--- | :---: | ---: |
| a | b | c |')
# Left is the HTML default, so the renderer omits the class for it rather than
# emitting a redundant prose-align-left. Assert that, not the class.
head_row=$(sed -n 's/.*<thead><tr>\(.*\)<\/tr>.*/\1/p' <<<"$html")
contains "$head_row" '<th>L</th>' && ok "left column carries no alignment class (it is the default)" \
  || bad "left column carries no alignment class (it is the default)" "head row: $head_row"
contains "$head_row" 'prose-align-center' && ok "center alignment" || bad "center alignment" "head row: $head_row"
contains "$head_row" 'prose-align-right' && ok "right alignment" || bad "right alignment" "head row: $head_row"
# Alignment must reach the body cells too, not just the header.
body_row=$(sed -n 's/.*<tbody><tr>\(.*\)<\/tr>.*/\1/p' <<<"$html")
contains "$body_row" 'prose-align-right' && ok "alignment is applied to body cells as well" \
  || bad "alignment is applied to body cells as well" "body row: $body_row"

echo
echo "=== renderer: inline formatting and escapes inside cells ==="
html=$(render '| A | B |
| --- | --- |
| **bold** | `code` |')
contains "$html" "<strong>bold</strong>" && ok "bold inside a cell renders" || bad "bold inside a cell renders" "got: ${html:0:200}"
contains "$html" "<code>code</code>" && ok "code inside a cell renders" || bad "code inside a cell renders" "got: ${html:0:200}"
html=$(render '| A |
| --- |
| x \| y |')
contains "$html" "x | y" && ok "escaped pipe stays a literal pipe" || bad "escaped pipe stays a literal pipe" "got: ${html:0:200}"
html=$(render 'A | B
--- | ---
1 | 2')
contains "$html" "<table" && ok "works without edge pipes" || bad "works without edge pipes" "got: ${html:0:160}"

echo
echo "=== renderer: a table inside a code block stays code ==="
html=$(render 'Here:

```
| Not | A table |
| --- | --- |
| x | y |
```')
contains "$html" "<pre" && ok "fenced block still renders as <pre>" || bad "fenced block still renders as <pre>" "got: ${html:0:160}"
contains "$html" "<table" && bad "no table is emitted inside a fence" "a <table> leaked out of the code block" \
  || ok "no table is emitted inside a fence"
html=$(render '    | Not | A table |
    | --- | --- |
    | x | y |')
contains "$html" "<table" && bad "indented code block is not read as a table" "a <table> leaked out" \
  || ok "indented code block is not read as a table"

echo
echo "=== renderer: pipes alone must not become a table ==="
html=$(render 'Use a | b | c for pipes.')
contains "$html" "<table" && bad "a single piped line is not a table" "got: ${html:0:120}" \
  || ok "a single piped line is not a table"
html=$(render '| a | b |
not a delimiter |')
contains "$html" "<table" && bad "a header with no delimiter row is not a table" "got: ${html:0:120}" \
  || ok "a header with no delimiter row is not a table"
html=$(render '| Name |
| --- |')
contains "$html" "<table" && ok "a header-only table (no body rows) still renders" \
  || bad "a header-only table (no body rows) still renders" "got: ${html:0:120}"

echo
echo "=== renderer: cell text is escaped, not injected ==="
html=$(render '| A |
| --- |
| <img src=x onerror=alert(1)> |')
contains "$html" "<img" && bad "raw HTML in a cell is escaped" "an <img> tag survived: ${html:0:160}" \
  || ok "raw HTML in a cell is escaped"

# ================================================================== TTS
echo
echo "=== TTS: a small table is read out, with no pipes spoken ==="
spoken=$(speak '| Name | Qty |
| --- | --- |
| Apples | 3 |
| Pears | 7 |')
contains "$spoken" "Name" && ok "header is spoken" || bad "header is spoken" "got: $(tr '\n' ' ' <<<"$spoken")"
contains "$spoken" "Apples" && ok "a cell value is spoken" || bad "a cell value is spoken" "got: $(tr '\n' ' ' <<<"$spoken")"
contains "$spoken" "|" && bad "no pipe characters are spoken" "pipes survive: $(tr '\n' ' ' <<<"$spoken")" \
  || ok "no pipe characters are spoken"
contains "$spoken" "---" && bad "the delimiter row is not spoken" "dashes survive" \
  || ok "the delimiter row is not spoken"

echo
echo "=== TTS: a big table is announced, not read ==="
big='| Item | Cost | Note |
| --- | --- | --- |
'
for i in $(seq 1 12); do big+="| row$i | $i | note$i |
"; done
spoken=$(speak "$big")
contains "$spoken" "table with 12 rows" && ok "a 12-row table announces its row count" \
  || bad "a 12-row table announces its row count" "got: $(tr '\n' ' ' <<<"$spoken")"
contains "$spoken" "row1" && bad "a big table does not read every cell" "cells were read aloud" \
  || ok "a big table does not read every cell"

echo
echo "=== TTS: markdown inside a cell is still flattened ==="
spoken=$(speak '| A | B |
| --- | --- |
| **bold** | see [docs](https://example.com/x) |')
contains "$spoken" "**" && bad "emphasis markers are not spoken" "got: $(tr '\n' ' ' <<<"$spoken")" \
  || ok "emphasis markers are not spoken"
contains "$spoken" "https://example.com/x" && bad "a link collapses to its label in TTS" "the URL was spoken" \
  || ok "a link collapses to its label in TTS"
contains "$spoken" "docs" && ok "the link label is spoken" || bad "the link label is spoken" "got: $(tr '\n' ' ' <<<"$spoken")"

echo
echo "=== TTS: a table inside a code block is not treated as a table ==="
spoken=$(speak 'Look:
```
| A | B |
| --- | --- |
| 1 | 2 |
```')
contains "$spoken" "A table with" && bad "a fenced table is not announced as a table" "got: $(tr '\n' ' ' <<<"$spoken")" \
  || ok "a fenced table is not announced as a table"

echo
echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
