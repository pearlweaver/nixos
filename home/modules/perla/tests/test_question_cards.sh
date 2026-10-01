#!/usr/bin/env bash
# Behaviour tests for the question card (web).
#
# The bug under test: OpenCode's question schema declares two OPTIONAL flags —
#   multiple?: boolean   "Allow selecting multiple choices"
#   custom?:   boolean   "Allow typing a custom answer (default: true)"
# (node_modules/@opencode-ai/sdk/.../types.gen.d.ts). Perla read NEITHER. It
# always allowed multi-select and always rendered a free-text input, so a
# question the model meant as one-of-three could be answered with three ticks
# and nothing in the UI said that was wrong.
#
# These tests pin the decision logic, not the pixels. The functions are
# extracted from the real source STRUCTURALLY (by dedent, never by line number)
# and run in node with a minimal DOM stub, so the test cannot drift from the
# implementation and needs no jsdom.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
JS="$HERE/../perla-companion.js"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail + 1)); }

# ------------------------------------------------------------- extract the bits
python3 - "$JS" "$WORK" <<'PY'
import sys, os
src = open(sys.argv[1]).read()
out = sys.argv[2]
lines = src.split("\n")

def block(sig):
    """Source of a function INCLUDING its closing brace.

    The closing brace of a top-level function sits at the same indent as the
    `function` line, so the terminator is `<=`, not `<`. Two bugs lived here
    before: `<` ran away and swallowed the rest of the 6400-line file, and
    excluding the terminator line dropped the closing `}` so the extracted
    source would not even parse.
    """
    start = next(i for i, l in enumerate(lines) if l.strip().startswith(sig))
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = start
    for i in range(start + 1, len(lines)):
        l = lines[i]
        if not l.strip():
            continue
        if (len(l) - len(l.lstrip())) <= indent:
            end = i          # include the closing brace, THEN stop
            break
        end = i
    return "\n".join(lines[start:end + 1])

# The pure decision helpers. If these do not exist yet the test fails loudly
# rather than silently passing on an empty extraction.
missing = [sig for sig in ("function questionAllowsMultiple(",
                          "function questionAllowsCustom(",
                          "function collectQuestionAnswers(")
           if sig not in src]
if missing:
    for sig in missing:
        print(f"MISSING:{sig}")
    sys.exit(3)

os.makedirs(out, exist_ok=True)
with open(os.path.join(out, "helpers.js"), "w") as f:
    for sig in ("function questionAllowsMultiple(",
                "function questionAllowsCustom(",
                "function collectQuestionAnswers(",
            "function permissionScopeList("):
        b = block(sig)
        # A runaway extraction is a broken test, not a pass.
        if b.count("\n") > 40:
            print(f"RUNAWAY:{sig} extracted {b.count(chr(10))} lines")
            sys.exit(4)
        f.write(b + "\n")
PY
rc=$?
case "$rc" in
  3) bad "question helpers exist in the source" \
       "questionAllowsMultiple / questionAllowsCustom / collectQuestionAnswers not found — the schema flags are still being ignored" ;;
  4) bad "helper extraction is bounded" "a helper block ran away — the extractor is broken, not the source" ;;
  0) ok "question helpers exist in the source" ;;
  *) bad "helper extraction" "python exited $rc" ;;
esac
[ "$rc" = 0 ] || { echo; echo "=================================="; echo "  $pass passed, $fail failed"; exit 1; }

# ------------------------------------------------------------------- run them
cat > "$WORK/run.js" <<'JS'
const fs = require("fs");
const helpers = fs.readFileSync(process.argv[2], "utf8");
const mod = eval(helpers + "\n;({ questionAllowsMultiple, questionAllowsCustom, collectQuestionAnswers, permissionScopeList })");
if (Object.keys(mod).length !== 4) throw new Error("helpers did not load: " + Object.keys(mod));
process.stdout.write("READY\n");

const results = [];
// Accepts a value or a thunk. A thunk matters: several of these expressions
// CALL the helper, and when the helper regressed to `return v || []` the
// `.join()` call threw. An uncaught throw killed the node process before any
// result was printed, so the run reported zero assertions and the suite looked
// green. Isolating each assertion turns that crash into a FAIL.
const t = (name, actualOrFn, expected) => {
  let actual, err = null;
  try {
    actual = (typeof actualOrFn === "function") ? actualOrFn() : actualOrFn;
  } catch (e) {
    err = e;
  }
  const ok = !err && JSON.stringify(actual) === JSON.stringify(expected);
  results.push({ name, ok,
                 got: err ? ("threw: " + err) : JSON.stringify(actual),
                 want: JSON.stringify(expected) });
};

