// Regression harness for: selecting a second option left the FIRST one wearing
// the selected border.
//
// Root cause: in a radio group the browser unchecks the previous input
// natively, but `change` fires ONLY on the newly-checked input. A handler that
// toggles just its own row therefore never clears the old one, leaving
// rows=["SEL","SEL","---"] against a single checked radio.
//
// This drives the real addQuestionEntry against a DOM stub small enough to
// audit, then asserts the invariant: the number of rows carrying
// `is-selected` always equals the number of checked inputs.
const fs = require("fs");

function makeEl(tag) {
  const el = {
    tagName: tag, children: [], className: "", dataset: {}, style: {},
    _text: "", type: "", name: "", value: "", checked: false,
    disabled: false, placeholder: "", title: "", _h: {},
    appendChild(c) { this.children.push(c); return c; },
    remove() {}, scrollIntoView() {},
    addEventListener(ev, fn) { this._h[ev] = fn; },
    dispatch(ev) { if (this._h[ev]) this._h[ev]({ target: this }); },
    set textContent(v) { this._text = v; this.children = []; },
    get textContent() { return this._text; },
    set innerHTML(v) { this._html = v; },
    get innerHTML() { return this._html || ""; },
  };
  const set = new Set();
  el.classList = {
    add: (c) => set.add(c),
    remove: (c) => set.delete(c),
    contains: (c) => set.has(c),
    toggle: (c, on) => {
      const want = on === undefined ? !set.has(c) : !!on;
      if (want) set.add(c); else set.delete(c);
      return want;
    },
  };
  // Descendant search, so querySelectorAll(".qac-option") and
  // querySelector("input") actually resolve.
  //
  // Supports a single class (.foo) or a bare tag name (input). That is all the
  // real code uses here: the option re-sync reaches its control by TAG rather
  // than by the .radio/.checkbox class, so that renaming those classes again
  // cannot silently break the selected state. A selector this double cannot
  // parse resolves to nothing, which is how a rename broke this test once -
  // it reported "0 steps exercised" rather than failing loudly on the lookup.
  const matches = (node, sel) => {
    if (sel.startsWith(".")) {
      const cls = sel.slice(1);
      return String(node.className || "").split(/\s+/).includes(cls);
    }
    return String(node.tagName || "").toLowerCase() === sel.toLowerCase();
  };
  el.querySelectorAll = (sel) => {
    const out = [];
    (function walk(n) {
      for (const c of n.children) {
        if (matches(c, sel)) out.push(c);
        walk(c);
      }
    })(el);
    return out;
  };
  el.querySelector = (sel) => el.querySelectorAll(sel)[0] || null;
  return el;
}

global.document = {
  createElement: makeEl,
  getElementById: () => null,
  querySelector: () => null,
  querySelectorAll: () => [],
};
global.CSS = { escape: (s) => s };

const CONFIG = { ENDPOINT: "", QUESTION_PATH: "/q", PERMISSION_PATH: "/p" };
const authToken = "t";
let activeTier = 1;
const output = makeEl("div");
const noop = () => {};
global.isViewingTierChat = () => true;
global.markTierUnread = noop; global.notify = noop;
global.showThinking = noop; global.hideThinking = noop;
global.setChatLog = noop; global.relockSession = noop; global.renderReplyResult = noop;
global.fetch = () => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({}) });

eval(fs.readFileSync(process.argv[2], "utf8"));

const QUESTIONS = [{
  question: "Pick one",
  options: [{ label: "A" }, { label: "B" }, { label: "C" }],
}];
addQuestionEntry({ request_id: "r1", questions: QUESTIONS });

// entry > bubble; the options live deeper, so search the whole entry.
const entry = output.children[0];
const rows = entry.querySelectorAll(".qac-option");
if (rows.length !== 3) {
  process.stdout.write("FAIL\tshould render 3 option rows (got " + rows.length + ")\n");
  process.exit(0);
}
const inputs = rows.map((r) => r.querySelector("input"));
const selected = () => rows.filter((r) => r.classList.contains("is-selected")).length;
const checked = () => inputs.filter((i) => i.checked).length;

let bad = 0;
function step(name, choose) {
  // Reproduce what the BROWSER does to a radio group: checking one input
  // unchecks its siblings. The handler only ever hears about the new one.
  inputs.forEach((i, n) => { i.checked = (n === choose); });
  inputs[choose].dispatch("change");
  const s = selected(), c = checked();
  const ok = s === 1 && c === 1;
  if (!ok) bad++;
  process.stdout.write((ok ? "PASS" : "FAIL") + "\t" + name +
    "  (selected=" + s + " checked=" + c + ")\n");
}

step("select A", 0);
step("move A -> B", 1);
step("move B -> C", 2);
step("move C -> A", 0);
process.stdout.write("BAD\t" + bad + "\n");
