#!/usr/bin/env bash
# Regression tests for two bugs that both involved state surviving a turn.
#
# 1. A stale typing indicator came back. The indicator is transient UI, but
#    every setChatLog(output.innerHTML) captured it into the saved transcript,
#    so switching tiers mid-reply persisted it and switching back painted it in
#    AFTER the message had been sent. stripThinking() now removes it on both the
#    write and the read path.
#
# 2. Uploaded file contents were pasted into the day log. format_text_attachments
#    folds file bodies into the prompt because OpenCode has no document channel,
#    and that same string was handed to log_request — so every upload landed in
#    full inside Conversations/{date}.md and the History view.
#    attachment_manifest_line() keeps the user's words and drops the bodies.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
JS="$HERE/../perla-companion.js"
PY="$HERE/../perla-companion.py"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

# ------------------------------------------------- 1. the typing indicator
echo "=== the typing indicator is never persisted ==="
js=$(python3 - "$JS" <<'PY'
import sys
src = open(sys.argv[1]).read()
def fn(name):
    s = next(k for k, l in enumerate(src.split("\n")) if l.strip().startswith("function " + name))
    lines = src.split("\n")
    ind = len(lines[s]) - len(lines[s].lstrip()); e = s
    for k in range(s + 1, len(lines)):
        l = lines[k]
        if l.strip() and (len(l) - len(l.lstrip())) <= ind:
            e = k; break
    return "\n".join(lines[s:e + 1])
missing = [n for n in ("stripThinking", "getChatLog", "setChatLog") if "function " + n not in src]
if missing:
    print("MISSING:" + ",".join(missing)); sys.exit(3)
print(fn("stripThinking")); print(fn("getChatLog")); print(fn("setChatLog"))
PY
)
if [ "${js#MISSING:}" != "$js" ]; then
  bad "the chat-log helpers exist" "${js#MISSING:}"
else
  ok "the chat-log helpers exist"
  # A DOM-free stand-in for the <template> the real code uses.
  printf '%s' "$js" > "$WORK/helpers.js"
  cat > "$WORK/run.js" <<'JS'
// Stand-in for the <template> element stripThinking relies on: a template
// whose querySelectorAll finds the indicator and whose innerHTML comes back
// without it. Regex-based on purpose — this test is about WHICH nodes get
// removed, not about the browser's parser.
// The stub has to make removal OBSERVABLE, otherwise the assertions test the
// stub rather than stripThinking. An earlier version did the stripping inside
// the innerHTML getter, so deleting the real querySelectorAll(...).forEach(remove)
// still "passed" — a false green. Here the nodes handed back by
// content.querySelectorAll delete THEMSELVES from the stored html, so if the
// real code never calls remove(), the indicator survives and the test fails.
const RE_IND = /<div[^>]*id="thinkingIndicator"[^>]*>[\s\S]*?<\/div>/g;
global.document = {
  createElement(tag) {
    if (tag !== "template") return {};
    const tpl = {
      _h: "",
      set innerHTML(v) { tpl._h = v; },
      get innerHTML() { return tpl._h; },
      content: {
        querySelectorAll(sel) {
          // Match on the same selectors stripThinking uses, and hand back
          // self-deleting stand-ins.
          const wantsId = sel.indexOf("#thinkingIndicator") !== -1;
          const wantsClass = sel.indexOf(".thinking") !== -1;
          const found = [];
          const scan = () => {
            let m;
            RE_IND.lastIndex = 0;
            while ((m = RE_IND.exec(tpl._h)) !== null) {
              const frag = m[0];
              const isId = frag.indexOf('id="thinkingIndicator"') !== -1;
              const isClass = frag.indexOf('class="thinking"') !== -1 || /class="[^"]*\bthinking\b/.test(frag);
              if ((wantsId && isId) || (wantsClass && isClass)) found.push(frag);
            }
          };
          scan();
          return found.map((frag) => ({
            remove() { tpl._h = tpl._h.split(frag).join(""); },
          }));
        },
      },
    };
    return tpl;
  },
};
const fs = require("fs");
const helpers = fs.readFileSync(process.argv[2], "utf8");
const src = fs.readFileSync(process.argv[3], "utf8");
eval(helpers);

const results = [];
const t = (name, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  results.push({ name, ok, got: JSON.stringify(actual), want: JSON.stringify(expected) });
};
const IND = '<div class="thinking" id="thinkingIndicator"><span class="think-dot"></span></div>';
const ENTRY = '<div class="entry entry-perla"><div class="entry-bubble">hi</div></div>';

// The reported failure: an indicator captured mid-reply must not come back.
t("a saved indicator is removed", stripThinking(ENTRY + IND), ENTRY);
t("an indicator before a saved entry is removed", stripThinking(IND + ENTRY), ENTRY);
t("an indicator between entries is removed", stripThinking(ENTRY + IND + ENTRY), ENTRY + ENTRY);
t("two indicators are both removed", stripThinking(IND + ENTRY + IND), ENTRY);
// Ordinary content is untouched, including a bubble whose text merely says it.
t("a clean transcript is unchanged", stripThinking(ENTRY), ENTRY);
t("empty input is safe", stripThinking(""), "");
t("a bubble that mentions thinking survives", stripThinking("<p>thinking</p>"), "<p>thinking</p>");