// --- multiple: single-select unless the model explicitly opts in
t("multiple absent -> single select",  mod.questionAllowsMultiple({}), false);
t("multiple false   -> single select",  mod.questionAllowsMultiple({ multiple: false }), false);
t("multiple true    -> multi select",   mod.questionAllowsMultiple({ multiple: true }), true);
// explicit undefined is what a JSON payload with the key omitted actually gives
t("multiple undefined -> single select",mod.questionAllowsMultiple({ multiple: undefined }), false);
t("multiple absent is not truthy-by-accident", mod.questionAllowsMultiple({ multiple: 0 }), false);

// --- custom: the schema says default TRUE, so absent must NOT hide the input
t("custom absent  -> input shown",  mod.questionAllowsCustom({}), true);
t("custom true    -> input shown",  mod.questionAllowsCustom({ custom: true }), true);
t("custom false   -> input hidden", mod.questionAllowsCustom({ custom: false }), false);
t("custom null    -> input shown (only false hides it)",
  mod.questionAllowsCustom({ custom: null }), true);

// --- collectQuestionAnswers: the wire shape must not change
// Array<Array<string>>, one inner array per question, in order.
const g = (sel, custom) => ({ _selected: sel, _custom: { value: custom || "" } });
t("collect: one label per question",
  mod.collectQuestionAnswers([g(new Set(["Tool call timeline"]), "")]),
  [["Tool call timeline"]]);
t("collect: multiple selections preserved in a single-select group",
  mod.collectQuestionAnswers([g(new Set(["A", "B"]), "")]),
  [["A", "B"]]);
t("collect: custom text is appended to that question's answer",
  mod.collectQuestionAnswers([g(new Set(["Approval checkpoints"]), "Something else")]),
  [["Approval checkpoints", "Something else"]]);
t("collect: custom text alone is a valid answer",
  mod.collectQuestionAnswers([g(new Set(), "Write it down")]),
  [["Write it down"]]);
t("collect: whitespace-only custom text is dropped, not sent as blank",
  mod.collectQuestionAnswers([g(new Set(["B"]), "   ")]),
  [["B"]]);
t("collect: unanswered question yields an empty array, not a missing entry",
  mod.collectQuestionAnswers([g(new Set(["B"]), ""), g(new Set(), "")]),
  [["B"], []]);
t("collect: shape is Array<Array<string>> for three questions",
  mod.collectQuestionAnswers([g(new Set(["a"]), ""), g(new Set(["b", "c"]), ""), g(new Set(), "d")]),
  [["a"], ["b", "c"], ["d"]]);

// --- permission scope coercion. A string here used to throw on .join(),
// which killed the whole card render and parked the tool until timeout.
t("scope: array passes through", mod.permissionScopeList(["/tmp", "/var"]), ["/tmp", "/var"]);
t("scope: bare string becomes a one-item list", mod.permissionScopeList("/tmp"), ["/tmp"]);
t("scope: null becomes an empty list", mod.permissionScopeList(null), []);
t("scope: undefined becomes an empty list", mod.permissionScopeList(undefined), []);
t("scope: empty array stays empty", mod.permissionScopeList([]), []);
t("scope: a string joins without throwing", () => mod.permissionScopeList("/tmp").join(", "), "/tmp");
t("scope: a list joins as before", () => mod.permissionScopeList(["/a","/b"]).join(", "), "/a, /b");

let failed = 0;
for (const r of results) {
  process.stdout.write((r.ok ? "PASS" : "FAIL") + "\t" + r.name +
    (r.ok ? "" : "\n\tgot  " + r.got + "\n\twant " + r.want) + "\n");
  if (!r.ok) failed++;
}
process.stdout.write("TOTAL\t" + results.length + "\t" + failed + "\n");
JS

out=$(node "$WORK/run.js" "$WORK/helpers.js" 2>&1)
# node prints READY before evaluating anything, so a crash is distinguishable
# from "no assertions". Without this a SyntaxError counted as output and every
# assertion silently vanished.
if ! grep -q "^READY" <<<"$out"; then
  bad "the helpers evaluate in node" \
      "node failed before emitting READY: $(head -3 <<<"$out" | tr '\n' ' ')"
else
  ok "the helpers evaluate in node"
  tab=$'\t'
  n_assert=$(grep -cE "^(PASS|FAIL)${tab}" <<<"$out")
  if [ "$n_assert" -lt 20 ]; then
    bad "all assertions ran" "only $n_assert assertion lines came back (expected >= 20) — the test is not checking what it claims"
  else
    ok "all assertions ran ($n_assert)"
  fi
  while IFS=$'\t' read -r status name rest; do
    case "$status" in
      PASS) ok "$name" ;;
      FAIL) bad "$name" "$(awk -v n="$name" -F'\t' '$1=="FAIL" && $2==n {getline g; getline w; print g "\n        " w}' <<<"$out")" ;;
      TOTAL|READY) : ;;
    esac
  done <<<"$out"
fi

# --------------------------------------------- the renderer must use the helpers
echo
echo "=== the renderer actually consults the schema ==="
qs=$(python3 - "$JS" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
i = src.find("function addQuestionEntry")
j = src.find("function addPermissionEntry")
body = src[i:j] if j > i else src[i:i + 12000]
checks = [
    ("reads q.multiple", bool(re.search(r"questionAllowsMultiple\s*\(", body))),
    ("reads q.custom",   bool(re.search(r"questionAllowsCustom\s*\(", body))),
    ("collects via collectQuestionAnswers", bool(re.search(r"collectQuestionAnswers\s*\(", body))),
    ("no longer hardcodes a plum fill on options",
     not re.search(r'rgba\(201,\s*123,\s*141', body)),
    ("no longer mutates selection via style.background",
     not re.search(r"btn\.style\.background", body)),
]
for name, good in checks:
    print(("yes" if good else "no ") + "\t" + name)
PY
)
while IFS=$'\t' read -r good name; do
  [ "$good" = "yes" ] && ok "$name" || bad "$name" "not satisfied in addQuestionEntry"
done <<<"$qs"

echo
echo "=== the card has a stepper (Next / Back) ==="
step=$(python3 - "$JS" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
i = src.find("function addQuestionEntry")
j = src.find("function addPermissionEntry")
body = src[i:j] if j > i else src[i:i + 12000]
print("yes\tper-question step index exists" if re.search(r"currentIndex|stepIndex", body) else "no \tper-question step index exists")
print("yes\tBack control exists" if re.search(r'backBtn|"Back"', body) else "no \tBack control exists")
print("yes\tNext control exists" if re.search(r'nextBtn|"Next"', body) else "no \tNext control exists")
print("yes\tprogress label exists" if re.search(r'" of "', body) else "no \tprogress label exists")
PY
)
while IFS=$'\t' read -r good name; do
  [ "$good" = "yes" ] && ok "$name" || bad "$name" "missing from addQuestionEntry"
done <<<"$step"

# ------------------------------------------------- selection class vs the input
# REGRESSION: selecting a second option left the FIRST one still wearing the
# selected border. The cause is a DOM subtlety no pure-function test can see:
# in a radio group the browser unchecks the previous input natively, but
# `change` fires ONLY on the newly-checked input, so a handler that toggles
# just its own row never clears the old one. Observed in a real browser as
# rows=["SEL","SEL","---"] against a single checked radio.
#
# This drives the real addQuestionEntry against a DOM stub small enough to
# audit, and asserts the invariant directly: rows carrying `is-selected` must
# always equal the number of checked inputs.
echo
echo "=== the selected class follows the input, not the click ==="
python3 - "$JS" "$WORK/renderer.js" <<'PYDOM'
import sys
src = open(sys.argv[1]).read()
lines = src.split("\n")
def block(sig):
    s = next(k for k, l in enumerate(lines) if l.strip().startswith("function " + sig))
    ind = len(lines[s]) - len(lines[s].lstrip()); e = s
    for k in range(s + 1, len(lines)):
        l = lines[k]
        if l.strip() and (len(l) - len(l.lstrip())) <= ind:
            e = k; break
    return "\n".join(lines[s:e + 1])
need = ["questionAllowsMultiple", "questionAllowsCustom", "collectQuestionAnswers",
        "permissionScopeList", "addQuestionEntry"]
missing = [n for n in need if ("function " + n + "(") not in src]
if missing:
    print("MISSING:" + ",".join(missing)); sys.exit(3)
open(sys.argv[2], "w").write("\n".join(block(n) for n in need))
PYDOM
if [ $? = 3 ]; then
  bad "renderer extracted for the selection DOM test" "one of the card functions is missing"
else
  ok "renderer extracted for the selection DOM test"
  dom_out=$(node "$HERE/selection_dom_test.js" "$WORK/renderer.js" 2>&1)
  tab=$'\t'
  n_dom=0
  while IFS="$tab" read -r st name rest; do
    case "$st" in
      PASS) ok "$name"; n_dom=$((n_dom + 1)) ;;
      FAIL) bad "$name" "the selected class and the checked input disagree" ;;
    esac
  done <<<"$dom_out"
  if [ "$n_dom" -lt 4 ]; then
    bad "the selection DOM test exercised every move" \
        "only $n_dom step(s) reported (expected 4) — it is not testing what it claims"
  else
    ok "the selection DOM test exercised every move ($n_dom)"
  fi
fi

echo
echo "=================================="
echo "  $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