// Stripped on the READ path too, or transcripts already saved with a stale
// indicator keep resurrecting it on every tier switch.
t("getChatLog strips on read", /stripThinking\(sessionStorage/.test(src), true);
t("setChatLog strips on write", /setItem\([^)]*stripThinking\(/.test(src), true);

let failed = 0;
for (const r of results) {
  process.stdout.write((r.ok ? "PASS" : "FAIL") + "\t" + r.name +
    (r.ok ? "" : "\n\tgot  " + r.got + "\n\twant " + r.want) + "\n");
  if (!r.ok) failed++;
}
process.stdout.write("TOTAL\t" + results.length + "\t" + failed + "\n");
JS
  out=$(node "$WORK/run.js" "$WORK/helpers.js" "$JS" 2>&1)
  tab=$'\t'
  n=0
  while IFS="$tab" read -r status name rest; do
    case "$status" in
      PASS) ok "$name"; n=$((n + 1)) ;;
      FAIL) bad "$name" "$(awk -v nm="$name" -F'\t' '$1=="FAIL" && $2==nm {getline g; getline w; print g " " w}' <<<"$out")" ;;
      TOTAL) : ;;
    esac
  done <<<"$out"
  if [ "$n" -lt 8 ]; then
    bad "all indicator assertions ran" "only $n reported (expected >= 8): $(head -2 <<<"$out" | tr '\n' ' ')"
  else
    ok "all indicator assertions ran ($n)"
  fi
fi

# --------------------------------------------- 2. file content out of the log
echo
echo "=== uploaded file content stays out of the log ==="
python3 - "$PY" "$WORK/manifest.py" <<'PY'
import sys
src = open(sys.argv[1]).read()
lines = src.split("\n")
s = next((k for k, l in enumerate(lines) if l.startswith("def attachment_manifest_line")), None)
if s is None:
    print("MISSING:attachment_manifest_line"); sys.exit(3)
e = s + 1
while e < len(lines) and (not lines[e].strip() or lines[e].startswith((" ", "\t"))):
    e += 1
open(sys.argv[2], "w").write("\n".join(lines[s:e]))
PY
if [ -f "$WORK/manifest.py" ]; then
  ok "attachment_manifest_line exists in the daemon"
  man=$(python3 - "$WORK/manifest.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("m", sys.argv[1])
m = importlib.util.module_from_spec(spec)
src = open(sys.argv[1]).read()
ns = {"os": __import__("os")}
exec(src, ns)
f = ns["attachment_manifest_line"]
BIG = "x" * (2 * 1024 * 1024)
cases = [
    ("no attachments passes text through", f("hello", []), "hello"),
    ("empty text still records the manifest",
     f("", [("a.cpp", "y" * 2048)]),
     "[attached: a.cpp (2 KB) — contents not logged]"),
    ("typed text is kept alongside the manifest",
     f("check this", [("a.cpp", "y" * 2048)]),
     "check this\n\n[attached: a.cpp (2 KB) — contents not logged]"),
    ("a large file is summarised in MB, not pasted",
     f("", [("b.pdf", BIG)]),
     "[attached: b.pdf (2.0 MB) — contents not logged]"),
    ("several files are all listed",
     f("hi", [("a.txt", "z" * 10), ("b.md", "w" * 900)]),
     "hi\n\n[attached: a.txt (10 B), b.md (900 B) — contents not logged]"),
]
bad = 0
for name, got, want in cases:
    okk = got == want
    if not okk:
        bad += 1
        print("FAIL\t%s\n\tgot  %r\n\twant %r" % (name, got, want))
    else:
        print("PASS\t%s" % name)
print("TOTAL\t%d\t%d" % (len(cases), bad))
PY
)
  tab=$'\t'
  while IFS="$tab" read -r status name rest; do
    case "$status" in
      PASS) ok "$name" ;;
      FAIL) bad "$name" "manifest output did not match" ;;
      TOTAL) : ;;
    esac
  done <<<"$man"

  # The bodies must not reach the log, and the memory keyword scan must not
  # see them either.
  wiring=$(python3 - "$PY" <<'PYW'
import re, sys
src = open(sys.argv[1]).read()
checks = [
    ("log_request receives the redacted form", "log_request(log_message,"),
    ("the memory scan uses the typed text only", "is_memory_worthy(typed_message)"),
    ("the model still gets the full prompt", "message = (message + \"\\n\\n\" + rendered) if message else rendered"),
]
for name, needle in checks:
    print(("yes" if needle in src else "no ") + "\t" + name)
PYW
)
  while IFS="$tab" read -r good name; do
    [ "$good" = "yes" ] && ok "$name" || bad "$name" "not found in the daemon"
  done <<<"$wiring"
else
  bad "attachment_manifest_line exists in the daemon" "not found"
fi

echo
echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
