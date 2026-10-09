// jsdom-free DOM harness for the SIDEBAR SHELL: STRUCTURE and CASCADE.
//
// WHY THERE IS NO `require("jsdom")` HERE, since the design brief asked for it:
// jsdom is not a DEPENDENCY of this repo. It is not in flake.nix's devShells and
// not in any package.json here, so a suite requiring it could only ever report
// FAIL for anyone who has not happened to install it into a scratch directory
// outside the tree - which is a red suite by accident, not a verdict. The three
// .js suites in this directory all hand-roll their DOM for the same reason.
// Adding jsdom to the flake is the alternative and is a real change with its own
// blast radius, so it is left to whoever wants to make it, deliberately.
//
// WHAT THIS FILE IS. It answers questions you can answer by READING the sources:
// does the element exist, what classes and attributes does it carry, what is its
// position in the tree, and - by parsing the stylesheet - what does the CASCADE
// resolve to. It observes no pixels: no widths, no heights, no stacking, no
// colours as rendered. That division of labour is why the responsive assertions
// near the bottom read rule bodies out of a `max-width: 640px` block instead of
// measuring a rendered box, and it is the same technique test_scales.sh section 4
// uses for the header-height relationship.
//
// THE HALF THAT EXECUTES CODE LIVES ELSEWHERE. nav_focus_effect_test.js holds
// the assertions that CALL the shipped overlay functions and check what happened
// - where focus landed, which hidden flags flipped, whether onClose ran. This
// file cannot do that: it stages state by reading the source, and a staged state
// is a claim about the source, not an observation of it. That is not a
// preference. Round 1 proved the difference: the focus bug it fixed was invisible
// here and needed an assertion that ran the real open path.
//
// THE PARSER IS NOT A FAKE BEHAVIOUR. The trap recorded about the other stubs is
// a stub that performs the very thing under test, so the assertion goes green
// with the real code deleted. This one only turns text into nodes; it never
// decides whether a class is present, an attribute matches, or which rule wins.
// Every assertion in BOTH halves was mutation-tested against the real sources.

const fs = require("fs");
const path = require("path");

const HERE = __dirname;
const SRC = path.join(HERE, "..");

const htmlPath = path.join(SRC, "perla-companion.html");
const cssPath = path.join(SRC, "perla-companion.html").replace(/\.html$/, ".css");
const jsPath = path.join(SRC, "perla-companion.js");

let pass = 0;
let fail = 0;
const ok = (n) => { console.log("  PASS  " + n); pass++; };
const bad = (n, d) => { console.log("  FAIL  " + n); console.log("        " + d); fail++; };

// ---------------------------------------------------------------------------
// A minimal HTML parser. Enough for this document: elements, attributes, void
// elements, self-closing tags (the SVG leaf shapes), comments, the doctype and
// raw-text elements. Enough is a claim, so it is CHECKED: `the whole document
// parsed` below asserts the parse produced the whole document, because a parser
// that silently bails at the first malformed-looking construct would report every
// "not found" below as a clean structural failure and read like a real result.
//
// The node factory carries two browser behaviours - focus() is a no-op inside a
// [hidden] subtree, and blur() moves focus to the document - which
// nav_focus_effect_test.js depends on and this file never exercises. They are
// documented at the methods rather than here, because that is where a reader
// deciding whether the fake is honest will look.
// ---------------------------------------------------------------------------

const VOID = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input",
  "link", "meta", "param", "source", "track", "wbr"]);
const RAWTEXT = new Set(["script", "style", "textarea", "title"]);

const ATTR_RE = /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;

function makeNode(tagName, attrs) {
  const node = {
    tagName: tagName.toLowerCase(),
    attrs: attrs,
    classes: new Set((attrs["class"] || "").split(/\s+/).filter(Boolean)),
    children: [],
    parent: null,
    // `hidden` is a PROPERTY in the app (`el.hidden = false`, `b.hidden = open`)
    // and an ATTRIBUTE in the markup. Both readings have to agree or
    // `closest("[hidden]")` answers a question nobody asked, so it is backed by
    // the attribute rather than shadowed by an own property.
    get hidden() { return "hidden" in this.attrs; },
    set hidden(v) {
      if (v) this.attrs.hidden = "";
      else delete this.attrs.hidden;
    },
    // Browser-faithful about TWO things, and both are about focus().
    //
    // focus() on an element inside a [hidden] subtree is a NO-OP, not a move.
    // jsdom sets activeElement regardless of visibility, which is why a jsdom
    // smoke test reported "focus moved into the sheet" green while the shipped
    // code was focusing a display:none button.
    //
    // blur() is its counterpart and exists for the same reason: it moves focus
    // to nothing (the document), which is what releaseSidebarFocus() falls back
    // to when the transcript is not there to take it. It is documented here
    // because that is where a reader deciding whether the fake is honest will
    // look, and because the header of nav_focus_effect_test.js says "exactly
    // ONE thing" - which was true when it was written and is not now.
    focus() {
      if (!this.closest("[hidden]")) focusSinks.activeElement = this;
    },
    blur() {
      focusSinks.activeElement = null;
    },
    // List bookkeeping only - no policy in here, so a harness that moves nodes
    // around is not testing these four lines but the shipped code's use of them.
    // parent/children are already the single source of truth above.
    get firstChild() { return this.children[0] || null; },
    appendChild(child) {
      if (child.parent) child.parent.children.splice(child.parent.children.indexOf(child), 1);
      child.parent = this;
      this.children.push(child);
      return child;
    },
    removeChild(child) {
      const i = this.children.indexOf(child);
      if (i !== -1) this.children.splice(i, 1);
      child.parent = null;
      return child;
    },
    // Descendants only, like the real API: queryAll never returns the root.
    querySelectorAll(sel) { return queryAll(this, sel); },
    querySelector(sel) { return queryAll(this, sel)[0] || null; },
    closest(sel) { return closest(this, sel); },
    // Attribute write, because syncSidebarSheetState() - the shipped function
    // the other half calls to reach the open state - sets `aria-expanded` this
    // way. Backed by the same attrs map `hidden` uses, so `getAttribute` and the
    // `[aria-expanded="…"]` matcher see one truth.
    setAttribute(name, value) { this.attrs[name.toLowerCase()] = String(value); },
    getAttribute(name) {
      const v = this.attrs[name.toLowerCase()];
      return v === undefined ? null : v;
    },
    // Added when setDestination was first RUN rather than only read. It clears
    // the attribute for real - delete the key - so `[aria-current="page"]` and
    // `getAttribute` see one truth, the same contract setAttribute already has.
    // A no-op here would have been the dangerous kind of stub: setDestination
    // REMOVES aria-current from the four rows that are not the destination, and a
    // removal that did nothing would leave every one of them claiming to be the
    // current page while the assertions read green.
    removeAttribute(name) { delete this.attrs[name.toLowerCase()]; },
    // Direct text content, accumulated by the parser from the source BETWEEN
    // tags. Added for one assertion - the rail tooltips restate each row's label
    // in `data-tooltip`, and the only way to check the two agree is to read the
    // label. Element text is not modelled (there is no text node), so this is
    // deliberately only ever read as `el.text` on a leaf, and asking for
    // `el.textContent` would return undefined rather than a wrong answer.
    text: "",
    // Is the pointer over this element right now? `:hover` was the one piece of
    // the rail's behaviour no assertion could reach, because nothing dispatches a
    // pointer and a synthetic `el.click()` leaves the mouse wherever it was -
    // which is exactly the gap that let Item 4 ship: toggleSidebar() reads
    // `sidebar.matches(":hover")` to decide whether to arm the hover lock, and
    // without this the harness would throw rather than report.
    //
    // It is a SETTABLE property, not a computed one, because there is nothing to
    // compute it from: the harness stages hover state the way a real user creates
    // it, by moving a pointer, and every assertion that reads it is reading a
    // state the test put there on purpose. `:hover` in `matchesOne` below is the
    // only thing that reads it.
    hoverState: false,
    // Selector matching, delegating to the same `matches()` the parser's own
    // queryAll uses, so a rule about "does this element match X" cannot be
    // answered by a second implementation that could disagree with it. Needed
    // because the shipped `toggleSidebar()` calls `sidebar.matches(":hover")`.
    matches(sel) { return matches(this, sel); },
    // Listener bookkeeping. The shipped code binds exactly one listener on the
    // sidebar (`pointerleave`, which clears the hover lock) and the effect
    // harness has to fire it, so this is a real registry rather than a no-op:
    // `addEventListener` that recorded nothing and `__fire` that called nothing
    // would let the clearing assertion pass while the shipped listener was
    // never bound at all - the exact class of stub this file's header warns
    // about, and the reason both halves exist here.
    _listeners: Object.create(null),
    addEventListener(type, fn) {
      (this._listeners[type] || (this._listeners[type] = [])).push(fn);
    },
    removeEventListener(type, fn) {
      const list = this._listeners[type];
      if (!list) return;
      const i = list.indexOf(fn);
      if (i !== -1) list.splice(i, 1);
    },
    // Dispatch, for the harness only. Not part of the DOM surface the app uses,
    // and named so that it is obvious at every call site that this is the test
    // turning an event loose rather than the browser.
    __fire(type, ev) {
      for (const fn of (this._listeners[type] || []).slice()) fn.call(this, ev || { type: type });
    },
  };
  // `dataset` is a DOMMap, not a bag of own properties: `el.dataset.collapsed`
  // reads and writes the `data-collapsed` ATTRIBUTE, and that contract is the
  // whole of the collapsed state - `.sidebar[data-collapsed="true"]` and
  // `.app[data-collapsed="true"]` are the only two selectors that exist for it,
  // and applySidebarCollapsed() is the only thing that writes either. A `dataset`
  // that merely held a JavaScript property would let every effect assertion pass
  // while nothing rendered, so this goes through the same `attrs` map `hidden`,
  // `setAttribute` and `getAttribute` already use - one truth, four doors.
  const camelToAttr = (k) => "data-" + String(k).replace(/[A-Z]/g, (c) => "-" + c.toLowerCase());
  node.dataset = new Proxy({}, {
    get: (_t, k) => node.attrs[camelToAttr(k)],
    set: (_t, k, v) => { node.attrs[camelToAttr(k)] = String(v); return true; },
    has: (_t, k) => camelToAttr(k) in node.attrs,
    deleteProperty: (_t, k) => { delete node.attrs[camelToAttr(k)]; return true; },
  });
  return node;
}

// Where focus() would land, if it lands anywhere. Module-level so makeNode's
// closure does not have to carry it.
const focusSinks = { activeElement: null };

// Index just past the `>` that closes the tag starting at `start`, skipping any
// `>` inside a quoted attribute value. Quote-aware because an attribute value
// MAY contain one and an unquoted scan would end the tag early on any that does,
// truncating every attribute after it. Verified directly against the parser
// rather than assumed: parsing `<button title="a > b" id="x" aria-label="...">`
// yields all three attributes intact. No attribute value in
// perla-companion.html contains a `>` today, so this is defence against a future
// value doing so - not a fix for one that did.
function tagEnd(src, start) {
  let quote = null;
  for (let i = start + 1; i < src.length; i++) {
    const c = src[i];
    if (quote) {
      if (c === quote) quote = null;
    } else if (c === '"' || c === "'") {
      quote = c;
    } else if (c === ">") {
      return i + 1;
    }
  }
  return -1;
}

function parseAttrs(inner) {
  const attrs = {};
  let m;
  ATTR_RE.lastIndex = 0;
  while ((m = ATTR_RE.exec(inner)) !== null) {
    const name = m[1].toLowerCase();
    if (!(name in attrs)) attrs[name] = m[2] !== undefined ? m[2]
      : m[3] !== undefined ? m[3] : m[4] !== undefined ? m[4] : "";
  }
  return attrs;
}

function parseHTML(src) {
  const root = makeNode("#root", {});
  let node = root;
  let i = 0;
  while (i < src.length) {
    const lt = src.indexOf("<", i);
    if (lt === -1) break;
    // Text between tags belongs to the element we are currently INSIDE. Only ever
    // read on leaves - see makeNode's `text` - but accumulating it here rather
    // than post-hoc keeps the parser honest: it records what the source says, and
    // decides nothing about which span is the label.
    const between = src.slice(i, lt).trim();
    if (between) node.text += between;
    if (src.startsWith("<!--", lt)) {
      const end = src.indexOf("-->", lt);
      if (end === -1) break;
      i = end + 3;
      continue;
    }
    if (src.startsWith("<!", lt) || src.startsWith("<?", lt)) {
      const end = src.indexOf(">", lt);
      if (end === -1) break;
      i = end + 1;
      continue;
    }
    if (src.startsWith("</", lt)) {
      const end = src.indexOf(">", lt);
      if (end === -1) break;
      const name = src.slice(lt + 2, end).trim().toLowerCase();
      let n = node;
      while (n && n.tagName !== name) n = n.parent;
      if (n && n.parent) node = n.parent;
      i = end + 1;
      continue;
    }
    const end = tagEnd(src, lt);
    if (end === -1) break;
    let inner = src.slice(lt + 1, end - 1);
    const selfClosing = inner.endsWith("/");
    if (selfClosing) inner = inner.slice(0, -1);
    const sp = inner.search(/[\s]/);
    const tagName = (sp === -1 ? inner : inner.slice(0, sp)).toLowerCase();
    if (!/^[a-z][a-z0-9-]*$/.test(tagName)) { i = end; continue; }
    const attrs = parseAttrs(sp === -1 ? "" : inner.slice(sp));
    const el = makeNode(tagName, attrs);
    el.parent = node;
    node.children.push(el);
    if (RAWTEXT.has(el.tagName)) {
      const close = src.toLowerCase().indexOf("</" + el.tagName, end);
      if (close === -1) break;
      const gt = src.indexOf(">", close);
      if (gt === -1) break;
      i = gt + 1;
      continue;
    }
    if (!VOID.has(el.tagName) && !selfClosing) node = el;
    i = end;
  }
  return root;
}

// Selector support: `#id`, `.class`, `[attr]`, `[attr="value"]`, a bare tag, and
// comma-separated lists of those. Compound selectors ("div.foo") and
// combinators are deliberately NOT supported - nothing here needs them, and a
// silently-wrong matcher is worse than one that cannot express the question.
function matchesOne(el, sel) {
  sel = sel.trim();
  if (!sel) return false;
  if (sel.startsWith("#")) return el.attrs.id === sel.slice(1);
  if (sel.startsWith(".")) return el.classes.has(sel.slice(1));
  // `:hover` is the one pseudo-class with a real state behind it here, because
  // toggleSidebar() branches on it. Everything else falls through to the tag
  // comparison below and answers false, which is the honest answer for a fake
  // that models no dynamic state - and it matters that it is false rather than
  // an exception, because "no hover" is the common case the effect harness
  // stages for the keyboard collapse.
  if (sel === ":hover") return el.hoverState === true;
  if (sel.startsWith("[")) {
    const m = /^\[([^\]=]+)(?:=["']?([^\]"']*)["']?)?\]$/.exec(sel);
    if (!m) return false;
    if (!(m[1].toLowerCase() in el.attrs)) return false;
    return m[2] === undefined || el.attrs[m[1].toLowerCase()] === m[2];
  }
  return el.tagName === sel.toLowerCase();
}

function matches(el, sel) {
  return sel.split(",").some((s) => matchesOne(el, s));
}

function walk(root, out) {
  for (const c of root.children) { out.push(c); walk(c, out); }
  return out;
}

function queryAll(root, sel) {
  return walk(root, []).filter((el) => matches(el, sel));
}

function query(root, sel) {
  return queryAll(root, sel)[0] || null;
}

function closest(el, sel) {
  let n = el;
  while (n && n.tagName !== "#root") {
    if (matches(n, sel)) return n;
    n = n.parent;
  }
  return null;
}

function contains(ancestor, el) {
  let n = el;
  while (n) {
    if (n === ancestor) return true;
    n = n.parent;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Exports, and the reason for the early return below.
//
// nav_focus_effect_test.js REQUIRES this file for the parser, the query helpers
// and `focusSinks` - the same `[hidden]` semantics have to mean one thing in both
// halves, and two parsers would be two definitions of it. So the parser is
// exported, and everything below the return is the ASSERTION half, which runs
// only when this file is the entry point. `require.main === module` is the whole
// of the mechanism; the wrapper runs both files as entry points, so both halves
// execute exactly once.
// ---------------------------------------------------------------------------

module.exports = {
  parseHTML,
  query,
  queryAll,
  closest,
  contains,
  walk,
  makeNode,
  focusSinks,
};

if (require.main !== module) return;

// ---------------------------------------------------------------------------
// Read the sources.
// ---------------------------------------------------------------------------

const htmlSrc = fs.readFileSync(htmlPath, "utf8");
const cssSrc = fs.readFileSync(cssPath, "utf8");
const jsSrc = fs.readFileSync(jsPath, "utf8");

// The wrapper passes the script path as argv[2]. Assert it resolves to the file
// this harness read, so a wrapper that drifts to a different copy fails loudly
// instead of reporting on one tree while claiming another.
if (process.argv[2]) {
  let same = false;
  try {
    same = fs.realpathSync(process.argv[2]) === fs.realpathSync(jsPath);
  } catch (e) {
    same = false;
  }
  if (same) {
    ok("argv[2] is the same perla-companion.js this harness read");
  } else {
    bad("argv[2] is the same perla-companion.js this harness read",
      "wrapper passed " + process.argv[2] + ", harness read " + jsPath);
  }
}

const doc = parseHTML(htmlSrc);
const all = walk(doc, []);

// SCAN FLOOR. A parser that stopped early would make every "not found" below
// indistinguishable from a genuine structural failure, so the size of the parse
// is asserted in its own right. The real figure is printed; this sits far below
// it and far above zero.
if (all.length > 300) {
  ok("the whole document parsed (" + all.length + " elements)");
} else {
  bad("the whole document parsed", "only " + all.length +
    " elements - the parser bailed early, so every result below is untrustworthy");
}

const app = query(doc, "#app");
if (app) ok("#app exists"); else bad("#app exists", "not found in the HTML");

// ---------------------------------------------------------------------------
// 1. The shell is a GRID with a sidebar column, not a centred card.
// ---------------------------------------------------------------------------

const sidebar = query(doc, ".sidebar");
if (sidebar) ok(".sidebar exists"); else bad(".sidebar exists", "not found in the HTML");

if (app && sidebar && contains(app, sidebar)) {
  ok(".sidebar is inside #app (it is a grid column, not an overlay)");
} else {
  bad(".sidebar is inside #app", "not a descendant of #app");
}

const appContent = query(doc, ".app-content");
if (app && appContent && contains(app, appContent)) {
  ok(".app-content is inside #app");
} else {
  bad(".app-content is inside #app", "the second grid column is missing");
}

const appCard = query(doc, ".app-card");
if (!appCard) {
  bad(".app-card exists", "no element carries the class - the content column runs edge to edge again");
}

if (sidebar && appContent && sidebar.parent === appContent.parent &&
    app.children.indexOf(sidebar) < app.children.indexOf(appContent)) {
  ok("the sidebar comes before .app-content, so it is the FIRST grid column");
} else {
  bad("the sidebar comes before .app-content", "order decides which column each lands in");
}

// #app is a grid container, so every in-flow child is a grid item. The four
// secondary surfaces and .content-wrap are IN FLOW (.dropdown-panel sets no
// position), so a panel left as a direct child of #app would be auto-placed into
// a grid cell and land somewhere the author never chose. That is the failure
// this guards, and it is invisible until an overlay is opened on a phone.
//
// TWO reasons each of these has to be under .app-content, which is why they are
// checked together rather than as two lists:
//
//   1. GRID. .app is a grid container, and the four .dropdown-panel surfaces set
//      no `position`, so as direct children of #app they become grid items and
//      get auto-placed into a column the author never chose.
//   2. CONTAINMENT. #drivePanel is `position: absolute`; moved out of the
//      content column it resolves against the VIEWPORT and covers the nav column
//      again, which is the regression its own rule was changed to fix.
//
// CHANGED: they are now children of .app-card, not of .app-content directly.
// .app-card is a new, STATIC wrapper, so (2) is unaffected - the containing block
// is still .app-content, and the assertions below say so rather than assuming it.
// (1) is also unaffected and for a stronger reason now: .app-card is the only
// in-flow child of .app-content, so nothing can auto-place out of it any more
// even if a surface were re-parented to .app-content itself.
//
// The comment used to argue (2) while the assertion only checked (1) - the
// declaration was right and the test was narrower than the claim.
// Mutation: re-parent #drivePanel out of .app-card -> red here.
// Mutation: delete .app-card -> red here.
// Mutation: remove `position: relative` from .app-content -> red below, and here.
const inFlowPanels = ["#historyPanel", "#remindersBar", "#drivePanel", "#quickActionsPanel",
  ".content-wrap"];
let stray = [];
for (const sel of inFlowPanels) {
  const el = query(doc, sel);
  if (!el) { stray.push(sel + " (missing)"); continue; }
  if (!appCard || el.parent !== appCard) stray.push(sel);
}
if (stray.length === 0) {
  ok("the five surfaces are children of .app-card - not grid items of #app, and inside the containing block");
} else {
  bad("the five surfaces are children of .app-card", "stray: " + stray.join(", "));
}

// And the chain itself: the card has to BE inside the content column. Asserting
// only the leaf parents would pass with .app-card anywhere in the document -
// including as a sibling of #app, which is where the mobile sheet is not allowed
// to be. The other half - that .app-card is STATIC, so the column stays the
// containing block for #drivePanel - needs the parsed stylesheet and lives in
// section 7, where that parser exists.
const cardInContent = !!(appCard && appContent && appCard.parent === appContent);
if (cardInContent) {
  ok(".app-card is inside .app-content - the centred window, not a third grid column");
} else {
  bad(".app-card is inside .app-content",
    "parent: " + (appCard && appCard.parent ? (appCard.parent.classes && [...appCard.parent.classes].join(".") || appCard.parent.tagName) : "<none>") +
    " - as a direct child of #app the card would be auto-placed into a grid track");
}

// .content-wrap must stay a SIBLING of #quickActionsPanel: the stylesheet hides
// it with `#quickActionsPanel:not([hidden]) ~ .content-wrap`, so re-parenting one
// without the other would silently leave the chat visible under Quick Actions.
const qaPanel = query(doc, "#quickActionsPanel");
const contentWrap = query(doc, ".content-wrap");
if (qaPanel && contentWrap && qaPanel.parent === contentWrap.parent) {
  ok("#quickActionsPanel and .content-wrap are still siblings (the ~ hide rule needs it)");
} else {
  bad("#quickActionsPanel and .content-wrap are still siblings",
    "the `~` selector that hides .content-wrap under Quick Actions resolves to nothing");
}

// ---------------------------------------------------------------------------
// 2. Every nav destination is present and carries a stable data attribute. The
//    router keys on the attribute; text labels may change, the key may not.
// ---------------------------------------------------------------------------

const DESTINATIONS = ["chat", "drive", "history", "reminders", "actions"];
const rows = queryAll(doc, "[data-destination]");
const found = rows.map((el) => el.attrs["data-destination"]);
const missing = DESTINATIONS.filter((d) => !found.includes(d));
if (missing.length === 0) {
  ok("all five destinations are present (" + found.join(", ") + ")");
} else {
  bad("all five destinations are present", "missing: " + missing.join(", ") + "; found: " + found.join(", "));
}

const dupes = DESTINATIONS.filter((d) => found.filter((f) => f === d).length > 1);
if (dupes.length === 0) {
  ok("no destination is declared twice");
} else {
  bad("no destination is declared twice", "duplicated: " + dupes.join(", "));
}

const badRows = rows.filter((el) => el.tagName !== "button" || el.attrs.type !== "button");
if (rows.length === 5 && badRows.length === 0) {
  ok("all five destination rows are real <button type=button>");
} else if (badRows.length > 0) {
  bad("all five destination rows are real <button type=button>",
    badRows.length + " row(s) are not, or there are " + rows.length + " rows rather than 5");
} else {
  bad("all five destination rows are real <button type=button>", "no rows found");
}

// aria-current names the destination that is on screen. Exactly one row may
// claim it - two is how a screen reader announces "current page" twice.
const current = rows.filter((el) => el.attrs["aria-current"] === "page");
if (current.length === 1 && current[0].attrs["data-destination"] === "chat") {
  ok("exactly one destination starts aria-current=page, and it is chat");
} else {
  bad("exactly one destination starts aria-current=page",
    current.length + " row(s) claim it" +
    (current.length ? ": " + current.map((e) => e.attrs["data-destination"]).join(", ") : ""));
}

// ---------------------------------------------------------------------------
// 3. Nothing #appMenu could reach was dropped with it.
//    This is the assertion the task actually turns on: eight menu rows became
//    sidebar rows, and a capability that quietly vanished has no other symptom.
// ---------------------------------------------------------------------------

// tierBadge, tierTimer and statusDot were on this list and are not any more: the
// user asked for the tier pill, the Full Mode countdown and the connection dot to
// be removed, and they are gone from the markup. They are named in the HTML's own
// comment at the foot of .sidebar-footer, and the JS records what each one's
// removal cost, so the history is where it can be read rather than here - which is
// also why this list is shorter without being weaker: every id BELOW still has to
// be present and still has to live inside .sidebar.
const CARRIED = [
  "tier1Btn", "tier2Btn", "tier1Badge", "tier2Badge",
  "quickActionsBtn", "remindersBtn", "driveBtn", "historyBtn",
  "clearChatBtn", "checkSessionBtn", "restartServiceBtn",
  "brandMark",
];
const lostIds = CARRIED.filter((id) => !query(doc, "#" + id));
if (lostIds.length === 0) {
  ok("every id #appMenu carried survives in the sidebar (" + CARRIED.length + " checked)");
} else {
  bad("every id #appMenu carried survives in the sidebar",
    "gone with the menu: " + lostIds.join(", "));
}

const stranded = CARRIED.filter((id) => {
  const el = query(doc, "#" + id);
  return el && !contains(sidebar, el);
});
if (stranded.length === 0) {
  ok("every carried id lives inside .sidebar (nothing was left outside the shell)");
} else {
  bad("every carried id lives inside .sidebar", "outside it: " + stranded.join(", "));
}

// The tier switcher is the FOOTER's job and is now its ONLY content: the status
// line - the tier pill, the Full Mode countdown and the connection dot - was
// removed at the user's request.
const footer = sidebar ? query(sidebar, ".sidebar-footer") : null;
const tierGroup = sidebar ? query(sidebar, "#sidebarTier") : null;
if (footer && tierGroup && footer === tierGroup.parent) {
  ok("#sidebarTier is the first block of .sidebar-footer");
} else {
  bad("#sidebarTier is the first block of .sidebar-footer", "the tier switcher has no home");
}

// THE REMOVAL, asserted as an absence rather than left to a reader. Every one of
// these three is a case where "the JS still writes to it" would throw on the first
// unlock - tierBadge.textContent on a null, tierTimerEl.hidden on a null,
// statusDot.className on a null - so a partial removal is a hard crash rather than
// a silent one, and this is the check that says the removal finished.
//
// Asked as a set rather than three separate assertions because the failure they
// share is one failure: a markup edit that put any of them back, or that removed
// only some of them, and the message needs to say which.
const REMOVED_STATUS = ["tierBadge", "tierTimer", "statusDot", "statusIndicator"];
const statusSurvivors = REMOVED_STATUS.filter((id) => query(doc, "#" + id));
const classSurvivors = ["status-indicator", "status-dot"]
  .filter((cls) => queryAll(doc, "." + cls).length > 0);
if (statusSurvivors.length === 0 && classSurvivors.length === 0) {
  ok("the tier pill, the Full Mode countdown and the connection dot are gone from the markup - " +
     REMOVED_STATUS.length + " ids and 2 classes, and no JS writer can be left pointing at a null");
} else {
  bad("the status row's elements are gone from the markup",
    "still present: " + (statusSurvivors.concat(classSurvivors).join(", ")) +
    " - the JS writes tierBadge.textContent, tierTimerEl.hidden and statusDot.className, " +
    "so any of these back in the markup with its writer removed (or the reverse) is a crash or a dead line");
}

// .sidebar is a flex column, so its three regions are order-sensitive: a header
// below the content would push the nav off the top of the rail.
if (sidebar) {
  const regions = sidebar.children;
  const tags = regions.map((r) => (r.classes.has("sidebar-header") ? "header"
    : r.classes.has("sidebar-content") ? "content"
    : r.classes.has("sidebar-footer") ? "footer" : "?" + r.tagName));
  if (tags.join(",") === "header,content,footer") {
    ok(".sidebar's three regions are header, content, footer - in that order");
  } else {
    bad(".sidebar's three regions are header, content, footer",
      "got: " + tags.join(", "));
  }
  const content = query(sidebar, ".sidebar-content");
  if (content && content.classes.has("scroll-area")) {
    ok(".sidebar-content carries .scroll-area (one scrollbar recipe, not two)");
  } else {
    bad(".sidebar-content carries .scroll-area", "the nav list cannot scroll a long session group");
  }
}

// ---------------------------------------------------------------------------
// 4. The hamburger is GONE. Two navigation affordances at once - one of them,
//    the one a phone actually used - is the regression this task exists to stop.
// ---------------------------------------------------------------------------

if (query(doc, "#menuBtn")) {
  bad("the hamburger button is removed", "#menuBtn still present");
} else {
  ok("the hamburger button is removed");
}
if (query(doc, ".menu-btn")) {
  bad("the .menu-btn chrome class is removed", "the dead hamburger rule is still attached to something");
} else {
  ok("the .menu-btn chrome class is removed");
}

// #appMenu is deleted only because its eleven callers were found and dealt with:
// four became destination rows, two moved to the footer, three became the
// Session group. If any of them had stayed, this element would have to stay too.
if (query(doc, "#appMenu")) {
  bad("#appMenu is gone (every row moved into the sidebar)", "a second navigation surface still exists");
} else {
  ok("#appMenu is gone (every row moved into the sidebar)");
}

// ONE hairline down the sidebar's trailing edge, not two. .sidebar draws it with
// `border-right`; .sidebar-rail is a registered primitive that draws the same line
// as an absolutely-positioned overlay and still has no consumer. The two were
// deliberately reconciled in favour of `border-right` (see the why-comment on
// .sidebar-rail), and this is what stops the other half quietly coming back -
// which would be a silent one-pixel change, not a broken layout, so nothing else
// in this repo would notice.
// Mutation: add `.sidebar-rail` to the .sidebar element -> red.
const railUsers = queryAll(doc, ".sidebar-rail");
if (railUsers.length === 0) {
  ok("no markup carries .sidebar-rail - the sidebar's own border-right is the only hairline");
} else {
  bad("no markup carries .sidebar-rail",
    railUsers.length + " element(s) - it would draw the same 1px line a second time, over the same --border, at the same edge");
}

// AND THE RULE IS GONE TOO, which is the other half and was the second half of a
// decision rather than an omission. Task 6 shipped `.sidebar-rail` registered,
// unreferenced and inert, with a twenty-line comment explaining why that was a
// defensible deferral - and this layer made the deferral stale: the rail is out of
// the flow now, so `position: relative` on `.sidebar` had nothing left to host
// and the recorded justification ("an absolutely-positioned overlay costs no
// layout width, which matters if the rail must measure exactly --sidebar-width")
// described a rail that no longer exists, because the collapsed rail is supposed
// to measure --sidebar-rail-width and the centring arithmetic depends on it.
//
// Deleting the rule and its two registry entries is the decision; this is what
// makes it enforceable. A comment saying a rule is not wanted is a request, and
// nothing caught it coming back - mutation m45 restored the whole rule and left
// all four suites green.
// Mutation: restore `.sidebar-rail { … }` -> red.
// Mutation: restore it plus `position: relative` on .sidebar -> red, twice.
// Read off the raw source with the comments stripped, because this assertion
// lives in the structure half - above `ruleBodies`/`selBodies`, which belong to
// the cascade section further down - and a question about the ABSENCE of a rule
// is answerable without parsing the rules that are there.
const railCss = cssSrc.replace(/\/\*[\s\S]*?\*\//g, "");
const railRuleInSheet = /\.sidebar-rail\s*\{/.test(railCss);
if (!railRuleInSheet) {
  ok(".sidebar-rail's rule is struck too - nothing in the stylesheet declares the class at all");
} else {
  bad(".sidebar-rail's rule is struck",
    "a `.sidebar-rail { … }` rule is back in the stylesheet" +
    (/\.sidebar\s*\{[^}]*position:\s*relative/.test(railCss)
      ? ", and `position: relative` is back on .sidebar to host it" : ""));
}

// ---------------------------------------------------------------------------
// 5. The mobile trigger and the sheet.
// ---------------------------------------------------------------------------

const trigger = query(doc, ".sidebar-trigger");
if (!trigger) {
  bad(".sidebar-trigger exists", "not found");
} else {
  ok(".sidebar-trigger exists");
  if (trigger.attrs["aria-expanded"] === "false") {
    ok(".sidebar-trigger starts aria-expanded=false");
  } else {
    bad(".sidebar-trigger starts aria-expanded=false",
      "got " + trigger.attrs["aria-expanded"]);
  }
  if (trigger.attrs["aria-controls"] === "sidebar") {
    ok(".sidebar-trigger points at the sidebar via aria-controls");
  } else {
    bad(".sidebar-trigger points at the sidebar via aria-controls",
      "got " + trigger.attrs["aria-controls"]);
  }
  if (trigger.tagName === "button" && trigger.attrs.type === "button") {
    ok(".sidebar-trigger is a real <button type=button>");
  } else {
    bad(".sidebar-trigger is a real <button type=button>", "got <" + trigger.tagName + ">");
  }
  if (trigger.attrs.id === "sidebarTrigger") {
    ok(".sidebar-trigger is #sidebarTrigger (the id the JS looks up)");
  } else {
    bad(".sidebar-trigger is #sidebarTrigger", 'got id="' + trigger.attrs.id + '"');
  }
  const header = query(doc, ".app-header");
  if (header && contains(header, trigger)) {
    ok("the trigger lives in the header, not in the sidebar");
  } else {
    bad("the trigger lives in the header", "a trigger outside the header is not a header affordance");
  }
}

// The sheet overlays the whole viewport, so it must NOT be a grid item of #app.
// An element that is both a fixed overlay and a grid column is laid out by the
// grid and then taken out of flow, which works by accident until the grid has
// two tracks.
const sheet = query(doc, "#sidebarSheet");
const overlay = query(doc, "#sidebarOverlay");
if (sheet && app && !contains(app, sheet)) {
  ok("#sidebarSheet is a sibling of #app, not a grid item of it");
} else {
  bad("#sidebarSheet is a sibling of #app", "found inside the grid" + (sheet ? "" : " (missing)"));
}
if (sheet && sheet.classes.has("sheet")) {
  ok("#sidebarSheet carries .sheet");
} else {
  bad("#sidebarSheet carries .sheet", "the mobile nav would render unpositioned");
}
if (sheet && sheet.attrs.role === "dialog" && sheet.attrs["aria-modal"] === "true") {
  ok("#sidebarSheet is a modal dialog to assistive tech");
} else {
  bad("#sidebarSheet is a modal dialog to assistive tech",
    'got role="' + (sheet ? sheet.attrs.role : "?") + '" aria-modal="' +
    (sheet ? sheet.attrs["aria-modal"] : "?") + '"');
}
if (sheet && "hidden" in sheet.attrs) {
  ok("#sidebarSheet starts hidden");
} else {
  bad("#sidebarSheet starts hidden", "an un-hidden sheet covers the page on load");
}
if (overlay && overlay.classes.has("sheet-overlay") && "hidden" in overlay.attrs) {
  ok("#sidebarOverlay is a .sheet-overlay and starts hidden");
} else {
  bad("#sidebarOverlay is a .sheet-overlay and starts hidden",
    "the scrim would be painted over the whole viewport on load");
}

// ---------------------------------------------------------------------------
// 6. One Escape dispatcher, walking an overlay stack top-down. The old code had
//    two `document` keydown listeners and both fired on the same press, so a
//    single Escape closed the lightbox AND the file-viewer modal behind it.
//    Whether the stack's functions WORK is asserted in nav_focus_effect_test.js,
//    which calls them; this half proves they are spelled as claimed.
// ---------------------------------------------------------------------------

if (/overlayStack/.test(jsSrc) && /closeTopOverlay/.test(jsSrc) &&
    /pushOverlay/.test(jsSrc) && /popOverlay/.test(jsSrc) &&
    /let overlayStack = \[\]/.test(jsSrc)) {
  ok("the overlay stack exists in the JS (push/pop/closeTop over one array)");
} else {
  bad("the overlay stack exists in the JS",
    "overlayStack / pushOverlay / popOverlay / closeTopOverlay not found, or overlayStack is not a real array - the names alone would match a stack that never unwinds");
}

// closeTopOverlay must be the pop, not a shrug. `return false` in its body is a
// stack that never closes: Escape falls straight through to the fixed overlays,
// so a sheet stays open while the lightbox behind it closes - two of the failures
// this layer fixes, in one line that every other assertion here is happy with.
const closeTop = /function closeTopOverlay\(\) \{([\s\S]*?)\n {4}\}/.exec(jsSrc);
if (closeTop && /return popOverlay\(\);/.test(closeTop[1])) {
  ok("closeTopOverlay() actually pops the stack");
} else {
  bad("closeTopOverlay() actually pops the stack",
    closeTop ? "got:" + closeTop[1].trim() : "the function is missing - Escape would close nothing");
}

// The stack must pop the LAST entry, not the first: a FIFO pop closes the
// bottom-most overlay, which is the mirror image of the bug the stack was
// introduced to fix.
const popBody = /function popOverlay\(\) \{([\s\S]*?)\n {4}\}/.exec(jsSrc);
if (popBody && /\.pop\(\)/.test(popBody[1])) {
  ok("popOverlay() pops the LAST entry (top-down)");
} else {
  bad("popOverlay() pops the last entry", "got:" + (popBody ? popBody[1].trim() : "<missing>"));
}

// Counting `document.addEventListener("keydown"` only is not enough. The bug
// this layer exists to remove was TWO Escape dispatchers both running on one
// press, and a second one bound to `window` or `document.body` is the same bug
// with a different target - and it survived the narrower pattern entirely, since
// neither string contains `document.`. The object expression is matched instead:
// any dotted member chain rooted at document, window or body.
//
// The leading `[^\w.]` is what keeps it honest - it forbids a preceding
// identifier character or dot, so `someObject.document.addEventListener` is not
// counted as `document.addEventListener` (the tail anchor after the object
// expression makes that case moot anyway, but the guard is explicit about the
// boundary rather than relying on it).
// Mutation: add a second dispatcher on `window` -> red.
// Mutation: add a second dispatcher on `document.body` -> red.
const ESC_DISPATCH_RE =
  /(?:^|[^\w.])(?:document|window|body)(?:\.\w+)*\.addEventListener\("keydown"/g;
const escMatches = jsSrc.match(ESC_DISPATCH_RE) || [];
const escGlobal = escMatches.length;
if (escGlobal === 1) {
  ok("exactly ONE document/window/body-level keydown handler remains");
} else {
  bad("exactly ONE document/window/body-level keydown handler remains",
    "found " + escGlobal + ": " + escMatches.join(" | ") +
    " - every Escape closes every layer it happens to reach, which is the original bug");
}

// The stack must be walked BEFORE the fixed overlays, or Escape still dismisses
// two layers at once (the sheet is topmost, and closing it with the lightbox is
// exactly the bug being fixed).
const escFn = /document\.addEventListener\("keydown"[\s\S]*?\n {4}\}\);/.exec(jsSrc);
if (escFn) {
  const body = escFn[0];
  const stackAt = body.indexOf("closeTopOverlay()");
  const editorAt = body.indexOf("imgEditor");
  if (stackAt !== -1 && editorAt !== -1 && stackAt < editorAt) {
    ok("Escape consults the overlay stack before the fixed overlays");
  } else {
    bad("Escape consults the overlay stack before the fixed overlays",
      "the stack call is " + (stackAt === -1 ? "missing" : "after the fixed overlays"));
  }
} else {
  bad("Escape consults the overlay stack before the fixed overlays",
    "the single document keydown handler could not be located");
}

// aria-current must have exactly ONE writer. Two writers - one on click, one
// derived from state - is how the highlight starts lying the first time a
// surface is opened by something other than its own nav row.
const ariaWrites = (jsSrc.match(/["']aria-current["']/g) || []).length;
const setDef = /function setDestination\(name\) \{[\s\S]*?\n {4}\}/.exec(jsSrc);
if (ariaWrites === 2 && setDef && setDef[0].includes('setAttribute("aria-current"')) {
  ok("setDestination is the only writer of aria-current (2 references, both inside it)");
} else {
  bad("setDestination is the only writer of aria-current",
    ariaWrites + ' reference(s) to "aria-current" across the script; a second writer would be derived state and remembered state fighting');
}

// The sheet is populated by MOVING the sidebar's nodes, and the move has to go
// the right way in both directions. This was written backwards the first time -
// openSidebarSheet emptied the sheet and left the rows in the grid cell, so a
// phone got a working-looking empty drawer - and the swap is invisible to every
// structural check above, because the nodes are still present and still carry
// their handlers. Only the direction of the two loops says anything.
const openFn = /function openSidebarSheet\(\) \{[\s\S]*?\n {4}\}/.exec(jsSrc);
const parkFn = /function parkSidebarRows\(\) \{[\s\S]*?\n {4}\}/.exec(jsSrc);
if (openFn && /while \(sidebar\.firstChild\) sidebarSheet\.appendChild\(/.test(openFn[0])) {
  ok("openSidebarSheet moves the rows OUT of the sidebar and into the sheet");
} else {
  bad("openSidebarSheet moves the rows out of the sidebar",
    openFn ? "the loop does not move sidebar.firstChild into sidebarSheet" : "openSidebarSheet is missing");
}

// ...and the move must come BEFORE syncSidebarSheetState, because
// syncSidebarSheetState hides the collapse control and pushOverlay focuses
// whatever is first. Round 1 asserted the direction of the move and the presence
// of the `[hidden]` filter, but not the ORDER - so swapping the last two lines of
// openSidebarSheet reproduced the exact shipped focus bug (focus asked for while
// the control was still visible, then the control hidden underneath it) with
// every suite green. Three statements, order-sensitive, all load-bearing:
//
//   1. move the nodes   - syncSidebarSheetState finds #sidebarCollapse by id, and
//                         after the move it is inside #sidebarSheet. `getElementById`
//                         is document-scoped so this works either way, but the
//                         collapse control only BELONGS to the sheet once moved.
//   2. syncSidebarSheetState(true) - sets collapse.hidden = true.
//   3. pushOverlay     - focuses the first VISIBLE focusable. If this ran before
//                         (2), #sidebarCollapse would still be visible and would
//                         take focus; hiding it afterwards leaves the caret on a
//                         display:none control, or - because the browser refuses
//                         focus() there - outside the aria-modal dialog entirely.
//
// The search space is the body with COMMENTS BLANKED, preserving offsets so the
// positions still point into the real body and the failure message stays
// readable. Without this the assertion is over-fitted to first TEXTUAL
// occurrence: a comment merely mentioning `pushOverlay(` above the move would
// win the search and report the calls reordered, which the comment immediately
// above this block promises cannot happen. Same technique as the CSS parser in
// this file - blank the comment, keep the byte length.
//
// Anchored to the start of a line as well, because a trailing `// ... calling
// pushOverlay(...)` on the SAME line as a real statement would otherwise still
// match at an earlier offset than the statement it trails. `^[ \t]*` accepts
// this file's indentation; the shipped code indents four spaces inside the
// spliced <script>.
//
// Asserted on positions, not on the strings, so reformatting does not break it
// and reordering does. Whether the ORDERED sequence actually produces the right
// focus is asserted by running it, in nav_focus_effect_test.js.
// Mutation: swap statements 2 and 3 -> red.
// Mutation: insert a comment mentioning pushOverlay( above the move -> green.
if (openFn) {
  const b = openFn[0];
  const code = b.replace(/\/\*[\s\S]*?\*\//g, (m) => " ".repeat(m.length))
    .replace(/\/\/[^\n]*/g, (m) => " ".repeat(m.length));
  const move = code.search(/^[ \t]*while \(sidebar\.firstChild\)/m);
  const sync = code.search(/^[ \t]*syncSidebarSheetState\(true\);/m);
  const push = code.search(/^[ \t]*pushOverlay\(/m);
  if (move !== -1 && sync !== -1 && push !== -1 && move < sync && sync < push) {
    ok("openSidebarSheet orders move -> syncSidebarSheetState -> pushOverlay (hiding the control must precede focusing)");
  } else {
    bad("openSidebarSheet orders move -> syncSidebarSheetState -> pushOverlay",
      "positions were move=" + move + " sync=" + sync + " push=" + push +
      " - pushOverlay before syncSidebarSheetState focuses #sidebarCollapse while it is still visible, then hides it underneath the caret");
  }
} else {
  bad("openSidebarSheet orders move -> syncSidebarSheetState -> pushOverlay",
    "openSidebarSheet is missing");
}

if (parkFn && /while \(sidebarSheet\.firstChild\) sidebar\.appendChild\(/.test(parkFn[0])) {
  ok("parkSidebarRows moves them back out of the sheet and into the sidebar");
} else {
  bad("parkSidebarRows moves them back into the sidebar",
    parkFn ? "the loop does not move sidebarSheet.firstChild into sidebar" : "parkSidebarRows is missing");
}

// The rows leave #sidebar entirely while the sheet is open, so a dismiss handler
// bound to #sidebar never sees the click - which is the whole interaction on a
// phone. Same mistake, opposite direction, and equally invisible structurally.
//
// Captured as the ENCLOSING ARROW FUNCTION, from the listener registration to the
// end of its body, rather than as a fixed +-400 character window. A window is
// loose in a way that matters: a decoy `document.addEventListener("click"` from
// any unrelated handler within the window would satisfy it, and this file has
// more than one click listener. The capture is anchored on
// `addEventListener("click"` and runs to the matching `\n    });`, which is this
// script's four-space closing convention - the same technique escFn above uses.
//
// closeSidebarSheet() is the CALL. An earlier version checked only the row
// lookup and the two contains() tests, so deleting the call left every term
// present and the suite green - an assertion that proved the handler could find
// a row and then said nothing about what it does with one. Also required to be
// INSIDE the guarded if, not merely somewhere in the capture: a stray
// closeSidebarSheet() elsewhere in the listener would otherwise satisfy it.
//
// KNOWN COST OF THE TIGHTENING, and the reason it is left alone. The capture is
// now wide enough to hold the whole handler, so the three terms it requires -
// `document.addEventListener("click"`, `sidebar.contains(row)`,
// `sidebarSheet.contains(row)` and the `closeSidebarSheet()` call - are still
// required as literal source text. Extracting the two contains() tests into a
// helper such as `rowIsInSidebar(row)` would be a pure refactor with identical
// semantics and would go RED here, because the helper's definition is not in the
// capture and its call site names no `contains`. That is the price of moving from
// a 400-character window to the enclosing function, and it is cheaper than the
// window was. Do NOT "fix" it by loosening these patterns to accept a helper: the
// assertion's job is to notice when someone removes a call from this handler, and
// a regex loose enough to survive a refactor will eventually survive the removal.
// If this ever does need to survive one, re-point it at the effect - click a row
// in nav_focus_effect_test.js and assert the sheet closed - which is what that
// file is for.
// Mutation: replace closeSidebarSheet() with a comment -> red.
// Mutation: move closeSidebarSheet() out of the guard -> red.
const dismissCtx = (() => {
  const start = jsSrc.indexOf('document.addEventListener("click"');
  if (start === -1) return "";
  const end = jsSrc.indexOf("\n    });", start);
  if (end === -1) return "";
  return jsSrc.slice(start, end);
})();
if (/document\.addEventListener\("click"/.test(dismissCtx) &&
    /e\.target\.closest\("\.sidebar-menu-button"\)/.test(dismissCtx) &&
    /sidebar\.contains\(row\)/.test(dismissCtx) &&
    /sidebarSheet\.contains\(row\)/.test(dismissCtx) &&
    /\)\s*\{\s*closeSidebarSheet\(\);/.test(dismissCtx)) {
  ok("the sheet dismisses on a row tap, delegated on the document and covering both containers");
} else {
  bad("the sheet dismisses on a row tap",
    dismissCtx === ""
      ? "the delegated click handler could not be located"
      : "missing one of: the document listener, the .sidebar-menu-button lookup, either contains() test, or the closeSidebarSheet() CALL inside the guard - the rows are in #sidebar OR #sidebarSheet, never both, so all four have to be there");
}

// aria-current must be DERIVED from activeOverlay, not remembered from the last
// click. Remembering it means opening History from anywhere but its own nav row
// - a permission card, a notification, a deep link - leaves the nav pointing at
// Chat while History covers the chat, and nothing else in the app would notice.
const highlightFn = /function updateTierButtonHighlight\(\) \{[\s\S]*?\n {4}\}/.exec(jsSrc);
if (highlightFn && /DESTINATION_FOR_OVERLAY\[activeOverlay\]/.test(highlightFn[0])) {
  ok("aria-current is derived from activeOverlay, not from the last click");
} else {
  bad("aria-current is derived from activeOverlay",
    highlightFn ? "updateTierButtonHighlight does not consult DESTINATION_FOR_OVERLAY" : "the function is missing");
}

// The four non-chat destinations are reachable only through a mapping from the
// overlay's own name, so a missing or misspelled entry is what leaves a nav row
// silently un-highlighted. BOTH halves are read - the keys are the overlay names
// updateComposerMode() writes into activeOverlay, the values are the
// data-destination the nav row actually carries - because the near-miss this
// guards is `quick-actions` on one side and `actions` on the other, and checking
// only one side would miss it.
const FOUR_OVERLAYS = ["drive", "history", "reminders", "quick-actions"];
const FOUR_DESTINATIONS = ["actions", "drive", "history", "reminders"];
const mapMatch = /DESTINATION_FOR_OVERLAY\s*=\s*\{([\s\S]*?)\n {4}\}/.exec(jsSrc);
// Keys are quoted only where they need to be - `"quick-actions"` is, `history`
// is not - so BOTH sides of the pair are matched optionally-quoted. Requiring
// the quotes would silently match only the hyphenated entry and report the other
// three as unmapped, which is what a first attempt did.
const pairs = mapMatch
  ? (mapMatch[1].match(/"?([a-z-]+)"?\s*:\s*"?([a-z-]+)"?/g) || [])
      .map((s) => /"?([a-z-]+)"?\s*:\s*"?([a-z-]+)"?/.exec(s))
  : [];
const mapKeys = pairs.map((p) => p[1]).sort();
const mapVals = pairs.map((p) => p[2]).sort();
const missingKeys = FOUR_OVERLAYS.filter((k) => !mapKeys.includes(k));
const missingVals = FOUR_DESTINATIONS.filter((v) => !mapVals.includes(v));
if (mapMatch && pairs.length === 4 && missingKeys.length === 0 && missingVals.length === 0) {
  ok("every overlay name maps to a real destination (" + mapKeys.join(", ") + ")");
} else {
  bad("every overlay name maps to a real destination",
    "unmapped overlay(s): " + (missingKeys.join(", ") || "none") +
    "; unreachable destination(s): " + (missingVals.join(", ") || "none") +
    " - updateTierButtonHighlight() would either name a destination no row carries, " +
    "or leave one unreachable, and no row would claim aria-current");
}

// ---------------------------------------------------------------------------
// 6b. The Chat row is WIRED. setDestination moves aria-current and nothing else,
//     so a destination row with no handler is a row that does nothing at all -
//     and the Chat row had none. The four overlay rows each bind their own
//     listener at their feature site; Chat has no feature site, so its binding
//     lives in the sidebar block beside the router it routes through.
//
// Captured as the ENCLOSING ARROW FUNCTION, from the registration to the end of
// its body, for the reason the sheet-dismiss capture gives: a fixed character
// window would be satisfied by an unrelated click listener, and this file has
// many. Anchored on `[data-destination="chat"]` so the capture cannot even start
// on the wrong row.
//
// Deliberately NOT asserted here: that the handler reaches switchTier, and that
// the tier it passes is the last one used. That is a question about RUNNING the
// code, and it is asked in nav_focus_effect_test.js, which compiles both
// functions out of the shipped source and calls them. A regex here would be
// satisfied by `setDestination("chat")` in a comment.
// Mutation: delete the whole binding -> red.
// Mutation: change the argument to setDestination("drive") -> red.
const chatWire = (() => {
  const start = jsSrc.indexOf('sidebar.querySelector(\'[data-destination="chat"]\')');
  if (start === -1) return "";
  const open = jsSrc.indexOf("addEventListener(\"click\"", start);
  if (open === -1) return "";
  // To the next line at this file's four-space statement indentation, rather than
  // to a `\n    });` as the sheet-dismiss capture does: a one-line arrow body
  // (`addEventListener("click", () => { setDestination("chat"); });`) never
  // reaches that terminator, and a capture that cannot find it would report a
  // missing binding for code that is right there.
  const end = jsSrc.indexOf("\n    ", open);
  if (end === -1) return "";
  return jsSrc.slice(start, end);
})();
if (/sidebar\.querySelector\('\[data-destination="chat"\]'\)/.test(chatWire) &&
    /addEventListener\("click"/.test(chatWire) &&
    /setDestination\("chat"\)/.test(chatWire)) {
  ok('the Chat row is bound to setDestination("chat") - looked up by its data-destination, like the four overlay rows');
} else {
  bad("the Chat row is bound to setDestination(\"chat\")",
    chatWire === ""
      ? 'no binding for [data-destination="chat"] was found - the row moves aria-current and nothing else, so an unbound row does nothing when clicked'
      : "the binding does not resolve the chat row, listen for clicks, or route through setDestination(\"chat\"): " + chatWire.trim());
}

// The four overlay rows bind their own listeners, so the chat row binding must
// NOT be a catch-all over every [data-destination] - that would fire the chat
// route when Drive or History is pressed, on top of their own handlers.
const allDestWire = (() => {
  const start = jsSrc.indexOf('sidebar.querySelector(\'[data-destination="chat"]\')');
  if (start === -1) return "";
  const end = jsSrc.indexOf("\n    ", start);
  return end === -1 ? "" : jsSrc.slice(start, end);
})();
if (allDestWire !== "" && !/querySelectorAll/.test(allDestWire)) {
  ok("the Chat binding targets its own row, not every [data-destination]");
} else {
  bad("the Chat binding targets its own row",
    allDestWire === "" ? "the binding could not be located" :
    "it queries all destinations, so pressing Drive or History would also run the chat route");
}

// aria-current names a DESTINATION, and the tier rows are a CHOICE between two
// conversations rather than one - they carry .active, which is a different class
// for a different question. If either tier button ever grew a data-destination,
// setDestination would hand it aria-current="page" and two rows would claim to
// be the current page, which is what a screen reader announces twice.
const tierRows = [query(doc, "#tier1Btn"), query(doc, "#tier2Btn")];
const tierDest = tierRows.filter((el) => el && "data-destination" in el.attrs);
if (tierRows.every(Boolean) && tierDest.length === 0) {
  ok("neither tier row carries data-destination, so setDestination can never hand one aria-current");
} else {
  bad("neither tier row carries data-destination",
    tierDest.length + " of them do - a tier row claiming aria-current=\"page\" is a second \"current page\" for a screen reader");
}

// lastActiveTier is the tier the Chat row returns to, and it is seeded from
// activeTier rather than a literal. That is not a style preference: activeTier is
// RESTORED from sessionStorage on load, so a literal 1 seeds lastActiveTier wrong
// for anyone reloading on Tier 2 - and setDestination("chat") runs during
// initialisation (updateTierButtonHighlight is called by initAppState), where a
// lastActiveTier that disagrees with activeTier makes switchTier miss its
// early-return exit and commit the wrong tier over the restore.
// The effect half runs this declaration for real; this checks it is the shipped
// one and that it reads activeTier rather than a number.
// Mutation: `= 1` -> red. Mutation: `= isElevated` -> red.
const lastDecl = /^\s*let lastActiveTier = ([^;]+);\s*$/m.exec(jsSrc);
if (lastDecl && /^activeTier$/.test(lastDecl[1].trim())) {
  ok("lastActiveTier is seeded from activeTier, so a reload that restored Tier 2 is not dragged back to Tier 1");
} else {
  bad("lastActiveTier is seeded from activeTier",
    lastDecl ? "seeded from " + JSON.stringify(lastDecl[1].trim()) + " instead" : "the declaration is missing");
}

// ...and the fresh-unlock reset has to move BOTH. initAppState(true) forces
// activeTier back to 1 because a new gate session starts clean at Tier 1; if
// lastActiveTier kept the value activeTier held before that reset, the very next
// setDestination("chat") - the one initAppState itself makes - would switch to
// the old tier and persist it, which is the fresh unlock arriving on the wrong
// tier. Both in one statement so they cannot be edited apart.
// Mutation: drop `lastActiveTier` from the reset -> red.
const freshUnlock = /function initAppState\(freshUnlock\) \{([\s\S]*?)\n {4}\}/.exec(jsSrc);
const freshResetsBoth = freshUnlock &&
  /(activeTier = lastActiveTier = 1;|lastActiveTier = activeTier = 1;)/.test(
    freshUnlock[1].replace(/\/\/[^\n]*/g, ""));
if (freshResetsBoth) {
  ok("the fresh-unlock reset moves lastActiveTier with activeTier, so a new session cannot land on the old tier");
} else {
  bad("the fresh-unlock reset moves lastActiveTier with activeTier",
    "initAppState(true) forces activeTier to 1 but leaves lastActiveTier holding the pre-reset value, and initAppState's own setDestination(\"chat\") would then commit it");
}

// ---------------------------------------------------------------------------
// 7. The cascade. Neither this file nor jsdom has a layout engine, so "under
//    640px the sidebar becomes a sheet and the trigger appears" is asserted as
//    the declaration that produces it, not as a measurement.
// ---------------------------------------------------------------------------

const cssNoComments = cssSrc.replace(/\/\*[\s\S]*?\*\//g, (m) => " ".repeat(m.length));

// selector SET -> every body declared for it, in source order. The list is the
// point: CSS applies the LAST match, so a single string would score a rule that
// a later one overrides. Two maps come back, because the two questions differ -
// "is this selector set declared exactly once" (a media-scoped override counts,
// since it is the copy that renders) and "does this selector appear in a rule
// that does X" (where the selector set is whatever else happens to share it).
function ruleBodies(src) {
  const bySet = new Map();
  const bySel = new Map();
  const re = /([^{}]*)\{([^{}]*)\}/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const sels = m[1].split(",").map((s) => s.trim()).filter(Boolean);
    const body = m[2].split(/\s+/).filter(Boolean).join(" ");
    const key = sels.slice().sort().join(" | ");
    if (!bySet.has(key)) bySet.set(key, []);
    bySet.get(key).push(body);
    for (const s of sels) {
      if (!bySel.has(s)) bySel.set(s, []);
      bySel.get(s).push(body);
    }
  }
  return { bySet, bySel };
}

// Byte ranges of every @media block whose prelude names this max-width, so the
// responsive assertions read the rules INSIDE it rather than the whole sheet.
function mediaRange(src, query) {
  const open = new RegExp("@media\\s*\\(\\s*" + query + "\\s*\\)\\s*\\{", "g");
  const ranges = [];
  let m;
  while ((m = open.exec(src)) !== null) {
    let depth = 1;
    let i = m.index + m[0].length;
    while (i < src.length && depth > 0) {
      if (src[i] === "{") depth++;
      else if (src[i] === "}") depth--;
      i++;
    }
    ranges.push([m.index, i]);
  }
  return ranges;
}

// Blank out every @media / @keyframes body, so the TOP-LEVEL map really is the
// top level. The `[^{}]` scan above has no idea an @-rule is there - it drops the
// prelude and reads a media-scoped override as if it were declared at the root,
// which is how `.app` came to look like it was declared twice when it is declared
// once and overridden once.
//
// KNOWN LIMIT, and it is the reason this function exists at all rather than the
// reason it cannot be trusted: both `ruleBodies` and `withoutAtRuleBodies` walk
// with `[^{}]`, which cannot represent a NESTED at-rule - an `@media` inside an
// `@supports`, or a rule inside `@layer`. The at-rule list here is therefore
// EXHAUSTIVE for this stylesheet and a KNOWN FOUR-NAME list, not a pattern for
// "any at-rule": a fifth kind (`@container`, `@layer`, `@document`) would be left
// in by this function and then read at the root by ruleBodies, i.e. silently
// mistaken for a top-level declaration. perla-companion.css has no nested or
// fifth-kind at-rules today - `grep -c '^ *@'` returns only @media and @keyframes
// - so nothing is misread today. If one is added, ADD ITS NAME HERE in the same
// commit; the alternative is a cascade assertion quietly scoring a nested rule as
// a root one, which is the first-match bug this whole section was written to
// avoid.
function withoutAtRuleBodies(src) {
  let out = "";
  let i = 0;
  while (i < src.length) {
    const at = /@(?:media|keyframes|supports|font-face)\b[^{]*\{/.exec(src.slice(i));
    if (!at) { out += src.slice(i); break; }
    out += src.slice(i, i + at.index);
    let depth = 1;
    let j = i + at.index + at[0].length;
    while (j < src.length && depth > 0) {
      if (src[j] === "{") depth++;
      else if (src[j] === "}") depth--;
      j++;
    }
    out += " ".repeat(j - (i + at.index));
    i = j;
  }
  return out;
}

const top = ruleBodies(withoutAtRuleBodies(cssNoComments));

// Every declaration of one property inside ONE rule body, in order, and the
// first of them. Reads the body `ruleBodies` stores - whitespace-normalised and
// `;`-separated - with the SAME split `resolveProperty` does, so the two cannot
// disagree about what a declaration is. The list rather than a single string is
// the point: a rule that declares the same property twice has a second copy
// overriding the first, which is invisible if only the first is read.
//
// `declOf` is a READ, deliberately, and is used where the question is about one
// declared declaration rather than about what the cascade applies: a custom
// property on an element (`.app`'s published inset), and a grid's track list for
// a state the resolver cannot see (`.app[data-collapsed="true"]` is an attribute
// selector, and `resolveProperty` skips those on purpose). Everywhere the claim
// is about what RENDERS, the assertions go through `resolveProperty`.
function declsOf(body, prop) {
  if (!body) return [];
  const p = String(prop).toLowerCase();
  const out = [];
  for (const raw of String(body).split(";")) {
    const d = raw.trim();
    const c = d.indexOf(":");
    if (c === -1) continue;
    if (d.slice(0, c).trim().toLowerCase() !== p) continue;
    const v = d.slice(c + 1).trim();
    if (v) out.push(v);
  }
  return out;
}
const declOf = (body, prop) => {
  const all = declsOf(body, prop);
  return all.length ? all[0] : null;
};
const setKey = (sel) => sel.split(",").map((s) => s.trim()).sort().join(" | ");
const bodies = (sel) => top.bySet.get(setKey(sel)) || [];
const selBodies = (sel) => top.bySel.get(sel) || [];
const topSrc = withoutAtRuleBodies(cssNoComments);

// ---------------------------------------------------------------------------
// A CASCADE RESOLVER, because "the declaration exists" is not "the declaration
// wins" and the difference shipped.
//
// `.sidebar-trigger { display: none }` and `.btn-icon { display: inline-flex }`
// are both (0,1,0). Source order decided, `.btn-icon` sits 520 lines later, and
// the hamburger rendered on every desktop next to a sidebar that already
// navigates. Every assertion that shipped alongside it asked whether the
// declaration was PRESENT - `test_primitives.sh` section 19 counted two
// declarations and pinned `display: none` as the first, and the line above
// confirmed the media query reveals it - and every one of them was true. This is
// the same class as the first-match-wins bugs fixed in earlier rounds, one level
// up: a rule that is real, correct, and outranked.
//
// So: resolve the property the way a browser would, and read the WINNER.
// `resolveProperty` returns the declaration the cascade actually applies, or null
// if no rule in `src` sets it for this element.
//
// CONSERVATIVE ON PURPOSE, and every limitation errs in ONE direction - toward
// reporting a weaker winner than the browser's, never a stronger one:
//
//   - a selector part containing a pseudo-class or pseudo-ELEMENT is treated as
//     NOT matching. Those are states this harness does not model, and counting
//     `:hover` as a match would let a rule outrank the one that applies.
//   - an attribute selector is treated as NOT matching, for the same reason:
//     `[aria-expanded="true"]` depends on runtime state, not on the markup.
//   - a combinator (descendant, child, sibling) is NOT understood. A selector
//     using one is skipped rather than matched as though the combinator were
//     absent, which would invent a match.
//
// THE COMBINATOR GAP IS MEASURED, NOT HYPOTHETICAL. Mutation: add
// `.app-header .sidebar-trigger { display: inline-flex }` - a (0,2,0) rule that
// would render the hamburger on every desktop - and NOTHING goes red, in this
// suite or any other. That is the limitation above doing exactly what it says,
// and it is recorded here rather than left for the next reader to discover the
// hard way. It is a deliberate stopping point: supporting `A B` means walking
// ancestors, and the next step past that is `:has()`, at which point this is a
// selector engine rather than a cascade resolver for two rules. The assertions
// below are unaffected - nothing in the shipped stylesheet puts a combinator on
// either element - and the fix that chose to RELOCATE a rule rather than raise a
// specificity is deliberately the one that keeps this resolver sufficient.
//
// The one `!important` in this stylesheet that sets `display` is the global
// `[hidden] { display: none !important }`, and it is skipped by the attribute
// rule above. That is only sound while the element in question carries no
// `hidden` attribute, which is asserted next to every use below rather than
// assumed - otherwise the gap could open without anything going red.
// ---------------------------------------------------------------------------

// Does one comma-separated selector part, taken as a plain compound, select this
// element? Returns the part's specificity, or null when the part is skipped.
function compoundSpec(el, part) {
  if (!part) return null;
  // Skip anything this resolver cannot model rather than guessing at it.
  if (/[:\s>+~[\]="']/.test(part)) return null;
  const spec = { id: 0, cls: 0, tag: 0 };
  // A compound is a run of #id / .class / tag tokens with nothing between them.
  const tokens = part.match(/[#.]?[A-Za-z][\w-]*/g);
  if (!tokens || tokens.join("") !== part) return null;
  for (const t of tokens) {
    if (t.startsWith("#")) {
      if (el.attrs.id !== t.slice(1)) return null;
      spec.id++;
    } else if (t.startsWith(".")) {
      if (!el.classes.has(t.slice(1))) return null;
      spec.cls++;
    } else {
      if (el.tagName !== t.toLowerCase()) return null;
      spec.tag++;
    }
  }
  return spec;
}

const specRank = (s) => [s.id, s.cls, s.tag];
const specGT = (a, b) => {
  const x = specRank(a), y = specRank(b);
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] > y[i] ? 1 : -1;
  return 0;
};

// `el` a node from makeNode, `prop` a property name, `src` a stylesheet whose
// at-rule bodies the caller has already handled (topSrc for the desktop sheet,
// narrowSrc for the 640px block).
function resolveProperty(el, prop, src) {
  const re = /([^{}]*)\{([^{}]*)\}/g;
  let m, order = 0;
  let best = null;
  while ((m = re.exec(src)) !== null) {
    const parts = m[1].split(",").map((s) => s.trim()).filter(Boolean);
    let spec = null;
    for (const p of parts) {
      const s = compoundSpec(el, p);
      if (!s) continue;
      // A selector LIST takes the specificity of its most specific matching part.
      if (!spec || specGT(s, spec)) spec = s;
    }
    if (!spec) continue;
    // Declarations are read whole, values included, so `display: inline-flex` is
    // one declaration and not a `display:` prefix. Splitting on `;` is the same
    // reading py_axis_rules uses, and no value in this stylesheet contains one.
    for (const raw of m[2].split(";")) {
      const d = raw.trim();
      const c = d.indexOf(":");
      if (c === -1) continue;
      const p = d.slice(0, c).trim().toLowerCase();
      if (p !== prop.toLowerCase()) continue;
      let value = d.slice(c + 1).trim();
      const important = /!\s*important$/i.test(value);
      if (important) value = value.replace(/!\s*important$/i, "").trim();
      if (!value) continue;
      const cand = { imp: important ? 1 : 0, spec: spec, order: order++, value: value };
      if (!best) { best = cand; continue; }
      if (cand.imp !== best.imp) { if (cand.imp > best.imp) best = cand; continue; }
      const c2 = specGT(cand.spec, best.spec);
      if (c2 > 0 || (c2 === 0 && cand.order > best.order)) best = cand;
    }
  }
  return best;
}

// --- .app is the grid, and is declared ONCE ---------------------------------
const appBodies = bodies(".app");
if (appBodies.length === 1) {
  ok(".app is declared exactly once (a second copy would be the one that renders)");
} else {
  bad(".app is declared exactly once", appBodies.length + " declarations: " + appBodies.join("  ||  "));
}
const appBody = appBodies[appBodies.length - 1] || "";
const appGrid = /(^|\s)display: grid(;|\s|$)/.test(appBody) &&
  /grid-template-columns: var\(--sidebar-width\) 1fr/.test(appBody) &&
  /height: 100dvh/.test(appBody) &&
  /overflow: hidden/.test(appBody);
if (appGrid) {
  ok(".app is a full-bleed grid: display:grid, var(--sidebar-width) + 1fr, 100dvh, overflow:hidden");
} else {
  bad(".app is a full-bleed grid", "got: " + (appBody || "<no rule>"));
}
if (!/max-width: 820px/.test(appBody)) {
  ok("the 820px centred column is gone from .app");
} else {
  bad("the 820px centred column is gone from .app", "still declared: " + appBody);
}
if (!/padding-top/.test(appBody)) {
  ok(".app no longer reserves the header band - the sidebar runs the full height");
} else {
  bad(".app no longer reserves the header band",
    "padding-top on the grid container leaves an empty strip above the sidebar");
}

// --- .app-content is the column, and .app-card is what reserves the header ---
const contentBodies = bodies(".app-content");
if (contentBodies.length === 1) {
  ok(".app-content is declared exactly once");
} else {
  bad(".app-content is declared exactly once", contentBodies.length + " declarations");
}
const contentBody = contentBodies[contentBodies.length - 1] || "";
// It no longer reserves the header band: .app-card does, and both halves of that
// move are asserted here so the reservation cannot end up TWICE. `padding-top`
// left on the column plus `margin-top` on the card would push the chat a full
// header-height below where the header actually ends.
if (/min-width: 0/.test(contentBody) && /min-height: 0/.test(contentBody) &&
    !/padding-top/.test(contentBody)) {
  ok(".app-content can shrink (min-width/min-height: 0) and reserves nothing - .app-card's job");
} else {
  bad(".app-content can shrink and reserves nothing", "got: " + (contentBody || "<no rule>"));
}

const cardBodies = bodies(".app-card");
const cardBody = cardBodies[cardBodies.length - 1] || "";
// Two halves. (1) STATIC: #drivePanel is `position: absolute` and .app-content is
// the nearest positioned ancestor. Give the card a position and the Drive panel
// re-anchors to the card - which is inside the 900px measure, so it would cover
// the chat and stop filling the column. (2) The six declarations that make this a
// card at all: drop `margin-inline` or `max-width` and it runs edge to edge,
// which is the bug this layer exists to fix; drop `flex`/`min-height` and the
// transcript stops scrolling inside the card.
// Mutation: give .app-card `position: relative` -> red on (1).
// Mutation: delete `max-width` -> red on (2).
const cardStatic = !/position:\s*(absolute|fixed|sticky|relative)/.test(cardBody);
if (cardBodies.length === 1 && cardStatic) {
  ok(".app-card is declared once and is STATIC, so .app-content stays the containing block");
} else {
  bad(".app-card is declared once and is static",
    cardBodies.length + " declaration(s): " + (cardBody || "<no rule>") +
    " - a positioned card would re-anchor #drivePanel");
}
// 820px, and the number is the POINT rather than a detail: it is what this column
// was before the redesign - the floating card's `max-width: 820px` - and the brief
// asked for the same size as before. An earlier draft of this rule said ~900px,
// which was a re-measure nobody asked for, so the literal is pinned to stop the
// next reader improving it again.
// Mutation: 820px -> 900px -> red.
const cardWired = /flex:\s*1/.test(cardBody) && /min-height:\s*0/.test(cardBody) &&
  /min-width:\s*0/.test(cardBody) && /margin-inline:\s*auto/.test(cardBody) &&
  /max-width:\s*820px/.test(cardBody) && /margin-top:\s*var\(--header-height\)/.test(cardBody);
if (cardWired) {
  ok(".app-card states the whole recipe: it fills, shrinks, centres, is capped, and clears the header");
} else {
  bad(".app-card states the whole recipe",
    "got: " + (cardBody || "<no rule>"));
}
// The card must not go find a background of its own. Two bubble rules in this
// file already resolve to --card and --background, so a card painted either of
// them erases messages into the page - the single most visible thing on screen.
// Mutation: add `background: var(--card)` to .app-card -> red here.
if (!/background\s*:/.test(cardBody) && !/border-radius\s*:/.test(cardBody) &&
    !/border\s*:/.test(cardBody)) {
  ok(".app-card adds no background, border or radius of its own - it is a measure, and the surfaces inside keep theirs");
} else {
  bad(".app-card adds no background, border or radius of its own",
    "got: " + (cardBody || "<no rule>") +
    " - .entry-perla .entry-bubble is var(--card) and the question cards are var(--background); painting the card either colour erases messages");
}

// position: relative IS the containment. Both children below say `position:
// absolute` and resolve against the nearest POSITIONED ancestor, which without
// this declaration is the viewport - which is precisely the bug this layer fixed:
// an `absolute` header with no positioned ancestor spans the whole window and
// paints straight across the nav column. Asserting `position: absolute` on the
// children without asserting this said "inside" and checked nothing. `.app` sets
// no position, so with this removed both children silently revert to the viewport.
// Mutation: delete `position: relative` from .app-content -> red here and nowhere
// else.
if (/position: relative/.test(contentBody)) {
  ok(".app-content is position: relative, so it is the CONTAINING BLOCK for the absolute children below");
} else {
  bad(".app-content is position: relative",
    "got: " + (contentBody || "<no rule>") +
    " - with no positioned ancestor, .app-header and .drive-panel resolve against the VIEWPORT and the header paints across the sidebar");
}

// The header's own declaration - `absolute`, not `fixed`, because `fixed`
// anchors to the viewport and spans the whole window. That is only half the
// claim: which element it is positioned AGAINST is the other half, and it is the
// assertion immediately above (.app-content must be positioned). Both have to
// hold or the header lands over the nav column, which is what `fixed` did.
const headerBodies = bodies(".app-header");
const headerBody = headerBodies[headerBodies.length - 1] || "";
if (headerBodies.length === 1 && /position: absolute/.test(headerBody) &&
    /height: var\(--header-height\)/.test(headerBody)) {
  ok(".app-header declares position: absolute at --header-height (its container is asserted above)");
} else {
  bad(".app-header declares position: absolute at --header-height",
    headerBodies.length + " declaration(s): " + (headerBody || "<no rule>"));
}
const header = query(doc, ".app-header");
if (header && appContent && contains(appContent, header)) {
  ok(".app-header is a child of .app-content, the element that positions it");
} else {
  bad(".app-header is a child of .app-content",
    "it is elsewhere in the tree, so `absolute` resolves against whatever ancestor happens to be positioned");
}

// --- the mobile shape ------------------------------------------------------
const narrow = mediaRange(cssNoComments, "max-width:\\s*640px");
if (narrow.length >= 1) {
  ok("there is a max-width: 640px query (" + narrow.length + ")");
} else {
  bad("there is a max-width: 640px query", "none found");
}
const narrowSrc = narrow.map(([a, b]) => cssNoComments.slice(a, b)).join("\n");
const narrowRules = ruleBodies(narrowSrc).bySel;

// .sidebar-trigger must be hidden OUTSIDE the media query and shown inside it -
// two declarations of the same selector, and CSS applies the second. So the
// "outside" half is read from the whole sheet and the "inside" half from the
// 640px block, and both have to be true for the phone case to work at all.
//
// THE ASSERTION ABOVE IS NOT ENOUGH, and the two are kept side by side on
// purpose. It asks whether `display: none` is DECLARED for `.sidebar-trigger`.
// The bug was that it was declared, correctly, in the right place, and lost to
// `.btn-icon { display: inline-flex }` 520 lines below it on a specificity tie.
// The next assertion asks the only question that can catch that.
const triggerOutside = bodies(".sidebar-trigger").join(" ");
const triggerInside = (narrowRules.get(".sidebar-trigger") || [])[0] || "";
if (/display: none/.test(triggerOutside) && /display: (?!none)/.test(triggerInside)) {
  ok(".sidebar-trigger is display:none by default and shown inside the 640px query");
} else {
  bad(".sidebar-trigger is display:none by default and shown inside the 640px query",
    "outside='" + triggerOutside + "' inside='" + triggerInside + "'");
}

// THE EFFECTIVE display on a desktop, resolved rather than read. This is the
// assertion whose absence let the hamburger ship.
//
// The element is #sidebarTrigger, and its class list is the whole question:
// `btn-icon btn-icon-28 sidebar-trigger`. Both `.btn-icon` and `.sidebar-trigger`
// are (0,1,0), so the winner is whichever comes LAST in the stylesheet - and
// `.btn-icon` is a primitives-block rule while the trigger is a shell rule. If
// anyone moves either of them the answer changes, so the answer is what gets
// asserted, not the position of any one line.
// Mutation: move `.sidebar-trigger { display: none }` back above `.btn-icon`
//            -> red here, and GREEN everywhere else - this is the assertion the
//            bug shipped past.
// Mutation: delete `.sidebar-trigger { display: none }` entirely -> red here.
// The `[hidden]` skip in the resolver is sound only because of the next check.
const desktopDisplay = trigger ? resolveProperty(trigger, "display", topSrc) : null;
if (desktopDisplay && desktopDisplay.value === "none") {
  ok(".sidebar-trigger's EFFECTIVE display on a desktop is none - the rule wins the cascade, not merely exists");
} else {
  bad(".sidebar-trigger's effective display on a desktop is none",
    "resolves to " + (desktopDisplay ? "'" + desktopDisplay.value + "'" : "<nothing sets it>") +
    " - a rule that declares display:none and loses to .btn-icon is dead code, and the hamburger renders beside the sidebar that already navigates");
}

// The soundness condition for skipping `[hidden] { display: none !important }`
// above. Asserted rather than assumed, because it is the one gap in the
// resolver and it is exactly the gap that would let a future `hidden` on the
// trigger turn the assertion above into a confident wrong answer.
if (trigger && !("hidden" in trigger.attrs)) {
  ok("#sidebarTrigger carries no [hidden] attribute, so the global [hidden] display:none !important cannot apply to it");
} else {
  bad("#sidebarTrigger carries no [hidden] attribute",
    "it is hidden in the markup, so the global [hidden] { display: none !important } outranks everything resolveProperty considers and its verdict would be wrong");
}

// The same question on a phone, where the 640px block is the whole stylesheet
// and the trigger has to come back. Without this the fix for the desktop half
// would be satisfied by deleting the reveal, and the phone would have no way in.
const phoneDisplay = trigger ? resolveProperty(trigger, "display", narrowSrc) : null;
if (phoneDisplay && phoneDisplay.value !== "none") {
  ok("inside the 640px query .sidebar-trigger's effective display is '" + phoneDisplay.value + "' - the phone keeps its one way in");
} else {
  bad("inside the 640px query .sidebar-trigger's effective display is not none",
    "resolves to " + (phoneDisplay ? "'" + phoneDisplay.value + "'" : "<nothing sets it>") +
    " - a phone would have a sheet nothing can open");
}

// --- BUG 1, the half that is not the markup: the card's MEASURE ---------------
// `.content-wrap` is already asserted to be a direct child of `.app-card` above -
// it always was - so the reported bug was never the tree. It was the card's
// WIDTH, and width is not in the DOM at all: it is what the cascade computes.
//
// `.app-card` is a flex item in a COLUMN flex container, so its cross axis is
// horizontal and `align-self: stretch` is what makes it fill the column. CSS
// suppresses that stretch when the cross-axis margins are `auto`, which
// `margin-inline: auto` is - and that suppression is why auto margins are the
// right way to centre a capped column. The side effect is that the box becomes
// FIT-CONTENT, so its width is whatever its contents happen to be. Measured in
// Firefox at 1600x1000 with the shipped stylesheet: 264px with an empty
// transcript, 790px after one ordinary reply, and never 820 in either state.
//
// `max-width` is a CEILING, and a ceiling nothing reaches is not a measure. So
// the card must declare a DEFINITE cross size, and `margin-inline: auto` is
// precisely what makes that necessary rather than redundant - which is why both
// halves are asserted together below rather than either alone.
// Mutation: delete `width: 100%` from .app-card -> red here.
// Mutation: add a later `.app-card { width: auto }` -> red here (resolved, not
//            grepped), and green in every other suite.
const cardWidth = appCard ? resolveProperty(appCard, "width", topSrc) : null;
const cardMargins = appCard ? resolveProperty(appCard, "margin-inline", topSrc) : null;
const cardMax = appCard ? resolveProperty(appCard, "max-width", topSrc) : null;
const cardDefinite = cardWidth !== null &&
  /^-?\d/.test(cardWidth.value) && cardWidth.value !== "auto" &&
  cardMargins !== null && cardMargins.value === "auto" &&
  cardMax !== null && cardMax.value === "820px";
if (cardDefinite) {
  ok(".app-card's resolved cross size is DEFINITE (" + cardWidth.value + ", capped at " + cardMax.value + ") - auto inline margins suppress stretch, so without it the measure tracks the content");
} else {
  bad(".app-card's resolved cross size is definite, capped at 820px",
    "width=" + (cardWidth ? cardWidth.value : "<none>") +
    " margin-inline=" + (cardMargins ? cardMargins.value : "<none>") +
    " max-width=" + (cardMax ? cardMax.value : "<none>") +
    " - with margin-inline:auto the box is fit-content, so the chat is 264px empty and grows only when a message arrives");
}

// --- the landing target for the collapse fix has a consumer and a guard -------
// `releaseSidebarFocus()` sends focus to the transcript when the sidebar
// collapses, because the collapsed rail's `:focus-within` arm re-opens the
// column for as long as anything inside the sidebar holds focus - and the
// control that was just pressed is inside it. A <main> with no tabindex cannot
// receive focus, so the fix would silently degrade to doing nothing.
// Mutation: drop tabindex from <main> -> red here and red on the effect half.
const main = query(doc, "main");
if (main && main.classes.has("page") && main.getAttribute("tabindex") === "-1") {
  ok("<main class=\"page\"> carries tabindex=\"-1\", so the collapse fix has somewhere real to put focus");
} else {
  bad("<main class=\"page\"> carries tabindex=\"-1\"",
    main ? "tabindex=" + JSON.stringify(main.getAttribute("tabindex")) +
      " - focus() on a plain <main> is a no-op, so collapsing would leave focus on the sidebar and the rail would stay open"
      : "no <main> in the transcript - the collapse fix would have no landing target");
}

// The persistent sidebar's slot in the grid has to be vacated on a phone,
// otherwise the content column keeps a 256px hole beside it.
const gridInNarrow = (narrowRules.get(".app") || [])[0] || "";
if (/grid-template-columns: 1fr/.test(gridInNarrow) &&
    /position: fixed/.test(gridInNarrow) &&
    /inset: 0/.test(gridInNarrow)) {
  ok("under 640px .app collapses to one column and is fixed to the viewport");
} else {
  bad("under 640px .app collapses to one column and is fixed to the viewport",
    "got: " + (gridInNarrow || "<no rule>"));
}
const sidebarInNarrow = (narrowRules.get(".app > .sidebar") || [])[0] || "";
if (/display: none/.test(sidebarInNarrow)) {
  ok("under 640px the persistent sidebar leaves the grid");
} else {
  bad("under 640px the persistent sidebar leaves the grid",
    "got: " + (sidebarInNarrow || "<no rule>"));
}

// --- the mobile KEYBOARD path ---------------------------------------------
// keyboardResize() rewrites #app's inline height from visualViewport so the
// composer sits on top of the on-screen keyboard. With a grid, the element it
// must bound is the GRID: bounding .app-content instead would leave the sidebar
// running past the bottom of the visible area. And .app must still declare a
// height in CSS, because that is the declaration the inline style overrides.
const kb = /function keyboardResize\(\)[\s\S]*?\n {4}\}\)\(\);/.exec(jsSrc);
if (kb && /getElementById\("app"\)/.test(kb[0]) && /style\.height = height \+ "px"/.test(kb[0])) {
  ok("keyboardResize still bounds #app - the grid - with the visual viewport height");
} else {
  bad("keyboardResize still bounds #app with the visual viewport height",
    "the handler no longer resolves #app or sets its inline height");
}
if (/height: 100dvh/.test(appBody)) {
  ok(".app declares a CSS height for keyboardResize's inline value to override");
} else {
  bad(".app declares a CSS height", "100dvh is the fallback the inline style replaces");
}
if (/position: fixed/.test(gridInNarrow)) {
  ok(".app is fixed under 640px, so the `top` keyboardResize sets has a box to move");
} else {
  bad(".app is fixed under 640px", "the visualViewport offsetTop is written to a static element");
}

// --- FIX 3: the collapsed rail takes NO grid column ------------------------
// The reported bug: collapsing the sidebar moved the chat 200px to the left. A
// width on a var(--sidebar-width) TRACK cannot do that - the track does not
// narrow with the item, so the sidebar's 200px came straight out of the content
// column. There are exactly two halves to the fix, and neither is any use alone,
// so they are asserted as a PAIR:
//
//   1. the rail is OUT OF FLOW (`position: fixed`), so it occupies no track;
//   2. the grid is ONE COLUMN while collapsed, or .app-content auto-places into
//      the vacated first track and shifts 256px the other way.
//
// `fixed` rather than `absolute` is itself part of the claim: .app declares no
// position, so `absolute` would resolve against whatever ancestor happens to be
// positioned - and pinning the rail to the VIEWPORT is exactly what "pinned to
// the screen's left edge" says, with no dependency on any ancestor having a box
// to pin to.
//
// THE REASON THIS FILE USED TO GIVE FOR IT WAS FALSE, and it is corrected here
// rather than left to rot. It said: "Making .app positioned is not available -
// #globalNotifications is a `position: fixed` child of #app and pinning .app
// would re-anchor the viewport-centred toast stack." A `position: relative`
// ancestor does NOT re-anchor a `position: fixed` descendant. Only `transform`,
// `perspective`, `filter`, `backdrop-filter`, `will-change` of those, or
// `contain: paint` create a containing block for a fixed box. So that was never
// a reason .app could not be positioned, and ux-fix-3 flagged it for exactly
// this reason without editing it.
//
// It is ALSO MOOT NOW, and that is worth recording rather than just deleting:
// the toast stack and #qaDrawer no longer centre on the viewport at all. They
// read `--content-column-inset`, a custom property, and custom properties
// inherit through the DOM regardless of any `position` - so pinning .app would
// not have moved them, and would not move them now. The centring correction is
// in section 11; the `left: calc((100% + var(--content-column-inset)) / 2)`
// there is the mechanism, and it is unaffected by how .app is positioned.
//
// Mutation: `position: absolute` -> red (half 1).
// Mutation: drop any of top/left/bottom -> red.
// Mutation: delete `.app[data-collapsed="true"]` -> red (half 2).
// Mutation: its `1fr` back to `var(--sidebar-width) 1fr` -> red (half 2).
const railBodies = bodies('.sidebar[data-collapsed="true"]');
const railBody = railBodies[railBodies.length - 1] || "";
const outOfFlow = /position: fixed/.test(railBody);
const pinned = /\btop: 0/.test(railBody) && /\bleft: 0/.test(railBody) && /\bbottom: 0/.test(railBody);
// The WIDTH is `--sidebar-width` in both states, which is the opposite of what
// this assertion used to require and is the point of the slide: the panel does not
// resize, it travels. What the rail SHOWS is still --sidebar-rail-width, and that
// is the slide relation asserted in the arithmetic section - asking for it here as
// a literal would contradict the mechanism that produces it.
const railIsPanel = /width: var\(--sidebar-width\)/.test(railBody);
if (railBodies.length === 1 && outOfFlow && pinned && railIsPanel) {
  ok("the collapsed rail is out of the flow, pinned to the left edge, and held at --sidebar-width so it can slide rather than resize");
} else {
  bad("the collapsed rail is out of the flow and pinned to the left edge",
    railBodies.length + " declaration(s): " + (railBody || "<no rule>") +
    " - an in-flow rail narrows nothing and the content column shifts by exactly the difference");
}
const collapsedGrid = bodies('.app[data-collapsed="true"]');
const collapsedGridBody = collapsedGrid[collapsedGrid.length - 1] || "";
// SCOPED TO THE ONE DECLARATION, and it used to be a whole-body regex. The old
// form asked "does this rule mention `var(--sidebar-width)` anywhere", which is a
// different question from "is the first track still the sidebar": the collapsed
// rule now also publishes `--content-column-inset`, and it happens to want 0
// there, but a future edit that pointed the inset at the sidebar width would have
// tripped this - red, but for the wrong reason, and pointing at the grid. Reading
// the track out of the body is the question the name actually asks.
// Mutation: `1fr` back to `var(--sidebar-width) 1fr` -> red here, as before.
const collapsedCols = declOf(collapsedGridBody, "grid-template-columns");
if (collapsedGrid.length === 1 && collapsedCols === "1fr") {
  ok('the collapsed grid is ONE 1fr column, so .app-content keeps the whole viewport width');
} else {
  bad("the collapsed grid is one 1fr column",
    collapsedGrid.length + " declaration(s): grid-template-columns=" + (collapsedCols || "<none>") +
    " - with the first track still 256px the content column lands in the wrong one");
}

// --- FIX 4: hover opens the rail, and nothing dims ---------------------------
// FOUR claims, and the third is a design decision rather than a property:
//
//   1. the rail really is --sidebar-rail-width at REST (asserted above) and the
//      full --sidebar-width when the pointer is on it, animated by the width
//      transition already on .sidebar rather than by a new one;
//   2. ANYWHERE on the rail opens the column, a row included. This used to be the
//      opposite - the slide-out was `:not(:has(.sidebar-menu-button:hover))`, so a
//      row hover showed that row's chip and left the rail at 56px - and the split
//      is gone because the chip is gone from the UX (its rules are all still in
//      the stylesheet, inert: `content: none` deletes the box). So the ABSENCE
//      claim below is now the reverse of what it was: a PLAIN `:hover` arm is
//      required, and a row-carve-out arm is the regression.
//   3. NO scrim, NO darkening. `.sidebar-overlay` must not reach the desktop at
//      all: the user was explicit, and a scrim here would also be a pointer
//      capture that makes the slide-out feel like a modal;
//   4. the keyboard arm is the exact mirror - plain `:focus-within` - so Tab
//      behaves like hover. Its `:not(:has(.sidebar-menu-button:focus-visible))`
//      carve-out went with claim 2's, for the same reason.
//
// The hover arm additionally carries `:not([data-hover-suppressed="true"])`, which
// is ITEM 4'S FIX and not part of the split: toggleSidebar() sets that attribute
// on a collapse the pointer is sitting on, and a pointerleave removes it, so the
// rail stays collapsed until the pointer LEAVES and comes back rather than
// springing open under a cursor that never moved. Measured in Firefox 156 with
// real pointer input: with the flag absent, pressing the collapse control left
// `:hover` true and the column open, and releaseSidebarFocus had already put focus
// on <main> - so the focus half of this bug was fixed and the hover half was not.
//
// Mutation: append `.sidebar[data-collapsed="true"]:hover { width: … }` -> red.
// Mutation: drop `:focus-within` from the pair -> red.
// Mutation: `--sidebar-width` -> `var(--sidebar-rail-width)` in the body -> red.
// Mutation: put `width:` back in the body instead of padding-left/transform -> red.
// Mutation: add `background: var(--scrim)` to the body -> red (claim 3).
// THE OPEN SELECTORS, named once so the comparison below has something to compare
// against. Eleven rules rest on the pair agreeing; the one way they could stop
// agreeing - a `:not()` argument edited on one and not the other - is exactly the
// shape of bug this file has been caught shipping twice.
const SLIDE_HOVER = '.sidebar[data-collapsed="true"]:not([data-hover-suppressed="true"]):hover';
const SLIDE_FOCUS = '.sidebar[data-collapsed="true"]:focus-within';
const railHover = selBodies(SLIDE_HOVER);
const railFocusIn = selBodies(SLIDE_FOCUS);
const hoverBody = railHover[0] || "";
const focusBody = railFocusIn[0] || "";
const opensBySliding = /padding-left:\s*0/.test(hoverBody) && /transform:\s*translateX\(0\)/.test(hoverBody);
// No `width:` anywhere in either arm. A body that still resized would pass the
// first check as well, and it is the check the whole review finding was about.
const stoppedResizing = !/width\s*:/.test(hoverBody);
if (railHover.length === 1 && opensBySliding && stoppedResizing &&
    railFocusIn.length === 1 && hoverBody === focusBody) {
  ok("hovering ANYWHERE on the rail (and the keyboard mirror) SLIDES the column out - padding-left and transform, and no width anywhere");
} else {
  bad("hovering anywhere on the rail slides the sidebar out",
    ":not([data-hover-suppressed]):hover -> " + (railHover.length + " rule(s): " + (hoverBody || "<none>")) +
    "; :focus-within -> " + (railFocusIn.length + " rule(s): " + (focusBody || "<none>")));
}
if (hoverBody === focusBody) {
  ok("the slide has ONE body, so a keyboard user and a mouse user see the same thing");
} else {
  bad("the slide has one body",
    "hover='" + hoverBody + "' focus-within='" + focusBody + "' - the two paths have drifted");
}
// CLAIM 2, THE ABSENCE - INVERTED. Before the chip was retired this asked for no
// plain `:hover` arm, because a plain arm would open the column on a row and so
// collide with the chip. There is no chip now, so the collision cannot happen and
// a plain arm is what the file must contain. What is asserted instead is that NO
// row-carve-out arm survives anywhere: `:not(:has(.sidebar-menu-button:hover))` or
// its focus-visible twin reappearing would restore the split, and the restored
// split is invisible on screen - a rail row that silently does nothing - which is
// the worst shape a regression in this block can take.
//
// Asked over `bySel` rather than by counting the two known selectors, so a third
// variant of the carve-out (`-webkit-any`, `:nth-child`, anything) is caught too,
// and so a second rule appended later is caught even though the first one's count
// is unchanged.
const rowCarveOuts = [...top.bySel.keys()].filter((s) =>
  /^\.sidebar\[data-collapsed="true"\]:hover:not\(:has\(/.test(s) ||
  /^\.sidebar\[data-collapsed="true"\]:focus-within:not\(:has\(/.test(s));
// ...and the two live arms are present with nothing between the compound and
// :hover / :focus-within, which is the "anywhere" half stated positively.
const hoverArmIsPlain = /^\.sidebar\[data-collapsed="true"\]:not\(\[data-hover-suppressed="true"\]\):hover$/.test(SLIDE_HOVER);
const focusArmIsPlain = /^\.sidebar\[data-collapsed="true"\]:focus-within$/.test(SLIDE_FOCUS);
if (rowCarveOuts.length === 0 && hoverArmIsPlain && focusArmIsPlain) {
  ok("the rail expands on hover ANYWHERE - no :not(:has(<a row>)) carve-out survives on either arm, and the hover arm carries the hover lock");
} else {
  bad("the rail expands on hover anywhere",
    "row carve-out selectors still present: " + (rowCarveOuts.join(", ") || "<none>") +
    "; hover arm plain: " + hoverArmIsPlain + " (" + SLIDE_HOVER + ")" +
    "; focus arm plain: " + focusArmIsPlain + " (" + SLIDE_FOCUS + ")");
}
// CLAIM 3, THE ABSENCE - NO UNGUARDED SLIDE-OUT ANYWHERE ELSE. This one was
// LOST in this round and mutation s41 found it, which is the only reason it is
// worth three paragraphs. The two arms above are pinned by SELECTOR, so a
// SECOND rule - appended anywhere, declaring the same slide-out properties on a
// plain `.sidebar[data-collapsed="true"]:hover` - slides perfectly past them:
// both arms are unchanged, their counts are unchanged, and the column opens the
// moment the pointer touches the rail with no lock on it, which is Item 4's bug
// wearing a different selector. ux-fix-2 caught this with an "no UNGUARDED
// :hover or :focus-within slide-out exists" assertion; rewriting that assertion
// for the chip's retirement dropped the clause along with the chip.
//
// So it is asked again here, from the other direction: sweep every rule in the
// sheet, and flag any OTHER `.sidebar`-level hover/focus arm that declares one
// of the three properties that make the column appear.
//
// Three scoping decisions, each of which the first version of this assertion got
// wrong and the mutation below found:
//
//   - `.sidebar`-level only. The selector's LAST compound must be the sidebar
//     itself. `.sidebar[data-collapsed="true"]:focus-within .sidebar-header
//     { padding-left: var(--space-4) }` sets a padding but is not a slide-out -
//     it is a descendant's own layout inside an already-open column, and flagging
//     it made this assertion red on a correct file.
//   - the two PINNED arms are exempt by name, not by property. They are the rule
//     this whole block is about; asking them to differ from themselves is
//     circular.
//   - the FOCUS arm is exempt too, and deliberately so. It carries no
//     data-hover-suppressed and must not: the lock means "the pointer is on the
//     rail", and `:focus-within` is the keyboard, where there is no pointer to
//     lock out. That is asserted in nav_focus_effect_test.js as behaviour rather
//     than read off a selector here.
// Mutation: append `.sidebar[data-collapsed="true"]:hover { width: var(--sidebar-width); }` -> red.
// Mutation: replace the hover arm's lock with nothing -> red (and CLAIM 2 too).
const SLIDE_PROPS = ["padding-left", "transform", "width"];
const unguardedSlideOuts = [...top.bySel.entries()].filter(([sel, body]) => {
  if (sel === SLIDE_HOVER || sel === SLIDE_FOCUS) return false;
  if (sel === ".sidebar" || sel === '.sidebar[data-collapsed="true"]') return false;
  // `.sidebar`-level: the last compound is the sidebar, so nothing follows it.
  if (!/^\.sidebar(\[[^\]]*\])?(:not\([^)]*\))?:(hover|focus-within)$/.test(sel)) return false;
  if (/\[data-hover-suppressed="true"\]/.test(sel)) return false;
  return SLIDE_PROPS.some((p) => new RegExp("(^|;)\\s*" + p + "\\s*:", "m").test(body));
});
if (unguardedSlideOuts.length === 0) {
  ok("no UNGUARDED slide-out exists anywhere else - every rule that sets padding-left, transform or width on a .sidebar hover/focus arm also carries [data-hover-suppressed=\"true\"], so a second slide-out cannot sidestep the lock");
} else {
  bad("no UNGUARDED slide-out exists anywhere else",
    unguardedSlideOuts.map(([s, b]) => s + " { " + b + " }").join(" | ") +
    " - a rule like that slides past the pinned arms, opens the column with no lock on it, and is Item 4's bug under a different selector");
}
// ITEM 4'S OTHER HALF, and it is a READING assertion where an EFFECT one would
// have been the wrong tool. The flag is set by toggleSidebar and cleared by
// clearHoverLock, and nav_focus_effect_test.js compiles both out of the shipped
// source and runs them - but it has to BIND the listener itself, because a
// top-level `addEventListener` call is not a function body to extract. So the
// subscription itself is pinned HERE, and between the two halves a missing
// subscription and a broken clearer are both red.
//
// `pointerleave` and not `pointerout`, and the reason is specific rather than
// stylistic: pointerout also fires when the pointer crosses from the rail onto one
// of the rows inside it, which is not leaving at all, and the flag would then
// clear while the pointer was still on the rail.
// Mutation: change the event to "pointerout" -> red.
// Mutation: bind it inside toggleSidebar instead -> red (the count is 1, and a
//   per-press binding accumulates).
// Mutation: rename clearHoverLock -> red.
const jsStripped = jsSrc.replace(/\/\*[\s\S]*?\*\//g, "");
const leaveSubs = (jsStripped.match(/addEventListener\(\s*"pointerleave"/g) || []).length;
const pointerOutSubs = (jsStripped.match(/addEventListener\(\s*"pointerout"/g) || []).length;
const clearLockNamed = /function clearHoverLock\(\)\s*\{/.test(jsSrc) &&
  /addEventListener\(\s*"pointerleave"\s*,\s*clearHoverLock\)/.test(jsStripped);
if (leaveSubs === 1 && pointerOutSubs === 0 && clearLockNamed) {
  ok("the hover lock's only clearer is a single pointerleave subscription to a named clearHoverLock - bound once at top level, and not pointerout, which also fires when the pointer crosses onto a row inside the rail");
} else {
  bad("the hover lock is cleared by exactly one pointerleave subscription",
    leaveSubs + " pointerleave subscription(s), " + pointerOutSubs + " pointerout, named+bound: " + clearLockNamed +
    " - without this the lock is either never cleared (the rail can never re-open on hover) or cleared by the wrong event");
}
// ...and the flag has exactly ONE writer. A second `dataset.hoverSuppressed =`
// anywhere would be a second place the two halves could disagree, which is the
// reason toggleSidebar's comment says expanding deliberately leaves it alone.
const lockWriters = (jsStripped.match(/dataset\.hoverSuppressed\s*=/g) || []).length;
const lockDeleters = (jsStripped.match(/delete\s+sidebar\.dataset\.hoverSuppressed/g) || []).length;
if (lockWriters === 1 && lockDeleters === 1) {
  ok("data-hover-suppressed has exactly one writer and one deleter in the whole script");
} else {
  bad("data-hover-suppressed has one writer and one deleter",
    lockWriters + " write(s), " + lockDeleters + " delete(s) - the asymmetry is deliberate (expand leaves the flag alone) and only holds while there is exactly one of each");
}
// BOTH bodies of the pair, not just `:hover`'s. The pair is ONE rule with two
// selectors, and `bodies()` keys on the whole set - so a dimming declaration
// added to the `:focus-within` arm is invisible to a check that reads only the
// `:hover` one. That was not hypothetical: the first version of this assertion
// did exactly that and mutation m22 stayed GREEN.
// Mutation: add `background: …` to EITHER arm -> red.
const scrimOnRail = [].concat(
  bodies(SLIDE_HOVER + ",\n    " + SLIDE_FOCUS) || [],
  bodies(SLIDE_HOVER) || [],
  bodies(SLIDE_FOCUS) || [])
  .some((b) => /--scrim|background/.test(b));
// M5. The old half of this was `!/sidebar-overlay/.test(js)`, and there is no such
// string anywhere in the file - the scrim is `.sheet-overlay` / `#sidebarOverlay`.
// So the check was `!false`, i.e. always true, and it read as "the desktop never
// binds a scrim" while testing a name that does not exist.
//
// The real chain, asked as the two facts that could break it:
//
//   1. `openSidebarSheet()` is CALLED from exactly one place, and that place is
//      inside #sidebarTrigger's click handler. The scrim DOES carry its own click
//      listener - it has to, it is how a phone dismisses a sheet - so "bound only
//      to the trigger" would be FALSE about the scrim and wrong to assert. What
//      matters is that only the TRIGGER can OPEN anything.
//   2. the scrim is only ever UN-HIDDEN by `syncSidebarSheetState(true)`, which is
//      itself called only from openSidebarSheet. So the scrim cannot appear on a
//      desktop even though the element and its listener exist.
//
// `blockSpan` counts braces from the anchor instead of pattern-matching the end -
// the same technique `withoutAtRuleBodies` and `mediaRange` already use here, and
// for the reason review round 2 recorded about `fnSpan`: a first-match `indexOf` on
// a closing token stops at the first one, which is usually not the function's.
// Mutation: add a second `openSidebarSheet()` call -> red.
// Mutation: open the sheet from a keydown handler -> red.
// Mutation: un-hide #sidebarOverlay from anywhere else -> red.
// Mutation: `.sidebar-trigger`'s root `display: none` -> `display: block` -> red.
function blockSpan(text, anchor) {
  const i = text.indexOf(anchor);
  if (i === -1) return null;
  let depth = 0, started = false;
  for (let j = text.indexOf("{", i); j < text.length; j++) {
    if (text[j] === "{") { depth++; started = true; }
    else if (text[j] === "}") { depth--; if (started && depth === 0) return [i, j]; }
  }
  return null;
}
const jsNoComments = jsSrc.replace(/\/\*[\s\S]*?\*\//g, "");
const triggerSpan = blockSpan(jsNoComments, 'sidebarTrigger.addEventListener("click"');
// The DEFINITION is excluded by its own index, not by looking backwards for the
// word `function`: `m.index` points at the name, so a slice taken BEFORE it cannot
// contain the name and the filter never fired - which is how the count came out as
// 2 call sites for a function that is called once.
const openCalls = [];
{
  // the name sits AFTER "function ", so the definition's match index is that
  // offset on - comparing the two directly never matched and the definition counted
  const defAt = jsNoComments.indexOf("function openSidebarSheet(") + "function ".length;
  const r = /openSidebarSheet\(\)/g;
  let m;
  while ((m = r.exec(jsNoComments)) !== null) {
    if (m.index !== defAt) openCalls.push(m.index);
  }
}
const openOnlyFromTrigger = triggerSpan !== null && openCalls.length === 1 &&
  openCalls[0] > triggerSpan[0] && openCalls[0] < triggerSpan[1];
// Exactly ONE `syncSidebarSheetState(true)` - inside openSidebarSheet. The
// scrim's `hidden` flag is written in exactly that function, so one true-call is
// one way for the scrim to appear, and it is the phone's.
const syncTrue = (jsNoComments.match(/syncSidebarSheetState\(true\)/g) || []).length;
const scrimOnlyViaSheet = syncTrue === 1;
const triggerHidden = /^\s*display:\s*none;?$/.test(
  (selBodies(".sidebar-trigger") || [""])[0]);
if (!scrimOnRail && openOnlyFromTrigger && scrimOnlyViaSheet && triggerHidden) {
  ok("nothing dims behind the slide-out: no arm carries a background, openSidebarSheet() is reachable only from #sidebarTrigger, #sidebarOverlay is only un-hidden through it, and the trigger is display:none at the root");
} else {
  bad("nothing dims behind the slide-out",
    "an arm carries a background: " + scrimOnRail +
    "; openSidebarSheet() call sites: " + openCalls.length + " (inside the trigger's handler: " + openOnlyFromTrigger + ")" +
    "; syncSidebarSheetState(true) occurrences: " + syncTrue + "; .sidebar-trigger root display:none: " + triggerHidden);
}

// --- reduced motion covers the three things that MOVE -------------------------
// The file already kills the mic pulses, the think-dot, the lightbox fade and the
// shake under prefers-reduced-motion. The rail's slide, the drawer's slide-in and
// the tooltip's fade are the same kind of thing: motion nobody asked for. Asserted
// as three selectors INSIDE the reduced-motion block rather than by searching the
// whole sheet, because a `transition: none` on .sidebar anywhere else would be a
// different rule with a different meaning.
// Mutation: delete the `.sheet { animation: none }` arm -> red.
// Mutation: delete the `.sidebar` arm -> red.
// Mutation: delete the `.sidebar-menu-button::after` arm -> red.
const reduced = mediaRange(cssNoComments, "prefers-reduced-motion\\:\\s*reduce");
// selector -> its BODY, read from inside the query's byte range. The previous
// version of this collected selectors and destructured a `needle` it then never
// referenced, so replacing all three arms' bodies with `width: 111px` - taking no
// motion away anywhere - still printed PASS on all three. A value computed but
// not tested is the same shape as the `Object.keys`-on-a-Map bug this round has
// already found once: the assertion LOOKED like it was checking the motion and was
// checking that three selectors exist.
//
// `selBodies` cannot answer this either: it resolves `top`, and `top` blanks every
// at-rule body, so a media-scoped rule reads as absent. Hence the range.
const reducedArms = [];
for (const [a, b] of reduced) {
  const inner = cssNoComments.slice(a, b);
  for (const m of inner.matchAll(/([^{}]*)\{([^{}]*)\}/g)) {
    const body = m[2].split(/\s+/).filter(Boolean).join(" ");
    for (const one of m[1].split(",").map((x) => x.trim()).filter(Boolean)) {
      reducedArms.push({ sel: one, body: body });
    }
  }
}
// Mutation: `transition: none` -> `width: 111px` in any arm -> red.
for (const [who, needle] of [[".sheet", /animation:\s*none/],
                             [".sidebar", /transition:\s*none/],
                             [".sidebar-menu-button::after", /transition:\s*none/]]) {
  const arms = reducedArms.filter((a) => a.sel === who || a.sel.endsWith(", " + who));
  const hits = arms.filter((a) => needle.test(a.body));
  if (arms.length === 1 && hits.length === 1) {
    ok("prefers-reduced-motion takes " + who + "'s motion away (" + needle.source + "), declared once");
  } else {
    bad("prefers-reduced-motion takes " + who + "'s motion away",
      arms.length + " arm(s) inside the query, " + hits.length + " carrying " + needle.source +
      " - bodies: " + (arms.map((a) => a.body).join(" | ") || "<none>"));
  }
}

// --- the collapsed rail has to actually fit --------------------------------
// A rail is --sidebar-rail-width wide. Anything sized for the expanded column
// and not hidden in the collapsed state is clipped by .sidebar's overflow:hidden,
// which is the difference between a deliberate rail and a broken one. The two
// selectors are asserted INSIDE the one collapsed-state rule rather than by
// looking for rules of their own: .brand-mark sets display:flex, so it needs the
// more specific collapsed selector to win, and there is only one rule that can
// provide it.
//
// `.status-indicator` was the third name in this list and has been removed from
// the markup, so asserting it here would assert the hiding of an element that
// does not exist - a green test that could not fail for any edit that mattered.
// `.sidebar-group-label` is NOT in this list either, and that is the point of
// Item 2: it used to be, and it is now shortened rather than hidden (asserted in
// its own section below) because the user asked for the section headers to survive
// the collapse.
for (const sel of [".brand-mark", ".brand-name"]) {
  const hiding = selBodies('.sidebar[data-collapsed="true"] ' + sel);
  if (hiding.length === 1 && /display: none/.test(hiding[0])) {
    ok("the collapsed rail hides " + sel + " (it does not fit 56px), declared once");
  } else {
    bad("the collapsed rail hides " + sel + ", declared once",
      hiding.length + " declaration(s): " + (hiding.join("  ||  ") || "<none>") +
      " - clipped by .sidebar's overflow: hidden");
  }
}
const footerPad = (top.bySel.get('.sidebar[data-collapsed="true"] .sidebar-footer') || [])[0] || "";
if (/padding-left: 0/.test(footerPad) && /padding-right: 0/.test(footerPad)) {
  ok("the collapsed rail drops the footer's side padding so two full-width rows fit");
} else {
  bad("the collapsed rail drops the footer's side padding",
    "got: " + (footerPad || "<no rule>"));
}
if (/margin-left: auto/.test((top.bySel.get(".sidebar-collapse") || [])[0] || "")) {
  ok(".sidebar-collapse is pushed to the trailing edge of the sidebar header");
} else {
  bad(".sidebar-collapse is pushed to the trailing edge", "it sits against the brand instead");
}

// --- the collapsed rail CENTRES its icons ------------------------------------
// The shipped bug: `.sidebar-menu-button` sets `padding: var(--space-2)
// var(--space-3)` and nothing in the collapsed state touched it, so with the
// label hidden the icon sat 4px + 6px = 10px from the rail's left edge instead of
// on its midpoint - roughly 8.5px adrift in a 56px rail, which is a third of the
// button's own width and impossible to mistake for deliberate.
//
// Reading the bodies. `py_axis_rules` - LAST match plus a declared-exactly-once
// count, the two halves CSS actually needs - is a bash helper in
// test_primitives.sh and is not reachable from here, so `axisBodies` below is its
// twin in this file's own idiom: the LAST body (CSS applies the last match) plus
// how many there were. What that avoids is `selBodies(sel)[0]`, the first-match
// read that the five guards this suite was reviewed for got wrong - a duplicate
// declaration renders while a first-match read scores the shadowed copy.
//
// This function is correct for what it does. Whether its CALLERS use it is a
// separate question, and the answer was "no" for seven of them - see the note
// below before adding a read.
function axisBodies(sel) {
  const list = selBodies(sel);
  return { n: list.length, body: list.length ? list[list.length - 1] : "" };
}
//
// WHAT EVERY READ BELOW MUST DO - and the first draft of this block did NOT do it,
// which is worth writing down because the failure is invisible until someone adds
// a second declaration.
//
// `axisBodies` resolved the COLLAPSED selectors. Seven other inputs to the
// arithmetic - `.sidebar`, `.sidebar-content`, `.sidebar-menu-button`,
// `.sidebar-header`, `.sidebar-collapse`, `.btn-icon`, `.btn-icon-24` - were read
// with `bodies(sel)[0]`, which is the FIRST match. The comment in the first draft
// claimed "Every assertion below takes the last body AND asserts the count, so
// neither half can pass alone", and that was FALSE of all seven reads.
//
// (The review called it "six"; it is seven. `.sidebar-collapse` appears twice in
// that list of arithmetic inputs - once for the auto-margin test and once in the
// count - and the reviewer's list of six omitted it from the enumeration. The
// fix covers all of them either way, so the substance is unchanged; the comment
// is corrected rather than the count.)
//
// Proven by mutation, not by argument. Appending a later, winning
// `.sidebar-content { padding: var(--space-3); }` RENDERS (CSS applies the last
// match) while the assertion kept reading the shadowed `var(--space-2)` and stayed
// GREEN. Measured on both harnesses, side by side:
//
//   mutation (a winning duplicate appended)      first-match read   last-match read
//   .sidebar-content                              GREEN             RED
//   .btn-icon-24                                  GREEN             RED
//   .sidebar-menu-button                          GREEN             RED
//   .sidebar (border-right)                       GREEN             RED
//   .btn-icon (padding)                           GREEN             RED
//   .sidebar-header                               RED (1 assertion) RED
//   second collapsed-row rule                     RED               RED
//
// Five of the seven were silently green; the two that were red were red for
// unrelated reasons (the sibling count assertion, and the collapsed rule's own
// `n === 1`).
//
// All seven are declared exactly once today, so nothing mis-renders - which is
// exactly why this is latent rather than live, and why the count half has to be
// asserted rather than assumed: a rule declared twice is dead code whether or not
// the duplicate happens to change the answer today.
//
// So: every input below goes through `axisBodies`, and both arithmetic assertions
// check `n === 1` for EVERY selector they read - collected by `axisUnique` in one
// place, so the check cannot be forgotten for one selector out of seven the way it
// was, and so the failure message names every duplicate at once rather than the
// first one found.
function axisUnique(sels) {
  const got = {};
  const dupes = [];
  for (const sel of sels) {
    got[sel] = axisBodies(sel);
    if (got[sel].n !== 1) dupes.push(sel + " x" + got[sel].n);
  }
  return { got: got, ok: dupes.length === 0, why: dupes.join(", ") };
}

// The collapsed row: no inline padding, centred flex content. Both halves, since
// either alone leaves the icon off the midpoint - padding-left:0 with the content
// still packed at the inline start puts the icon at 4px, and justify-content
// against 6px of padding centres the icon AND its padding box at 27px.
const collapsedRow = axisBodies('.sidebar[data-collapsed="true"] .sidebar-menu-button');
if (collapsedRow.n === 1 && /padding-left: 0/.test(collapsedRow.body) &&
    /padding-right: 0/.test(collapsedRow.body) &&
    /justify-content: center/.test(collapsedRow.body)) {
  ok('the collapsed nav row drops its inline padding and centres its icon (.sidebar[data-collapsed="true"] .sidebar-menu-button, declared once)');
} else {
  bad("the collapsed nav row centres its icon",
    collapsedRow.n + " declaration(s): " + (collapsedRow.body || "<none>") +
    " - one rule has to zero padding-left/padding-right AND set justify-content: center, or the icon renders 6px off the rail's midpoint");
}

// Centring the ROW only centres the ICON if the row is icon-only. This is the
// load-bearing half and it is already shipped (the label spans are hidden by the
// five-selector rule above), but nothing asserted it: a future rule that revealed
// .sidebar-menu-button span in the collapsed state would still leave this section
// green while `justify-content: center` put the icon and its label side by side
// around the midpoint.
const collapsedSpan = axisBodies('.sidebar[data-collapsed="true"] .sidebar-menu-button span');
if (collapsedSpan.n === 1 && /display: none/.test(collapsedSpan.body)) {
  ok("the collapsed nav row really is icon-only, so centring the row centres the ICON (its spans are display:none)");
} else {
  bad("the collapsed nav row is icon-only",
    collapsedSpan.n + " declaration(s): " + (collapsedSpan.body || "<none>") +
    " - with a label still in the flex row, justify-content: centre centres the icon+label pair, not the icon");
}

// The header, for the same reason and one step further out. Its 8px of side
// padding plus `margin-left: auto` on .sidebar-collapse pushed the 24px control to
// the TRAILING edge of a 39px content box, which put its centre at 35px in a
// 55px rail. `margin-left: auto` is the subtle half: an auto margin absorbs ALL
// the free space in a flex row and `justify-content` never gets a look in, so
// centring the header without neutralising it changes nothing.
const collapsedHeader = axisBodies('.sidebar[data-collapsed="true"] .sidebar-header');
if (collapsedHeader.n === 1 && /padding-left: 0/.test(collapsedHeader.body) &&
    /padding-right: 0/.test(collapsedHeader.body) &&
    /justify-content: center/.test(collapsedHeader.body)) {
  ok("the collapsed header drops its inline padding and centres the collapse control (declared once)");
} else {
  bad("the collapsed header centres the collapse control",
    collapsedHeader.n + " declaration(s): " + (collapsedHeader.body || "<none>"));
}
const collapsedCollapse = axisBodies('.sidebar[data-collapsed="true"] .sidebar-collapse');
if (collapsedCollapse.n === 1 && /margin-left: 0/.test(collapsedCollapse.body)) {
  ok("the collapsed collapse control gives up margin-left: auto, which would otherwise beat justify-content");
} else {
  bad("the collapsed collapse control neutralises margin-left: auto",
    collapsedCollapse.n + " declaration(s): " + (collapsedCollapse.body || "<none>") +
    " - an auto margin absorbs all the free space, so the control stays pinned to the trailing edge however the header is centred");
}

// --- ITEM 2: the group labels SURVIVE the collapse, shortened --------------
// This used to assert they were `display: none`, and the user's report was that
// this read as "collapsing removes the section headers". They are now visible in
// the rail with the long word swapped for a short one, so this is a different
// question with a different answer - and the old assertion's shape would have been
// worse than useless here: it would have gone GREEN on a build where the labels
// were hidden again, because that is exactly what it was checking for.
//
// Four things have to hold, and each is checked separately because each fails in
// its own way:
//
//   1. the collapsed rule does NOT hide the label. `display: none` here is the
//      regression, so it is named as the failure rather than the goal.
//   2. the element's own text is taken out of the RENDERING while staying in the
//      DOM - `font-size: 0`, and specifically not `display: none`, because a
//      display-none label leaves a screen-reader user with five unlabelled
//      destinations and that is the accessibility cost the user did not ask for.
//   3. the short form is generated, and it comes from `attr(data-short)` rather
//      than a hardcoded string, so it cannot drift from the markup.
//   4. every label in the markup CARRIES a data-short, and it is a prefix of its
//      own text - the same discipline test (4) of the rail tooltips applies,
//      because a data-short with no label behind it would render as an
//      abbreviation of nothing.
//
// The FIT is the arithmetic section below, not here: this harness has no layout
// engine, so it can say the label is not hidden and that a short form is
// generated, and the measured 47px-against-24.7px fit lives in the CSS's own
// why-comment and in the ux-fix-5 report. What it CAN do here is assert the
// declarations that make the fit possible - the zeroed padding and the centred
// text - because those are what turn 47px of room into 24.7px of centred text
// rather than 35px of left-aligned text.
const collapsedLabel = axisBodies('.sidebar[data-collapsed="true"] .sidebar-group-label');
const labelShort = selBodies('.sidebar[data-collapsed="true"] .sidebar-group-label::after');
const labelHide = /display:\s*none/.test(collapsedLabel.body);
if (collapsedLabel.n === 1 && !labelHide &&
    /font-size:\s*0/.test(collapsedLabel.body) &&
    /padding:\s*0/.test(collapsedLabel.body) &&
    /text-align:\s*center/.test(collapsedLabel.body)) {
  ok("the collapsed group labels are VISIBLE - the long word is taken out of the rendering with font-size: 0, not display: none, and the box is centred and unpadded");
} else {
  bad("the collapsed group labels stay visible, shortened rather than hidden",
    collapsedLabel.n + " declaration(s): " + (collapsedLabel.body || "<none>") +
    (labelHide ? " - display: none is the regression: it is what the user reported as the headers vanishing" : "") +
    " - without font-size: 0 the 59.3px word paints over the chat, since .sidebar-content is overflow: visible here");
}
// The ::after half, read through selBodies so a DUPLICATE would show as a count
// rather than being read first-match and missed.
if (labelShort.length === 1 &&
    /content:\s*attr\(data-short\)/.test(labelShort[0]) &&
    /font-size:\s*var\(--text-2xs\)/.test(labelShort[0]) &&
    /white-space:\s*nowrap/.test(labelShort[0]) &&
    /text-transform:\s*uppercase/.test(labelShort[0])) {
  ok("the rail's short group label is generated from attr(data-short) in the rail's own type, uppercase and nowrap");
} else {
  bad("the short group label is generated from attr(data-short)",
    labelShort.length + " declaration(s): " + (labelShort.join("  ||  ") || "<none>") +
    " - a hardcoded string here would not follow the markup");
}
// THE MARKUP HALF: every label has a data-short, and it is a prefix of its own
// text. Checked per label rather than as "all of them" so the failure names the
// one that is wrong, and the prefix test is what stops `data-short="NAV"` being
// left behind on a label that has since been renamed to something else - which is
// the edit that would make the rail say NAV over the word History.
const groupLabels = queryAll(doc, ".sidebar-group-label");
let labelNoShort = [];
let labelNotPrefix = [];
for (const el of groupLabels) {
  const short = el.attrs["data-short"];
  if (!short) { labelNoShort.push(el.text || "<no text>"); continue; }
  const own = (el.text || "").trim();
  if (!own.toLowerCase().startsWith(short.toLowerCase())) {
    labelNotPrefix.push(short + " vs '" + own + "'");
  }
}
if (groupLabels.length === 2 && labelNoShort.length === 0 && labelNotPrefix.length === 0) {
  ok("both group labels carry a data-short that is a prefix of their own text (" +
     groupLabels.length + " checked), so the rail's abbreviation follows the label");
} else {
  bad("every group label's data-short is a prefix of its own text",
    groupLabels.length + " label(s); missing data-short: [" + labelNoShort.join(", ") +
    "]; not a prefix: [" + labelNotPrefix.join("; ") + "]");
}
// ...and the open column has to put the long word back and stop generating the
// short one, or the 256px column reads "NavigateNAV" at 0px. Asserted as the pair
// of rules rather than one, because they are two declarations and either alone is
// a visible defect - one leaves a stray NAV, the other leaves an invisible label.
const labelRestore = selBodies(SLIDE_HOVER + " .sidebar-group-label")
  .concat(selBodies(SLIDE_FOCUS + " .sidebar-group-label"));
const labelRestoreAfter = selBodies(SLIDE_HOVER + " .sidebar-group-label::after")
  .concat(selBodies(SLIDE_FOCUS + " .sidebar-group-label::after"));
if (labelRestore.length === 2 &&
    labelRestore.every((b) => /font-size:\s*var\(--text-2xs\)/.test(b)) &&
    labelRestoreAfter.length === 2 &&
    labelRestoreAfter.every((b) => /content:\s*none/.test(b))) {
  ok("the open column restores the label's type on both arms and stops generating the short form on both arms");
} else {
  bad("the open column restores the group label",
    "label rules: [" + labelRestore.join(" | ") + "]  ::after rules: [" +
    labelRestoreAfter.join(" | ") + "] - without the font-size the label renders at 0px, and without content: none it reads 'NavigateNAV'");
}

// --- and the centring is EXACT, not approximate ------------------------------
// Four declaration-level assertions say the intent. This one checks the
// arithmetic that turns the intent into pixels, because "centred" is a claim
// about a coordinate and neither the harness nor jsdom has a layout engine to
// measure one. Every number is read out of the sources - the collapsed width, the
// sidebar's own border, the container's padding, the collapsed padding, the item
// width - so changing any of them moves the expected centre rather than
// invalidating the check.
//
// The model, and why each term is there:
//   inner      = collapsedWidth - border-right. `*` is box-sizing: border-box, so
//                .sidebar's 1px border comes out of the declared 56px and
//                everything inside lays out in 55. THIS is why the expected centre
//                is 27.5 and not 28: the rail's declared midpoint is half a pixel
//                off its own content box, which no amount of centring can fix.
//   free  = inner - padLeft - padRight - inlineL - inlineR
//   centre = padLeft + inlineL + free/2 + itemWidth/2   (justify-content: center)
//
// `inlineL` and `inlineR` are SEPARATE, not one value, because a row's own inline
// padding is not required to be symmetric. The first draft collapsed it to one
// number, which hid an error of exactly |l-r|/2: `padding-left: 4px;
// padding-right: 0` renders the icon at 29.5px, genuinely 2px off, and reported
// 27.5. Nothing caught it except a sibling assertion pinning the literal text
// `padding-left: 0`, which is not a guarantee - it is a spelling.
//
// Two items, because the two containers size their child differently and the
// formula has to be right for both: the nav row is `width: 100%` (so its free
// space is 0 and the centre is the content box's own), the collapse control is a
// fixed 24px (so there IS free space for justify-content to distribute).
const pxToken = (name) => {
  const m = new RegExp("--" + name + ":\\s*(-?[\\d.]+)px").exec(cssSrc);
  return m ? parseFloat(m[1]) : null;
};
// A value -> px. Padding is written as tokens, widths as numbers, and a value
// this cannot resolve is a null that makes the comparison below fail rather than
// silently scoring NaN === NaN as true.
// A FUNCTION CALL's argument text, read with a parenthesis counter rather than a
// regex. `transform: translateX(calc(-1 * (var(--a) - var(--b))))` nests three
// deep, and `[^)]*` stops at the first `)` - which is inside the first `var()` -
// so the regex version extracted the string `calc(-1 * (var(--sidebar-width` and
// then failed to resolve it, silently reporting null for a declaration that is
// present and perfectly resolvable. This is the same shape as `mediaRange` and
// `withoutAtRuleBodies`, which both count rather than pattern-match, and for the
// same reason: this file has been bitten by a first-match read four times now.
// Returns null when the call is absent or unbalanced, which makes the assertions
// that use it red rather than wrong.
function callArg(name, body) {
  const i = body.indexOf(name + "(");
  if (i === -1) return null;
  let depth = 0;
  for (let j = i + name.length; j < body.length; j++) {
    const c = body[j];
    if (c === "(") depth++;
    else if (c === ")") {
      depth--;
      if (depth === 0) return body.slice(i + name.length + 1, j).trim();
    }
  }
  return null;
}

// `calc(...)` as well, because the collapsed rail's padding-left and transform
// are both `calc()` of two tokens and ux-fix-1's model cannot see the rail at all
// without it. A `calc` is resolved here rather than in a second helper so there is
// ONE function that turns a written length into a number: two would be two things
// to keep in step, and the failure mode is the same one ux-fix-1 already hit - a
// silently-unresolvable term that turns a centre into NaN and then compares equal.
//
// Supported: `calc(<a> - <b>)`, `calc(-1 * (<a> - <b>))`, `calc(<a> * <n>)`, and
// bare lengths, with nesting. Anything else returns null, which makes the
// assertions that use it RED rather than wrong.
// Mutation: `calc(var(--sidebar-width) - var(--sidebar-rail-width))` -> `300px`
//            -> red (the flank arithmetic below stops resolving).
const calcLen = (expr) => {
  const t = String(expr).trim();
  const num = (part) => {
    const q = part.trim();
    if (/^-?[\d.]+px$/.test(q)) return parseFloat(q);
    const v = /^var\((--[a-z0-9-]+)\)$/.exec(q);
    return v ? pxToken(v[1].slice(2)) : NaN;
  };
  // The closing paren is stripped ONLY when there is an opening one to match.
  // `.replace(/\)$/, "")` applied unconditionally silently turns `var(--sidebar-
  // width)` into `var(--sidebar-width` - and then every later stage reports null
  // for a token that resolves perfectly well. Pair the two or neither.
  const opensParen = /^calc\(/.test(t) || /^\(/.test(t);
  let inner = t.replace(/^calc\(/, "").replace(/^\(/, "").trim();
  if (opensParen) inner = inner.replace(/\)$/, "").trim();
  // strip an outer `-1 * (...)` or `(<expr>)`
  const mul = /^-?\d+(?:\.\d+)?\s*\*\s*\((.*)\)$/.exec(inner);
  if (mul) return parseFloat(mul[0].split("*")[0]) * (calcLen(mul[1]) || NaN);
  const paren = /^\((.*)\)$/.exec(inner);
  if (paren) return calcLen(paren[1]);
  // Infix ONLY on a whitespace-delimited operator, and by splitting rather than by
  // regex. `/^(\S+)\s*-\s*(\S+)$/` looks equivalent and is not: it splits inside
  // the token, so `var(--sidebar-width)` came apart as `var(--sidebar` `-` `width)`
  // and recursed until it hit something unresolvable. A `--` in every token name
  // makes any regex keyed on `-` a landmine; splitting on whitespace and requiring
  // exactly three parts with an operator in the middle cannot do that.
  const parts = inner.split(/\s+/);
  if (parts.length === 3 && (parts[1] === "-" || parts[1] === "+")) {
    const a = calcLen(parts[0]);
    const b = calcLen(parts[2]);
    if (a === null || b === null) return null;
    return parts[1] === "-" ? a - b : a + b;
  }
  const n = num(inner);
  return Number.isNaN(n) ? null : n;
};
const padPx = (v) => {
  if (v === null || v === undefined || v === "") return null;
  const t = String(v).trim();
  if (/^calc\(/.test(t)) return calcLen(t);
  const asVar = t.replace(/^var\(--/, "").replace(/\)$/, "");
  return /^var\(/.test(t) ? pxToken(asVar) : parseFloat(t);
};

// EVERY input below, resolved through `axisBodies`, with the declared-once count
// kept so both arithmetic assertions can check all seven at once. See the note
// above `axisUnique` for why the first draft got six of these wrong with
// `bodies(sel)[0]` and why the count half is not optional.
const AXIS_INPUTS = [".sidebar", ".sidebar-content", ".sidebar-menu-button",
  ".sidebar-header", ".sidebar-collapse", ".btn-icon", ".btn-icon-24",
  '.sidebar[data-collapsed="true"]'];
const ax = axisUnique(AXIS_INPUTS);
// Suffixed, because `contentBody` is already bound in section 7 to .app-content's
// body - a different selector entirely, and shadowing it would have quietly
// changed what that assertion measures.
const sidebarRuleBody = ax.got[".sidebar"].body;
const sidebarContentBody = ax.got[".sidebar-content"].body;
const rowBase = ax.got[".sidebar-menu-button"].body;
const sidebarHeadBody = ax.got[".sidebar-header"].body;
const ctrlRuleBody = ax.got[".sidebar-collapse"].body;
const iconPrimBody = ax.got[".btn-icon"].body;
const icon24Body = ax.got[".btn-icon-24"].body;

// The WIDTH comes from the collapsed rule, not from the token. Reading
// `--sidebar-rail-width` looked equivalent and was not: the declaration that
// actually sets the collapsed rail's width is
// `.sidebar[data-collapsed="true"] { width: … }`, and setting THAT to `60px`
// decoupled from the token rendered a 60px rail while both arithmetic assertions
// kept reporting the token's 27.5. Nothing mis-rendered - the centring property
// still held - but the claim that "changing the rail width moves the expected
// centre" only held for one of the two places the width is written.
// `padPx` resolves it, so `width: var(--sidebar-rail-width)` and `width: 60px`
// are both read correctly.
const railDecl = (/width:\s*([^;}]+)/.exec(ax.got['.sidebar[data-collapsed="true"]'].body) || [])[1];
const railPx = railDecl ? padPx(railDecl.trim()) : null;
const borderM = /border-right:\s*(\d+)px/.exec(sidebarRuleBody);
const borderPx = borderM ? parseFloat(borderM[1]) : 0;
// The panel's own PADDING-LEFT is part of the content box, and it is 200px in the
// collapsed state - which is the whole point of the slide. Reading `inner` as
// `width - border` would describe a 255px content box that does not exist on
// screen, and every number below it with it. This is the arithmetic that proves
// the padding-and-transform arrangement is equivalent to the old fixed-56px rail,
// rather than an assertion that it is.
// Mutation: drop `padding-left` from `inner` -> the flank and the centre both go
//            wrong and red.
const panelPad = padPx((/padding-left:\s*([^;}]+)/.exec(railBody) || [])[1]);
const panelTx = padPx(callArg("translateX", railBody));
// NOT `+ panelTx`. The transform moves the box; it does not resize it. The
// content box is 55px and then sits at screen x 0 because the two offsets cancel -
// and that cancellation is what the slide relation asserts separately. Adding the
// transform here would describe a -145px content box and every number below it.
const inner = railPx !== null && borderM && panelPad !== null
  ? railPx - borderPx - panelPad : null;
const halfInner = inner !== null ? inner / 2 : null;
// The slide relation itself, as a separate assertion so a failure names WHICH half
// broke. `translate === -padding-left` is what puts the content box's screen
// origin at 0, and `padding-left === width - rail` is what makes it rail-wide.
// Both literals alone are satisfiable by something broken; together they are the
// mechanism.
// Mutation: padding-left -> `0` -> red (a 256px panel on screen).
// Mutation: transform -> `translateX(0)` -> red (nothing slides).
// Mutation: padding-left -> `180px` -> red (the panel sits 20px proud of the edge).
const slideNumerics = [railPx, panelPad, panelTx].every((v) => v !== null && !Number.isNaN(v));
if (slideNumerics && panelPad === railPx - pxToken("sidebar-rail-width") && panelTx === -panelPad) {
  ok("the rail is a --sidebar-width panel slid " + (-panelTx) + "px left and padded " + panelPad +
     "px, so its right --sidebar-rail-width is what shows - and the transform is exactly -padding-left, which puts the content box's screen origin at 0");
} else {
  bad("the rail is the right-hand window onto a full-width panel",
    "width=" + railPx + " padding-left=" + panelPad + " transform=" + panelTx +
    " (width - rail = " + (railPx !== null && !Number.isNaN(railPx) ? railPx - pxToken("sidebar-rail-width") : "?") +
    " and the transform must be exactly -padding-left) - anything else either leaves a 256px panel on screen or slides nothing");
}

// The item's INLINE padding in the collapsed state, resolved through the cascade
// rather than assumed: the collapsed rule's own padding declarations if it has
// any, else whatever the base rule declares. This is the term the bug lives in,
// so an earlier draft that simply used the CONTAINER's padding computed 27.5 both
// before and after the fix - a green assertion measuring its own assumption,
// which is the trap this file's header names.
// Mutation: delete `padding-left: 0` from the collapsed rule -> red below.
//
// Both sides come back SEPARATELY, because a row's own inline padding is not
// required to be symmetric. The first draft collapsed them to one number, which
// hid an error of exactly |l-r|/2: `padding-left: 4px; padding-right: 0` renders
// the icon at 29.5px, genuinely 2px off, and reported 27.5. Nothing caught it
// except a sibling assertion pinning the literal text `padding-left: 0` - which is
// a spelling, not a guarantee.
// Mutation: `padding-left: 4px; padding-right: 0` -> red below.
const collapsedInlinePad = (collapsedBody, baseBody) => {
  if (HAS_PAD.test(collapsedBody)) return sidePadding(collapsedBody);
  return sidePadding(baseBody);
};
// justify-content, the same cascade resolution. The DEFAULT is flex-start, and
// that default is the shipped bug: an icon packed against the inline start of a
// 56px rail is 8.5px adrift no matter how symmetric its padding is.
const collapsedJustify = (collapsedBody, baseBody) => {
  const m = /justify-content:\s*([^;}]+)/.exec(collapsedBody);
  if (m) return m[1].trim();
  const b = /justify-content:\s*([^;}]+)/.exec(baseBody);
  return b ? b[1].trim() : "flex-start";
};
// Does an auto inline margin still push the item to the trailing edge? An auto
// margin absorbs ALL the free space in a flex row, so `justify-content` is never
// consulted - which is why centring the header without neutralising
// .sidebar-collapse's margin-left: auto changes nothing at all.
const hasAutoLeadingMargin = (collapsedBody, baseBody) =>
  (/margin-left:\s*auto/.test(collapsedBody) || /margin-left:\s*auto/.test(baseBody)) &&
  !/margin-left:\s*0/.test(collapsedBody);

// Where the item's centre actually lands, from those facts and nothing else.
// Single-line flex container, one item, no wrap, no flex-grow:
//   available = inner - padL - padR - inlineL - inlineR
//   auto margin    -> item at the TRAILING edge: inner - padR - inlineR - itemW/2
//   justify:center -> padL + inlineL + (available - itemW)/2 + itemW/2
//   otherwise      -> padL + inlineL + itemW/2   (flex-start, the default)
//
// Null if any input is missing, so a rule that stops declaring one of them turns
// this into a red assertion instead of an arithmetic accident.
const flexItemCentre = (pad, itemW, inline, justify, autoMargin) => {
  if (inner === null || !pad || !inline || itemW === null || Number.isNaN(itemW)) return null;
  // EVERY side goes through padPx, not just the container's. The first draft of
  // this signature took the inline pair as already-numeric, so `l + il` was
  // number + STRING and concatenated: "4" + "0" = "40", which the arithmetic then
  // reported as a centre 40149.5px from the rail. A test that silently coerces
  // types is a test that can pass for the wrong reason, so the conversion is
  // uniform and unmissable.
  const nums = [padPx(pad.l), padPx(pad.r), padPx(inline.l), padPx(inline.r), itemW];
  if (nums.some((n) => n === null || Number.isNaN(n))) return null;
  const [l, r, il, ir] = nums;
  if (autoMargin) return inner - r - ir - itemW / 2;
  const available = inner - l - r - il - ir;
  if (justify === "center") return l + il + (available - itemW) / 2 + itemW / 2;
  return l + il + itemW / 2;
};

// The container's own side padding, and the one function both call sites share.
//
// RESOLUTION ORDER - source order, which is what CSS actually does. Every padding
// declaration in the body is collected WITH ITS INDEX and resolved per side, and
// the last declaration wins: a longhand after a shorthand overrides just that
// side, and a shorthand after a longhand overrides all four.
//
// The two helpers that used to do this each preferred one FORM over the other, in
// OPPOSITE directions - `collapsedInlinePad` longhand-first, `sidePadding`
// shorthand-first - so neither was universally right and the pair contradicted
// itself. Harmless today (no rule in this stylesheet mixes the two), but one of
// them was latently wrong and nothing would have said so. There is now one
// implementation, called from both places, so the two questions cannot disagree
// again.
//
// Per-side rather than per-block, so an ASYMMETRIC pair is representable: `l` and
// `r` come back independently and `flexItemCentre` uses both. A single collapsed
// longhand (`padding-right: 8px` on top of a base `padding: 0`) keeps its 8px
// rather than inheriting a symmetric assumption.
const HAS_PAD = /padding(-left|-right)?:/;
const sidePadding = (body) => {
  const decls = [];
  const re = /padding(-left|-right)?:\s*([^;}]+)/g;
  let m;
  while ((m = re.exec(body)) !== null) {
    decls.push({ side: m[1] || "", values: m[2].trim().split(/\s+/) });
  }
  if (decls.length === 0) return null;
  // The inline value a shorthand supplies: 1 value -> all four sides, 2 ->
  // vertical/horizontal, 3 -> top/horizontal/bottom, 4 -> top/right/bottom/left.
  // Only the 4-value form can make left and right differ.
  const shorthandInline = (values, side) => {
    if (values.length === 1) return values[0];
    if (values.length === 4) return side === "-left" ? values[3] : values[1];
    return values[1];
  };
  const side = (which) => {
    for (let i = decls.length - 1; i >= 0; i--) {
      if (decls[i].side === which) return decls[i].values[0];
      if (decls[i].side === "") return shorthandInline(decls[i].values, which);
    }
    return null;
  };
  const l = side("-left");
  const r = side("-right");
  return l === null || r === null ? null : { l: l, r: r };
};

// The nav row. `width: 100%` is read rather than assumed, because it is what
// makes the button's box the container's whole content box - without it the item
// is only as wide as the icon and the container's padding stops mattering.
const chatRow = query(doc, '[data-destination="chat"]');
const chatSvg = chatRow ? query(chatRow, "svg") : null;
const iconW = chatSvg ? parseFloat(chatSvg.attrs.width) : NaN;
const contentPad = sidePadding(sidebarContentBody);
const rowInline = collapsedInlinePad(collapsedRow.body, rowBase);
const rowCentre = flexItemCentre(contentPad, iconW, rowInline,
  collapsedJustify(collapsedRow.body, rowBase), false);
if (ax.ok && rowCentre !== null && padPx(contentPad.l) === padPx(contentPad.r) &&
    /width: 100%/.test(rowBase) && Math.abs(rowCentre - halfInner) < 1e-9) {
  ok("the collapsed nav row's icon centre IS the rail's midpoint (" + rowCentre +
    "px of a " + inner + "px content box), read through the cascade: zeroed inline padding + justify-content: center on a full-width row");
} else {
  bad("the collapsed nav row's icon centre is the rail's midpoint",
    (!ax.ok ? "declared more than once: " + ax.why + "; " : "") +
    "collapsedWidth=" + railPx + " border-right=" + borderPx + " inner=" + inner + " midpoint=" + halfInner +
    " containerPadding=" + JSON.stringify(contentPad) + " iconWidth=" + iconW +
    " inlinePad=" + JSON.stringify(rowInline) +
    " justify=" + collapsedJustify(collapsedRow.body, rowBase) +
    " width100=" + /width: 100%/.test(rowBase) + " centre=" + rowCentre +
    " - off by " + (rowCentre === null ? "?" : Math.abs(halfInner - rowCentre)) +
    "px; an icon packed at the flex start, one still carrying the base rule's inline padding, or asymmetric inline padding, each do this");
}

// The collapse control, through the same model on a different container and a
// DIFFERENTLY SHAPED item: a fixed 24px rather than a full-width row, so there is
// real free space for justify-content to distribute and the auto margin has
// something to absorb. Checked on both branches deliberately - a surviving
// `margin-left: auto` is invisible to any declaration assertion about the header
// and is exactly what puts this control 7.5px off the midpoint.
const headPad = sidePadding(sidebarHeadBody);
const ctrlW = (() => {
  const m = /width:\s*([\d.]+)px/.exec(icon24Body);
  return m ? parseFloat(m[1]) : NaN;
})();
// .btn-icon sets `padding: 0`, so the control has no inline padding of its own to
// resolve - 0 is read off the primitive rather than assumed here. Both sides,
// because the primitive is read the same way everything else is.
const ctrlInline = sidePadding(iconPrimBody);
const ctrlCentre = flexItemCentre(headPad, ctrlW,
  (/padding:\s*0/.test(iconPrimBody) ? { l: 0, r: 0 } : ctrlInline),
  collapsedJustify(collapsedHeader.body, ""),
  hasAutoLeadingMargin(collapsedCollapse.body, ctrlRuleBody));
if (ax.ok && ctrlCentre !== null && Math.abs(ctrlCentre - halfInner) < 1e-9) {
  ok("the collapsed collapse control lands on the same midpoint (" + ctrlCentre +
    "px) - a fixed 24px item, centred, with margin-left: auto neutralised");
} else {
  bad("the collapsed collapse control lands on the rail's midpoint",
    (!ax.ok ? "declared more than once: " + ax.why + "; " : "") +
    "headerPadding=" + JSON.stringify(headPad) + " controlWidth=" + ctrlW +
    " autoMargin=" + hasAutoLeadingMargin(collapsedCollapse.body, ctrlRuleBody) +
    " centre=" + ctrlCentre + " midpoint=" + halfInner +
    " - a surviving margin-left: auto absorbs all the free space and pins it to the trailing edge, whatever justify-content says");
}

// --- and the SLIDE cannot relayout the content ------------------------------
// The reported bug: "when hovering over the sidebar, the icons seem to jump a lot
// from their positions". Measured in Firefox 156 with real pointer input and one
// rAF sample per frame, on the shipped file:
//
//   hover OUT   icon centre        127.5 -> 27.5, thirteen distinct samples
//               collapse control   235.0 -> 27.5
//   hover IN    icon centre         27.5 -> 20.5 in the FIRST frame, then 20.5
//                                    for every remaining frame
//               row left edge      4.0 throughout, in both directions
//
// Which says the padding animation was never what carried the icons. Its two edges
// CANCEL - padding-left rises exactly as fast as translateX falls, because the
// slide relation above pins the content box's screen origin at 0 - so no row and
// no region ever moves horizontally. What moves is the content box's WIDTH,
// 55 -> 255 and back, and `justify-content: center` makes every centred item's
// position a function of that width: padL + (available - item)/2 + item/2. On the
// way out the collapsed rule's centring re-applies while the row is still 247px
// wide, so each icon lands on the middle of a 247px row - 127.5px, four and a half
// rail widths from where it was - and then rides the shrinking box down to 27.5.
// 107px and 207px are not slips; they are that arithmetic running on a width that
// is halfway between the two states.
//
// So the three regions are given the rail's width outright, and the invariant is
// that WHILE COLLAPSED THE CONTENT IS A RAIL OR A COLUMN, NEVER A HYBRID. Three
// assertions, and they are three different questions on purpose:
//
//   1. STRUCTURE - all three regions declare the rail's width, declared once each.
//   2. THE IDENTITY - and that width is the SAME NUMBER the panel's own content
//      box measures at rest, so it cannot be a second, drifting copy of the
//      geometry. `inner` is derived from the panel (256 - 1px border - 200px
//      padding); the region width is derived from the rail (56 - 1px border); the
//      two are algebraically the same expression, so this compares them rather
//      than trusting either.
//   3. BEHAVIOUR - the icon's centre computed from the REGION's own declared width,
//      through the same centring model the two assertions above use, is the rail's
//      midpoint. This is the one that can fail for a reason that is not a spelling:
//      a region's width that is a percentage, `auto`, or a function of the panel's
//      padding resolves to something else here, and the centre moves.
//
// The counterfactual, recorded because it is what makes assertion 3 worth having
// and not merely redundant: feed the same model the OPEN end of the slide instead
// and it reports 127.5, not 27.5. Nothing above stops that number except the width
// declaration assertion 1 reads - which is why 1 and 3 are both here.
//
// Mutation: delete `width:` from any of the three collapsed region rules -> 1 and 3
//            red, 2 red (its input is gone).
// Mutation: `calc(var(--sidebar-rail-width) - 1px)` -> `100%` -> 1 red, 2 red, 3 red.
// Mutation: `calc(var(--sidebar-rail-width) - 1px)` -> `60px` -> 1 red, 2 red
//            (60 is not 55), 3 red (centre 32.5).
// Mutation: the rail token 56px -> 50px -> all three stay GREEN, and that is
//            correct: 50 - 1 = 49 = the panel's content box at the same token, so
//            the identity holds and the midpoint moves with it. `inner`, `halfInner`
//            and the modelled centre are all read from the sources for that reason.
const RAIL_REGIONS = [".sidebar-header", ".sidebar-content", ".sidebar-footer"];
const regionDecl = RAIL_REGIONS.map((s) => {
  const b = axisBodies('.sidebar[data-collapsed="true"] ' + s);
  return { sel: s, n: b.n,
    width: b.n === 1 ? padPx((/width:\s*([^;}]+)/.exec(b.body) || [])[1]) : null,
    body: b.body };
});
const regionsOnce = regionDecl.every((r) => r.n === 1);
if (regionsOnce && regionDecl.every((r) => r.width !== null && !Number.isNaN(r.width))) {
  ok("while collapsed, all three regions declare a width - once each - so the sidebar's interior is sized by something other than the panel's animated padding");
} else {
  bad("while collapsed, all three regions declare a width",
    regionDecl.map((r) => r.sel + " x" + r.n + " width=" + r.width).join("  |  ") +
    " - without one, each region stretches to the panel's content box, which the animated padding-left carries continuously between 55px and 255px");
}
// The identity. `inner` is the panel's content box at rest; the region width is
// `var(--sidebar-rail-width) - 1px`. Comparing them is what makes this an identity
// rather than a restatement - and it is the half that survives a token change.
if (regionsOnce && regionDecl.every((r) => r.width === inner) && inner !== null) {
  ok("the rail regions' width IS the panel's content box at rest (" + inner +
    "px, from both sides: 256 - 1px border - 200px padding, and 56 - 1px border) - so it is the same expression, not a second number to keep in step");
} else {
  bad("the rail regions' width is the same number as the panel's content box",
    "panel content box=" + inner + "  regions=" +
    regionDecl.map((r) => r.sel.split("sidebar-")[1] + "=" + r.width).join(", ") +
    " - a region width that is not this number either relayouts mid-slide or freezes the open column");
}
// The behaviour. Same model as the two centring assertions, but the container's
// width is the REGION's declaration rather than the panel's - which is the whole
// difference between "a width is declared" and "the icon cannot move".
const modelledCentre = (containerW, pad, itemW) => {
  if (containerW === null || !pad || itemW === null || Number.isNaN(itemW)) return null;
  const l = padPx(pad.l), r = padPx(pad.r);
  if (l === null || r === null || Number.isNaN(l) || Number.isNaN(r)) return null;
  return l + (containerW - l - r - itemW) / 2 + itemW / 2;
};
// By NAME, not by index: `RAIL_REGIONS[1]` happens to be .sidebar-content, and an
// assertion that reads the container it is modelling out of a positional lookup is
// one reordering away from quietly modelling the header instead - which is the
// "a name asserting something the code does not measure" shape this file's header
// warns about. The nav rows live in .sidebar-content, so that is the one asked for.
const railContent = regionDecl.find((r) => r.sel === ".sidebar-content");
const railCentre = modelledCentre(railContent ? railContent.width : null, contentPad, iconW);
if (regionsOnce && railCentre !== null && halfInner !== null &&
    Math.abs(railCentre - halfInner) < 1e-9 && /width: 100%/.test(rowBase)) {
  ok("the icon's centre computed from the REGION's own width is the rail's midpoint (" +
    railCentre + "px) - a function of the region alone, so it is that number whether " +
    "the panel's padding-left is 200 or 0, and the slide cannot move an icon");
} else {
  bad("the icon's centre, computed from the region's own width, is the rail's midpoint",
    "contentWidth=" + (railContent ? railContent.width : "<no .sidebar-content>") +
    " containerPadding=" + JSON.stringify(contentPad) +
    " iconWidth=" + iconW + " centre=" + railCentre + " midpoint=" + halfInner +
    " width100=" + /width: 100%/.test(rowBase) +
    " - the counterfactual is the point: this same model fed the OPEN end of the slide (255px) reports 127.5, which is where the icons used to fly from");
}

if ((top.bySel.get(".sidebar-tier") || []).length === 1) {
  ok(".sidebar-tier is a declared row group, not an unstyled div");
} else {
  bad(".sidebar-tier is a declared row group", "it has no rule, so it lays out as a bare block");
}
if ((top.bySel.get(".sidebar-menu-button.active") || []).length === 1) {
  ok(".sidebar-menu-button.active exists, so the tier rows can read as a choice");
} else {
  bad(".sidebar-menu-button.active exists", "the tier rows would carry no active state at all");
}

// The Drive panel is the one surface that was `position: fixed` over the whole
// viewport, which as a child of #app meant it covered the nav column - opening
// Drive on a desktop made the sidebar disappear. It is absolute now. Three
// things have to hold for it to stay inside the frame, and they live in three
// different assertions on purpose, because they are three different files:
//
//   - this one:      its own `position: absolute` and header offset
//   - `.app-content is position: relative` (section 7): the containing block
//   - `the five surfaces are children of .app-content` (section 1): the parent
//
// Deleting any one of the three puts the panel back over the sidebar, and before
// the review round that caught this only the first was asserted - the assertion's
// TEXT said "inside .app-content" and its CODE checked neither containment nor
// containing block.
// Mutation: put `position: fixed` back -> red.
// Mutation: delete `position: relative` from .app-content -> red above.
// Mutation: re-parent #drivePanel out of .app-content -> red in section 1.
const driveBody = (top.bySel.get(".drive-panel") || [])[0] || "";
if (/(^|[\s;])position: absolute([\s;]|$)/.test(driveBody) &&
    /top: var\(--header-height\)/.test(driveBody) &&
    !/(^|[\s;])position: fixed([\s;]|$)/.test(driveBody)) {
  ok(".drive-panel declares position: absolute at --header-height (its container and parent are asserted above)");
} else {
  bad(".drive-panel declares position: absolute at --header-height",
    "got: " + (driveBody || "<no rule>") +
    " - as a fixed child of #app it spans the viewport and paints over the sidebar");
}
if (!/height: 100%/.test(driveBody) && !/height: 100%/.test((top.bySel.get(".drive-panel") || []).join(" "))) {
  ok(".drive-panel carries no height: 100% - it would beat `bottom: 0` and hang below the fold");
} else {
  bad(".drive-panel carries no height: 100%", "it would override `bottom: 0` and overflow the shell");
}

// ---------------------------------------------------------------------------
// 8. The sheet has to stay UNDER the header band, not over the composer.
// ---------------------------------------------------------------------------

const sheetBody = (top.bySel.get(".sheet") || [])[0] || "";
if (/position: fixed/.test(sheetBody) && /z-index: var\(--z-top\)/.test(sheetBody)) {
  ok(".sheet is fixed and takes its rung from the scale");
} else {
  bad(".sheet is fixed and takes its rung from the scale", "got: " + (sheetBody || "<no rule>"));
}
const overlayBody = (top.bySel.get(".sheet-overlay") || [])[0] || "";
if (/position: fixed/.test(overlayBody) && /z-index: var\(--z-modal\)/.test(overlayBody)) {
  ok(".sheet-overlay is fixed and takes a LOWER rung than .sheet");
} else {
  bad(".sheet-overlay is fixed and takes a lower rung than .sheet", "got: " + (overlayBody || "<no rule>"));
}
// The phone drawer now SLIDES IN. An animation rather than a transition, because
// the sheet ships `hidden` and `display: none` has no box for a transition to
// interpolate between; pushOverlay() un-hides it and the keyframes run from the
// first rendered frame. The -100% is against `left: 0`, so it means "off the
// left edge of the screen" rather than "off the card".
// Mutation: delete the animation declaration -> red.
// Mutation: 0% in place of 100% -> red (it would slide IN from off-screen right).
// Mutation: delete @keyframes sheet-slide-in -> red.
// ONE rule at the top level and one inside the prefers-reduced-motion block, and
// `bodies()` can only see the first - it blanks every at-rule body. So the count
// here is deliberately NOT taken from it: the cascade-order question is
// test_primitives.sh section 19's `expect_n`, which does see both, and a second
// count here would be a second number to keep in step for no extra information.
// An earlier version of this computed one anyway and never read it; a computed
// value nobody tests is the shape this file just found in three places, so it is
// deleted rather than justified.
if (bodies(".sheet").length === 1 &&
    /animation: sheet-slide-in var\(--duration-slow\) var\(--ease\)/.test(sheetBody)) {
  ok(".sheet slides in at the root; the reduced-motion arm above is the only thing that stops it");
} else {
  bad(".sheet slides in at the root",
    (bodies(".sheet") || []).join("  ||  "));
}
const sheetFrames = /@keyframes sheet-slide-in\s*\{([\s\S]*?)\n {4}\}/.exec(cssNoComments);
if (sheetFrames && /from\s*\{\s*transform: translateX\(-100%\);\s*\}/.test(sheetFrames[0]) &&
    /to\s*\{\s*transform: translateX\(0\);\s*\}/.test(sheetFrames[0])) {
  ok("sheet-slide-in travels from -100% to 0 - off the left edge, and no scrim or opacity fades in");
} else {
  bad("sheet-slide-in travels from -100% to 0",
    "got: " + (sheetFrames ? sheetFrames[0] : "<no @keyframes sheet-slide-in>"));
}

// ---------------------------------------------------------------------------
// 9. FIX 6: the rail tooltips. Three separable claims, plus the one that makes
//    the string duplication survivable.
// ---------------------------------------------------------------------------

// (1) EXISTENCE, and CSS-only. `content: attr(data-tooltip)` is the whole
// mechanism; no JS may generate, set or clear the attribute, because a tooltip
// that needs a script is not a tooltip.
// Mutation: replace `content: attr(data-tooltip)` with a literal -> red.
// Mutation: add `btn.dataset.tooltip = …` to the JS -> red.
const tipBody = bodies('.sidebar[data-collapsed="true"] .sidebar-menu-button::after')[0] || "";
if (/content: attr\(data-tooltip\)/.test(tipBody) && /position: absolute/.test(tipBody) &&
    /left: 100%/.test(tipBody) && /opacity: 0/.test(tipBody) &&
    !/tooltip/.test(jsSrc.replace(/\/\*[\s\S]*?\*\//g, "").replace(/data-tooltip[^\n]*/g, ""))) {
  ok("the rail tooltip is a ::after driven by attr(data-tooltip), and no JS touches it");
} else {
  bad("the rail tooltip is a ::after driven by attr(data-tooltip)",
    "got: " + (tipBody || "<no rule>"));
}

// (2) COLLAPSED-ONLY, by selector. Every rule in the family is written
// `.sidebar[data-collapsed="true"] …`, so an expanded sidebar cannot produce a
// chip next to a label that is already showing. Asked as a question about the
// WHOLE family rather than one rule, because the trigger and the suppression are
// two more rules with the same prefix and a chip that ignored the collapsed state
// would come from one of those.
// Mutation: un-scope the ::after rule -> red.
// DERIVED from the stylesheet rather than listed, because a hardcoded list has to
// be edited every time the family grows and nothing says so - which is how the
// previous version of this assertion went blind: it named three selectors, the
// family became four, and it stayed green while one of them was unreachable.
const chipSels = [...top.bySel.keys()].filter((s) => /::after/.test(s) && /sidebar-menu-button/.test(s)).sort();
// Only the CHIP family's rules are in scope for the claim - `chipSels` above is
// already filtered to them. `.radio:checked::after`, `.checkbox:checked::after`
// and `.chat-dropzone-active::after` are unrelated pre-existing rules, and asking
// about them would be asking a question this assertion has no answer to.
const unscoped = chipSels.filter((k) => !/data-collapsed/.test(k));
// FIVE, not three or four: base, the two-arm show rule, and the suppression -
// which is now TWO selectors, the hover arm and the focus arm, because it answers
// "the column is open" rather than only "focus is inside on a non-row". The
// `:active` arm of `@media (hover: none)` is the fifth and is deliberately NOT in
// this count - `withoutAtRuleBodies` blanks every at-rule body, so asking for five
// here would report four and send someone looking for a bug that is not there.
//
// FIVE SELECTORS, and the count is of SELECTORS rather than declarations, which is
// a distinction this file has been caught by before: the retirement of the chip
// added a SIXTH declaration - `content: none` on the base recipe's own selector -
// and `chipSels` counts keys, so it did not move. That is correct for what this
// assertion asks (which selectors exist, and are they all scoped to the collapsed
// sidebar) and it is why the retirement needs its own assertion, below, rather
// than being folded in here as a sixth.
//
// `Object.keys()` on a Map returns `[]` and every predicate built on it is
// VACUOUS. That is not hypothetical: this assertion's earlier form was
// `Object.keys(top.bySet).every(k => !/::after/.test(k) || /data-collapsed/.test(k))`,
// which is trivially true of an empty array and would have passed with the chip
// family unscoped. `[...map.keys()]` is the only correct spelling, and the comment
// above `top` saying "two maps come back" is where the mistake came from.
// Mutation: un-scope the ::after rule -> red.
if (chipSels.length === 5 && unscoped.length === 0) {
  ok("the chip family is five SELECTORS (base, two-arm show, two-arm suppression), all scoped to the collapsed sidebar - the selectors are retained for the chip to be restorable, not because any of them can currently paint");
} else {
  bad("the chip family is five selectors, all scoped to the collapsed sidebar",
    "found " + chipSels.length + ": " + chipSels.join(" | ") +
    "; unscoped ::after rules: " + (unscoped.join(", ") || "<none>"));
}

// (2b) THE RETIREMENT, which is the one assertion in this family that is about
// what the chip DOES rather than what survives of it. The user asked for the chip
// to be gone from the UX with its code left in the file, so the claim to test is
// precisely "no box is generated" - and "no box is generated" is a stronger and
// much easier-to-check statement than any opacity, because a pseudo-element with
// `content: none` is not laid out, not measured and not hit-testable. An
// `opacity: 0` chip would satisfy an opacity assertion while still being there.
//
// Four things, because each fails differently:
//
//   1. `content: none` is declared on the chip's own base selector. On any other
//      selector it would suppress the wrong pseudo-element.
//   2. it is declared LAST for that selector - `content` is only set by the base
//      recipe, so the retirement is decided by source order at equal specificity,
//      and "equal specificity" is the claim worth asserting rather than assuming.
//   3. the base recipe still says `content: attr(data-tooltip)`, i.e. the chip's
//      mechanism is intact and only the retirement was added. Without this, a
//      reader could satisfy the assertion by gutting the recipe instead, and the
//      "restorable by deleting one declaration" promise would be a lie.
//   4. nothing else in the family declares `content`, so there is no second
//      writer for the property to lose to. ONE selector, not two: every other
//      rule in the family animates `opacity`, which is precisely why
//      `content: none` beats all of them - it is a different property, so no
//      amount of opacity anywhere can out-rank it. An earlier draft of this
//      expected two writers and went red against a correct stylesheet, which is
//      the same "I asserted a number I had not measured" mistake this file has
//      now made twice; the number below is the measured one.
//
// Mutation: delete the `content: none` rule -> red (the chip is back).
// Mutation: move it ABOVE the base recipe -> red.
// Mutation: change `attr(data-tooltip)` to a literal -> red (assertion 1).
// Mutation: add `content: attr(data-tooltip)` to the show arm -> red (assertion 4).
const CHIP_BASE = '.sidebar[data-collapsed="true"] .sidebar-menu-button::after';
const chipBaseDecls = selBodies(CHIP_BASE);
const chipBaseLast = chipBaseDecls[chipBaseDecls.length - 1] || "";
const chipBaseFirst = chipBaseDecls[0] || "";
const contentWriters = chipSels
  .map((s) => [s, selBodies(s)])
  .filter((pair) => pair[1].some((b) => /(^|;)\s*content\s*:/.test(" " + b + " ")))
  .map((pair) => pair[0]);
const retirementOK = chipBaseDecls.length === 2 &&
  /content:\s*none/.test(chipBaseLast) &&
  /content:\s*attr\(data-tooltip\)/.test(chipBaseFirst) &&
  contentWriters.length === 1 &&
  contentWriters[0] === CHIP_BASE;
if (retirementOK) {
  ok("the chip cannot paint: `content: none` is declared on its own base selector AFTER the `content: attr(data-tooltip)` recipe, and that selector is the family's only writer of `content` - so the recipe is intact and the retirement is one line to undo");
} else {
  bad("the chip is retired by `content: none`, declared last on its own base selector",
    chipBaseDecls.length + " declaration(s) for " + CHIP_BASE + ": [" + chipBaseDecls.join(" || ") + "]" +
    "; selectors in the family that declare content: [" + (contentWriters.join(", ") || "none") + "]" +
    " - above the recipe is dead code, below it is the retirement; a second writer means something else can decide the property");
}

// (3) ESCAPING THE CLIP. This is the part that is easy to ship broken: a tooltip
// that lays out and is then cut in half by an ancestor's overflow is worse than
// no tooltip, because it looks like a rendering bug rather than a missing one.
// Two halves, because either alone is not enough:
//
//   a. `.sidebar[data-collapsed="true"]` overrides the base `overflow: hidden`
//      with `overflow: visible`. A pseudo-element is a DESCENDANT for clipping
//      purposes, so this is the only thing that lets a chip render outside the
//      56px column. The EXPANDED sidebar must KEEP its clip - at 256px there is
//      nothing to escape and it is what stops an overlong label bleeding into the
//      chat - so this is an override of one rule and not a deletion of both.
//   b. the row is `position: relative`, so `left: 100%` is measured from the ROW
//      rather than from the viewport. Without it the chip would anchor to the
//      nearest positioned ancestor and land wherever that was.
// Mutation: delete `overflow: visible` from the collapsed rule -> red.
// Mutation: delete `overflow: hidden` from .sidebar -> red (the expanded clip is
//            still wanted).
// Mutation: delete `position: relative` from .sidebar-menu-button -> red.
const expandedStillClips = /overflow: hidden/.test(bodies(".sidebar")[0] || "");
const rowIsPositioned = /position: relative/.test(bodies(".sidebar-menu-button")[0] || "");
// (3a) THE GENERAL FORM, and it is the general form because the specific one is
// what shipped broken. The review measured Firefox 156 clipping eight of the ten
// chips at 53px: `.sidebar`'s own `overflow: visible` was necessary and was not
// sufficient, because `.sidebar-content` carries `overflow-y: auto` and a `visible`
// on one axis computes to `auto` whenever the other axis is not visible. An
// assertion that named `.sidebar` alone went green with eight chips invisible,
// and deleting `overflow-y: auto` outright - what a real fix looks like - left
// every suite green too.
//
// So: walk every ancestor between a chip's row and `.sidebar` in the PARSED
// MARKUP, and require that none of them declares any `overflow` other than
// `visible` in the collapsed state. The collapsed-state answer for each is
// resolved through the cascade - its own `[data-collapsed="true"] …` rule if it has
// one, else its base rule - so the check follows the fix rather than pinning the
// spelling of it, and a THIRD clipper added to any box in between is caught without
// anyone remembering to extend a list.
//
// The knock-on the review measured is covered by the same walk: a box that scrolls
// on an axis is what makes `scrollWidth > clientWidth`, and that is what lets the
// rail be scrolled sideways out of its own icons.
// Mutation: add `overflow: hidden` to `.sidebar-group` -> red.
// Mutation: put `overflow: auto` on `.sidebar-menu` -> red.
// Mutation: `.sidebar-content` back to `overflow-y: auto` -> red.
// Mutation: delete `.sidebar-content`'s collapsed override -> red.
const CLIP_CHAIN = (() => {
  const row = query(doc, ".sidebar-menu-button");
  const chain = [];
  for (let n = row; n && n !== sidebar; n = n.parent) chain.push(n);
  chain.push(sidebar);
  const offenders = [];
  const seen = [];
  for (const el of chain) {
    const cls = [...el.classes][0];
    if (!cls) continue;
    // `.sidebar` itself carries the attribute, so its collapsed rule is
    // `.sidebar[data-collapsed="true"]` and not a descendant of it - two spellings
    // to try, or the walk flags the sidebar with its OWN base `overflow: hidden`
    // and the assertion is red for a reason that has nothing to do with the chip.
    const collapsed = el === sidebar
      ? selBodies('.sidebar[data-collapsed="true"]')
      : selBodies('.sidebar[data-collapsed="true"] .' + cls);
    const base = selBodies("." + cls);
    const body = (collapsed.length ? collapsed : base)[0] || "";
    seen.push(cls + "{" + body + "}");
    const m = /overflow(?:-[xy])?\s*:\s*([^;}]+)/.exec(body);
    const v = m ? m[1].trim() : "visible";
    if (v !== "visible") offenders.push(cls + " { overflow: " + v + " }");
  }
  return { offenders: offenders, seen: seen, depth: chain.length };
})();
// The row itself: a chip's own box must not scroll it away, and the row declares no
// overflow today - which the walk above would not notice, because it stops at the
// row's parent.
const rowOverflow = /overflow/.test(bodies(".sidebar-menu-button")[0] || "");
const escapeOK = CLIP_CHAIN.offenders.length === 0 && !rowOverflow &&
  expandedStillClips && rowIsPositioned;
if (escapeOK) {
  ok("nothing between a row and .sidebar clips in the collapsed state (walked " +
     CLIP_CHAIN.depth + " boxes), the expanded sidebar still clips, and the row is the containing block");
} else {
  bad("nothing between a row and .sidebar clips in the collapsed state",
    "offenders: " + (CLIP_CHAIN.offenders.join(" ;; ") || "<none>") +
    "; the row itself scrolls: " + rowOverflow +
    "; expanded overflow:hidden=" + expandedStillClips + " row position:relative=" + rowIsPositioned +
    "; walked: " + CLIP_CHAIN.seen.join(" | "));
}

// (4) THE STRING IS DUPLICATED, and this is what makes that survivable. CSS can
// read an attribute; it cannot read a descendant's text, and the labels already
// exist as <span>s which the collapsed rail hides. So `data-tooltip` restates
// each row's own label, and THIS is the assertion that keeps the two in step - a
// comment asking a reader to keep them in step is not evidence.
// Mutation: change one data-tooltip -> red.
// Mutation: change one label <span> -> red.
// Mutation: remove a data-tooltip -> red.
const tipRows = queryAll(doc, ".sidebar-menu-button");
let tipStray = [];
let tipMissing = [];
for (const b of tipRows) {
  const label = (b.children.find((c) => c.tagName === "span" && c.children.length === 0 &&
    (!c.attrs.class || c.attrs.class === "")) || {}).text;
  const want = b.attrs["data-tooltip"];
  if (want === undefined) { tipMissing.push(b.attrs.id || b.attrs["data-destination"] || "<row>"); continue; }
  if (want !== label) tipStray.push((b.attrs.id || "<row>") + ": '" + want + "' vs '" + label + "'");
}
if (tipRows.length === 10 && tipMissing.length === 0 && tipStray.length === 0) {
  ok("every one of the ten rows carries a data-tooltip that IS its own visible label");
} else {
  bad("every row's data-tooltip is its own visible label",
    "missing: [" + tipMissing.join(", ") + "] mismatched: [" + tipStray.join("; ") + "]");
}

// (5) The chip's chrome, read off the rule rather than off taste: --popover
// behind a --border hairline at --radius-lg in --text-2xs, sitting to the RIGHT
// of the icon and vertically centred on it. The radius is the CONTROL & SURFACE
// role - the one role in this file's four-role ladder that covers a small
// floating label - and test_scales.sh section 7 refuses any value off the ladder.
// Mutation: `var(--card)` for `var(--popover)` -> red.
// Mutation: `--radius-xl` -> red.
// Mutation: `left: 0` -> red.
const tipSkin = /background: var\(--popover\)/.test(tipBody) &&
  /border: 1px solid var\(--border\)/.test(tipBody) &&
  /border-radius: var\(--radius-lg\)/.test(tipBody) &&
  /font-size: var\(--text-2xs\)/.test(tipBody) &&
  /font-family: var\(--font-sans\)/.test(tipBody) &&
  /top: 50%/.test(tipBody) && /transform: translateY\(-50%\)/.test(tipBody) &&
  /white-space: nowrap/.test(tipBody) &&
  /pointer-events: none/.test(tipBody);
if (tipSkin) {
  ok("the chip is --popover over a --border hairline at --radius-lg in --text-2xs, centred on the icon's row and inert to the pointer");
} else {
  bad("the chip states its whole recipe", "got: " + (tipBody || "<no rule>"));
}

// (6) THE TWO TRIGGERS, AND WHY THEY SHARE ONE RULE.
//
// Hover of the row is the mouse half and `:focus-visible` is the keyboard half.
// Neither replaces the other, so both selectors sit in ONE rule - which is
// asserted as a single body rather than as two rules, because that is what makes
// "someone deleted one arm and left the other" visible here instead of being a
// silent loss of an input.
//
// This is the second two-selector rule in this file where reading one arm would be
// vacuous: `.sidebar-menu-button:hover::after` and `…:focus-visible::after` share a
// body, and a check that read only the focus arm would have gone green on the
// hover arm being deleted - which is exactly the regression the correction was for.
// Mutation: delete `:hover::after` from the pair -> red.
// Mutation: delete `:focus-visible::after` -> red.
// Mutation: `opacity: 1` -> `opacity: 0` -> red.
const CHIP_SHOW_HOVER = '.sidebar[data-collapsed="true"] .sidebar-menu-button:hover::after';
const CHIP_SHOW_FOCUS = '.sidebar[data-collapsed="true"] .sidebar-menu-button:focus-visible::after';
const showHover = selBodies(CHIP_SHOW_HOVER);
const showFocus = selBodies(CHIP_SHOW_FOCUS);
const showBody = showHover[0] || "";
if (showHover.length === 1 && showFocus.length === 1 &&
    /opacity: 1/.test(showBody) && showBody === (showFocus[0] || "")) {
  ok("the chip's show arms are RETAINED on BOTH row hover and row focus-visible, from one rule - inert, but neither input was quietly dropped");
} else {
  bad("the chip's show arms are retained on both row hover and row focus-visible",
    "hover: " + (showHover.length + " rule(s): " + (showBody || "<none>")) +
    "; focus-visible: " + (showFocus.length + " rule(s): " + (showFocus[0] || "<none>")) +
    " - these are load-bearing history: they are what a restored chip needs, and a half-deleted pair would restore it broken");
}

// (7) THE SUPPRESSION, RETAINED AND INERT. Its arms were rewritten when the open
// state was, and the reason they were rewritten rather than left pointing at the
// old selectors is the point of this assertion:
//
// The chip's `left: 100%` is measured from its ROW, so it is only correct while
// the rail is 56px wide, and the column opening under a chip is the conflict it
// exists to prevent. Both of its arms used to be the old carved-up compounds -
// `:hover:not(:has(.sidebar-menu-button:hover))` and
// `:focus-within:not(:has(.sidebar-menu-button:focus-visible))` - and leaving
// them there would have been a rule naming selectors that no longer exist in the
// stylesheet. It would still have been "harmless" while the chip was off, and
// that is precisely the failure mode worth catching: the reader who deletes the
// `content: none` below to restore the chip would get a chip whose suppression
// silently stopped matching, and it would show over the open column - the exact
// bug this rule was written to prevent, reintroduced by the restoration itself.
//
// So the arms are asserted to be the LIVE open-state selectors, the same constants
// every other open rule uses. If they are the same strings, a restored chip
// behaves; if they are not, this goes red while the chip is still off, which is
// the only moment the question can be answered cheaply.
//
// Two arms, both asserted, and the count is checked per arm: `selBodies` keys on
// individual selectors, so a rule listing the hover arm and a rule listing only
// the focus arm look identical to it. That was not hypothetical - the first
// version of this assertion read one arm and passed.
// Mutation: freeze either arm back to the old `:not(:has(...))` compound -> red.
// Mutation: delete the hover arm -> red.
// Mutation: delete the focus arm -> red.
// Mutation: drop `opacity: 0` from the body -> red.
// Mutation: delete the rule -> red.
const ROWSPAN = '.sidebar-menu-button::after';
const SUPPRESS_HOVER = SLIDE_HOVER + " " + ROWSPAN;
const SUPPRESS_FOCUS = SLIDE_FOCUS + " " + ROWSPAN;
// The frozen old arms, spelled out here rather than reconstructed, so that "the
// arms have not gone back to the pre-Item-3 compounds" is a comparison against
// bytes somebody chose rather than against a pattern that might also match
// something new.
const FROZEN_HOVER = '.sidebar[data-collapsed="true"]:hover:not(:has(.sidebar-menu-button:hover)) ' + ROWSPAN;
const FROZEN_FOCUS = '.sidebar[data-collapsed="true"]:focus-within:not(:has(.sidebar-menu-button:focus-visible)) ' + ROWSPAN;
const suppressHover = selBodies(SUPPRESS_HOVER);
const suppressFocus = selBodies(SUPPRESS_FOCUS);
const frozenSuppressions = selBodies(FROZEN_HOVER).length + selBodies(FROZEN_FOCUS).length;
const suppressBody = suppressHover[0] || "";
const suppressOK = suppressHover.length === 1 && suppressFocus.length === 1 &&
  /opacity: 0/.test(suppressBody) && suppressBody === (suppressFocus[0] || "") &&
  frozenSuppressions === 0;
if (suppressOK) {
  ok("the chip's suppression is retained and points at the LIVE open-state arms on both of them - so deleting the `content: none` restores a chip that is correctly suppressed");
} else {
  bad("the chip's suppression carries BOTH live open-state arms",
    "hover arm: " + suppressHover.length + " rule(s): " + (suppressBody || "<none>") +
    "; focus arm: " + suppressFocus.length + " rule(s): " + (suppressFocus[0] || "<none>") +
    "; rules still frozen on the pre-Item-3 compounds: " + frozenSuppressions +
    " - those name selectors that no longer exist, so a restored chip would ignore them");
}

// ---- M6: the specificity the suppression depends on, computed not asserted ----
// The hover suppression beats both `opacity: 1` arms because of the specificity
// its `:not()` argument contributes, not because of where it is written. Nothing
// in the stylesheet says that, and source order would decide it if the argument
// were ever dropped - so the arithmetic is computed here from the four selectors
// rather than left as a claim in a comment.
// A real recursive-descent specificity reader, because the shortcut is wrong in
// both directions. Counting `:`-pseudo-classes with a regex double-counts the ones
// inside `:not(...)` and `:has(...)` - `:hover:not(:has(.a:hover))` came out at 12
// against a true 6 - and a single regex cannot know which `:has()` argument is the
// most specific, which is the entire rule for `:is()`, `:not()` and `:has()`.
//
// Grammar handled: ids, classes, attribute selectors, pseudo-CLASSES (including
// the functional three), pseudo-ELEMENTS. Anything unrecognised returns null so a
// selector it cannot read makes the assertion RED rather than silently scoring 0.
function specOf(sel) {
  const text = sel.trim();
  let i = 0, a = 0, b = 0, c = 0;
  const FUNCS = ["is", "not", "has"];
  while (i < text.length) {
    const ch = text[i];
    if (/\s/.test(ch)) { i++; continue; }
    if (ch === "#") {
      const m = /#([\w-]+)/.exec(text.slice(i));
      if (!m) return null;
      a++; i += m[0].length; continue;
    }
    if (ch === ".") {
      const m = /\.([A-Za-z][\w-]*)/.exec(text.slice(i));
      if (!m) return null;
      b++; i += m[0].length; continue;
    }
    if (ch === "[") {
      const j = text.indexOf("]", i);
      if (j === -1) return null;
      b++; i = j + 1; continue;
    }
    if (ch === ":") {
      if (text[i + 1] === ":") {                     // a pseudo-ELEMENT
        const m = /^::[\w-]+/.exec(text.slice(i));
        if (!m) return null;
        c++; i += m[0].length; continue;
      }
      const m = /^:([\w-]+)/.exec(text.slice(i));
      if (!m) return null;
      const name = m[1];
      let j = i + m[0].length;
      if (text[j] === "(") {
        const inner = balancedArgs(text, j);
        if (inner === null) return null;
        if (FUNCS.indexOf(name) === -1) {
          // :nth-child(2n+1) and friends: their own specificity is a pseudo-CLASS
          // and the argument contributes nothing on its own.
          b++;
        } else {
          let best = [0, 0, 0];
          for (const part of splitTop(inner)) {
            const sub = specOf(part);
            if (sub === null) return null;
            if (sub[0] > best[0] || (sub[0] === best[0] && sub[1] > best[1]) ||
                (sub[0] === best[0] && sub[1] === best[1] && sub[2] > best[2])) best = sub;
          }
          a += best[0]; b += best[1]; c += best[2];
        }
        j = inner.end + 1;
        i = j;
        continue;
      }
      b++; i += m[0].length; continue;
    }
    if (/[>+~*]/.test(ch) || ch === " ") { i++; continue; }
    if (/[A-Za-z]/.test(ch)) {                       // a bare type selector
      const m = /^[A-Za-z][\w-]*/.exec(text.slice(i));
      if (!m) return null;
      c++; i += m[0].length; continue;
    }
    return null;                                    // something unmodelled
  }
  return [a, b, c];
}
// The text between the parens at `open`, and the index of the closing one. Counts,
// because the argument contains nested parens of its own.
function balancedArgs(text, open) {
  let depth = 0;
  for (let j = open; j < text.length; j++) {
    if (text[j] === "(") depth++;
    else if (text[j] === ")") { depth--; if (depth === 0) return { text: text.slice(open + 1, j), end: j }; }
  }
  return null;
}
// Split on TOP-LEVEL commas only - a nested `,` is inside parens and belongs to an
// inner selector list. A naive `split(",")` is the same bug the CSS readers in the
// bash suites have, and it is why `:is(a, b)` looked like two selectors to them.
function splitTop(inner) {
  const parts = [];
  let depth = 0, cur = "";
  for (const ch of inner.text) {
    if (ch === "(") depth++;
    if (ch === ")") depth--;
    if (ch === "," && depth === 0) { parts.push(cur); cur = ""; continue; }
    cur += ch;
  }
  parts.push(cur);
  return parts.map((x) => x.trim()).filter(Boolean);
}
const fmt = (v) => v === null ? "?" : "(" + v.join(",") + ")";
const specSuppress = specOf(SUPPRESS_HOVER);
const specSuppressFocus = specOf(SUPPRESS_FOCUS);
const specShowHover = specOf(CHIP_SHOW_HOVER);
const specShowFocus = specOf(CHIP_SHOW_FOCUS);
// SPECIFICITY ORDER: ids, then classes/attributes/pseudo-classes, then elements.
const geq = (x, y) => x !== null && y !== null &&
  (x[0] > y[0] || (x[0] === y[0] && x[1] > y[1]) ||
   (x[0] === y[0] && x[1] === y[1] && x[2] >= y[2]));
const gt = (x, y) => x !== null && y !== null &&
  (x[0] > y[0] || (x[0] === y[0] && x[1] > y[1]) ||
   (x[0] === y[0] && x[1] === y[1] && x[2] > y[2]));
// The numbers are pinned, not just ordered. A calculator that returned 5 for the
// suppression and 4 for the arms because it was WRONG in a way that happened to
// preserve the ordering would sail through a bare `gt`.
//
// THE PINS CHANGED WITH THE SELECTORS, and that is worth stating plainly because
// "relaxed a threshold" and "the number moved because the thing being counted
// moved" look identical in a diff. Before Item 3 the suppression's `:not()` held
// a `:has()` argument, whose specificity is that of its most specific argument -
// `.sidebar-menu-button:hover`, two classes - so the compound came out at (0,6,1)
// against the show arms' (0,4,1). The open state's `:not()` now holds an
// ATTRIBUTE selector, `[data-hover-suppressed="true"]`, which is one class, so
// the same compound is (0,5,1). The margin over the show arms went from two
// classes to one; it did not go to zero, which is what keeps the chip's
// suppression decidable by specificity rather than by source order.
//
// A zero margin would not be a cosmetic difference to the pinned numbers. It would
// mean the suppression and the show arms tie, and the winner would be whichever
// happens to be written last - an order a reader cannot see and an edit can
// change silently. So `gt` is kept, not `geq`.
//
// The focus arm is a DIFFERENT number from the hover arm now, and asymmetrically
// so: `.sidebar[data-collapsed="true"]:focus-within` carries no `:not()` at all, so
// it lands at (0,4,1) - level with the focus-visible show arm rather than above
// it. That is correct and it is deliberate: with the row carve-out gone, "the
// column is open" and "a row is focus-visible" are no longer mutually exclusive,
// so there is no conflict left for the focus arm's specificity to resolve. The
// hover arm still needs its `:not()` and it is carrying one - for the hover LOCK,
// not for rows - which is why the two differ. Asserted separately below rather
// than folded into one expectation, because "both arms are the same number" was
// true before and is false now for a reason.
const specificOK = fmt(specSuppress) === "(0,5,1)" && fmt(specShowHover) === "(0,4,1)" &&
  fmt(specShowFocus) === "(0,4,1)" &&
  gt(specSuppress, specShowHover) && gt(specSuppress, specShowFocus) &&
  fmt(specSuppressFocus) === "(0,4,1)" && fmt(specSuppressFocus) === fmt(specShowFocus);
if (specificOK) {
  ok("the hover suppression's specificity " + fmt(specSuppress) + " beats both show arms " + fmt(specShowHover) + " by one class - the `:not()` now holds an attribute (the hover lock), not a `:has()` of two - so the chip still cannot win on source order alone; the focus arm ties at " + fmt(specSuppressFocus) + ", correctly, since with no row carve-out there is no conflict left for it to resolve");
} else {
  bad("the suppression outranks both show arms on specificity",
    "suppression " + fmt(specSuppress) + " / " + fmt(specSuppressFocus) + " vs hover " +
    fmt(specShowHover) + " / focus " + fmt(specShowFocus) +
    " - expected (0,5,1) and (0,4,1) against (0,4,1); if the hover suppression ties with the arms then source order decides, and nothing in the stylesheet says which way that goes");
}

// (8) TOUCH. `@media (hover: none)` gets an `:active` arm, following the two
// blocks already in this file (.code-copy-btn, .drive-item-menu-btn) which exist
// for exactly this class of problem: a `:hover` rule must not be the only way to
// see something. Read from INSIDE the query, because `withoutAtRuleBodies` blanks
// it and a whole-sheet search would happily match the `:active` anywhere.
//
// `:active` and not a permanent `opacity: 1`: ten chips at once on a 56px column
// would overlap each other, and iOS moves no focus on a tap so `:focus-visible` is
// unavailable there - which is why this arm exists and why its limitation is
// recorded in the CSS.
// Mutation: delete the arm -> red.
// Mutation: move it out of the query -> red.
const hoverNoneRanges = mediaRange(cssNoComments, "hover\\:\\s*none");
let hoverNoneSel = [];
for (const [a, b] of hoverNoneRanges) {
  const inner = cssNoComments.slice(a, b);
  for (const m of inner.matchAll(/([^{}]*)\{([^{}]*)\}/g)) {
    for (const one of m[1].split(",").map((x) => x.trim()).filter(Boolean)) hoverNoneSel.push(one);
  }
}
const CHIP_ACTIVE = '.sidebar[data-collapsed="true"] .sidebar-menu-button:active::after';
const activeArm = hoverNoneSel.filter((s) => s === CHIP_ACTIVE);
// The BODY is read from inside the query rather than through `selBodies`, which
// resolves `top` - and `top` blanks every at-rule body, so `selBodies` reports
// nothing for a rule that exists and renders. Asking `top` about a media-scoped
// rule is the same class of mistake as `Object.keys` on a Map: the lookup succeeds
// and the answer is meaningless.
let activeBody = "";
for (const [a, b] of hoverNoneRanges) {
  const inner = cssNoComments.slice(a, b);
  for (const m of inner.matchAll(/([^{}]*)\{([^{}]*)\}/g)) {
    if (m[1].split(",").map((x) => x.trim()).includes(CHIP_ACTIVE)) {
      activeBody = m[2].split(/\s+/).filter(Boolean).join(" ");
    }
  }
}
if (activeArm.length === 1 && /opacity: 1/.test(activeBody)) {
  ok("prefers-hoverless pointers get the chip on :active, so a press is not the only way to miss");
} else {
  bad("the hover: none arm exists for the chip",
    activeArm.length + " arm(s) inside the query; body: " + (activeBody || "<none>") +
    " - on an iPad at 640px and up the rail exists, :hover never fires, and iOS moves no focus on a tap");
}

// ---------------------------------------------------------------------------
// C2: the OPEN COLUMN SHOWS THE LABELS. Eight rules, two arms each, and the
//    reviewer's render of the shipped state was a 256px column of bare icons -
//    which nothing asserted, because every assertion in this file was about the
//    RAIL. The rail hid the labels correctly; the open state never put them back,
//    and "the rail hides .brand-name" is true in both states.
//
// So the question is asked of the OTHER half of the pair, for every label the
// collapsed rule hides, and for the four layout declarations the rail zeroes that
// the column needs back. One table, one loop, because five of these six
// mutations were green on the first attempt - nothing was checking them at all.
//
// TWO ENTRIES LEFT THIS TABLE AND THE REASONS DIFFER. `.status-indicator` is gone
// from the markup - the tier pill, the Full Mode countdown and the connection dot
// were all removed - so there is no status line to restore, and asserting one
// would assert a rule for an element that does not exist. `.sidebar-group-label`
// was here because the rail HID it, and Item 2 stops hiding it: it is now
// shortened rather than removed, so its restore is not a `display` but the
// `font-size` the collapsed rule zeroes plus a `content: none` that stops the
// short form being generated. That pair is asserted in its own section above,
// where the reasons are, rather than being folded in here - because the value it
// restores is not "the base rule's display" and putting it in this table would
// have needed a note explaining why it is not.
//
// Mutation: delete any restore rule -> red.
// Mutation: `display: inline` on the badge -> red (its base rule is inline-flex).
// Mutation: leave `justify-content: center` -> red.
// Mutation: leave `margin-left: 0` on the control -> red.
// Mutation: drop one arm of a pair -> red (the two arms are one rule).
const RESTORE = [
  // [ what the rail removed, the value the base rule gives it, a note ]
  [".sidebar-menu-button span", "display: inline;", "the row labels"],
  [".sidebar-menu-button span.badge", "display: inline-flex;", "the tier badges - .badge is inline-flex"],
  [".brand-mark", "display: flex;", "the avatar"],
  [".brand-name", "display: inline;", "the word Perla"],
];
let restoreBad = [];
for (const [desc, want, note] of RESTORE) {
  const bodies = selBodies(SLIDE_HOVER + " " + desc).concat(selBodies(SLIDE_FOCUS + " " + desc));
  if (bodies.length === 2 && bodies[0] === want && bodies[1] === want) continue;
  restoreBad.push(desc + " -> [" + bodies.join(" | ") + "] want " + want + " (" + note + ")");
}
// And the layout declarations, which are not `display` and so would be a
// second list with its own loop if anything else ever joins them.
//
// `width: auto` is in two of these four rows and is a fifth row of its own, and
// that is the restore half of the width pin that stops the slide relaying out the
// content (see "and the SLIDE cannot relayout the content" above). It is asserted
// HERE rather than only there because the pin's failure mode is one-sided: without
// it the rail is still a rail, every centring assertion above still passes, and
// the open column's three regions stay 55px wide inside a 256px panel with the
// labels nowhere to sit. Nothing else in this file reads that width.
const layoutRestores = [
  [".sidebar-menu-button", "padding-left: var(--space-3); padding-right: var(--space-3); justify-content: flex-start;"],
  [".sidebar-header", "padding-left: var(--space-4); padding-right: var(--space-4); width: auto;"],
  [".sidebar-footer", "padding-left: var(--space-4); padding-right: var(--space-4); width: auto;"],
  [".sidebar-collapse", "margin-left: auto;"],
  // Its own row because .sidebar-content has no padding to give back, so it had no
  // open rule to join the others in - and the two-arm count this loop enforces is
  // what will notice a second one being added for it later.
  [".sidebar-content", "width: auto;"],
];
for (const [desc, want] of layoutRestores) {
  const bodies = selBodies(SLIDE_HOVER + " " + desc).concat(selBodies(SLIDE_FOCUS + " " + desc));
  const wantParts = want.split(";").map((x) => x.trim()).filter(Boolean);
  const okBoth = bodies.length === 2 && bodies.every((b) => {
    const have = b.split(";").map((x) => x.trim()).filter(Boolean);
    return wantParts.every((w) => have.includes(w));
  });
  if (!okBoth) restoreBad.push(desc + " -> [" + bodies.join(" | ") + "] want " + want);
}
if (restoreBad.length === 0) {
  ok("the open column restores all " + RESTORE.length + " hidden elements and all " +
     layoutRestores.length + " zeroed layout declarations, on BOTH arms of the split");
} else {
  bad("the open column restores what the rail removed",
    restoreBad.join(" ;; ") +
    " - a 256px column with the labels still hidden is the state the review rendered, and a rule that restores one arm is half a fix");
}

// --- the hit area: is there enough rail that is NOT a row? ------------------
// The split made this a question rather than a comment. A hover target of a few
// pixels is a hover target nobody hits, so the numbers are computed from the
// sources instead of asserted in prose - the same technique as the two centring
// assertions below, and for the same reason: jsdom has no layout engine, so the
// CASCADE is the only thing measurable.
//
// Two figures, because "is it big enough" has two answers:
//
//   a. the BAND BESIDE EACH ICON. The row spans .sidebar-content's content box
//      and the icon is centred in it, so the clear rail on either side is
//      `contentPad + (rowWidth - iconW) / 2`. Note this is INVARIANT under
//      .sidebar-content's inline padding - zeroing the padding widens the row by
//      the padding on each side and moves the icon out by exactly half of that,
//      so the flank is the same number either way. Which is why the fix for a
//      thin flank is NOT "remove the padding".
//   b. the HEADER BAND, which is 100% non-row: .sidebar-header carries the
//      collapse control, which is not a .sidebar-menu-button, so the whole strip
//      opens the column. That is the intended primary target and it is measured
//      from `min-height`.
//
// Floors rather than exact values: 16px for a band, 40px for the header. Both are
// below what the geometry actually produces, so this is a floor that moves with
// the tokens instead of a constant that quietly stops describing the rail.
// Mutation: `--sidebar-rail-width` -> `20px` -> the flank goes negative -> red.
// Mutation: `.sidebar-header { min-height }` -> `0` -> red.
// Mutation: the row's `justify-content` back to flex-start -> the icon is off the
//            midpoint and one flank is 0 -> red.
// WHAT THIS MEASURES, named correctly this time. It is a CENTRING fact, not a
// hit-target fact, and the earlier version of this assertion got the category
// wrong: `.sidebar-menu-button` is `width: 100%` and the collapsed rule zeroes only
// its INLINE padding, so the row's border box is the whole 47px and the 18px on
// either side of the icon is INSIDE the row. Hovering it is a row hover, which
// routes to the chip and not to the slide-out - so calling it a "non-row band" and
// a "hittable target" was describing a region that cannot be hovered as described.
//
// The two centring assertions above are the claim; this one is the same claim's
// consequence stated as a number, and it is worth having because 18px is what a
// reader would otherwise have to re-derive to picture the rail.
//
// Its own claimed mutation was wrong too: the comment said removing
// `justify-content: center` turns this red, and it does NOT - the flank stays 18
// with the icon packed at the start (one side gets 18, the other 0, so the SUM is
// the same). The centring assertions catch it, and they are the ones that say so.
// `mutation: justify-content -> flex-start` below is removed rather than fixed,
// because the honest version of it is already asserted twice.
//
// Reuses `iconW`, `contentPad`, `rowInline`, `inner` and `ax` from the centring
// assertions above rather than re-deriving them: a second derivation of the same
// numbers is a second thing to be wrong, and the harness header's whole subject is
// that this file computes rather than hardcodes. `ax.ok` gates it for the same
// reason the two centring assertions gate on it.
// Every side through `padPx`, which is what resolves `var(--space-2)` to 4px. The
// centring assertions above had to be taught this the same way after a first draft
// concatenated number + string and reported a centre of `40149.5px` - a test that
// coerces types silently can pass for the wrong reason.
const flankPadL = padPx(contentPad.l), flankPadR = padPx(contentPad.r);
const flankInlineL = padPx(rowInline.l), flankInlineR = padPx(rowInline.r);
const flankNums = [flankPadL, flankPadR, flankInlineL, flankInlineR].every((n) => n !== null && !Number.isNaN(n));
const flankRowWidth = flankNums ? inner - flankPadL - flankPadR - flankInlineL - flankInlineR : NaN;
const flank = flankNums && flankRowWidth >= iconW ? flankPadL + (flankRowWidth - iconW) / 2 : NaN;
const headerPx = padPx((/min-height:\s*([^;}]+)/.exec(sidebarHeadBody) || [])[1]);
const flankOK = ax.ok && flankNums && !Number.isNaN(flank) && flank >= 16;
if (flankOK) {
  ok("the centred icon leaves " + flank + "px of clear row on each side of its " + iconW + "px (" + inner + "px inner, " + flankRowWidth + "px row) - inside the row, not beside it");
} else {
  bad("the centred icon's clearance inside the row",
    "flank=" + flank + " rowWidth=" + flankRowWidth + " icon=" + iconW + " inner=" + inner +
    " contentPad=" + JSON.stringify(contentPad) + " resolved=" + flankNums + " inputs-ok=" + ax.ok +
    " - the rail is narrower than its own rows");
}

// THE REAL NON-ROW AREA, which is what a reader actually wants to know when
// deciding whether the split is usable: how much of the rail is pointer-targetable
// without landing on a row. Three kinds, all summed, all read through the cascade:
//
//   the header band      min-height x inner          - .sidebar-header carries the
//                        collapse control, which is not a .sidebar-menu-button, so
//                        the WHOLE band is non-row
//   the container strips .sidebar-content's inline padding, full height - the only
//                        continuous run of non-row either side of the rows
//   the seams            the vertical gaps: between rows in a menu, between
//                        groups, and each group's margin-bottom
//
// Counts come from the MARKUP (rows per .sidebar-menu, number of groups), because a
// gap's length depends on how many things it separates. `float`/`parseFloat` are
// deliberate: every input is coerced here rather than summed as strings, which is
// the type bug ux-fix-1 hit and this file has now hit twice more.
//
// Floors, not exact values: 3000px², roughly 55% of what this computes, so a
// pathological collapse of any ONE term still goes red while a token change moves
// the number without invalidating it.
// Mutation: `.sidebar-header { min-height }` -> 0 -> red.
// Mutation: `.sidebar-group { margin-bottom }` -> 0 -> red.
// Mutation: `.sidebar-content { padding }` -> 0 -> red.
const nonRowWidths = (() => {
  const groups = queryAll(doc, ".sidebar-group");
  // BOTH row stacks, not just .sidebar-menu: the two tier rows live in
  // .sidebar-tier and the 2px seam between them is exactly as non-row as the ones
  // between the destinations. Reading only .sidebar-menu counted 8 of the 10 rows
  // and dropped that seam on the floor.
  const stacks = queryAll(doc, ".sidebar-menu").concat(queryAll(doc, ".sidebar-tier"));
  // THE GAPS AND THE MARGIN ARE READ FROM THEIR DECLARATIONS, not from their
  // tokens - which is the exact mistake ux-fix-1's correction round recorded
  // ("rail width read from the token, not the declaration") and which this
  // assertion had reintroduced on its first run: setting
  // `.sidebar-group { margin-bottom: 0 }` moved nothing in the sum, because
  // `pxToken("space-5")` still resolved to 10px from an untouched declaration
  // elsewhere in the sheet. A number read from a token measures the token.
  const gapPx = (body) => {
    const m = /gap:\s*([^;}]+)/.exec(body);
    return m ? padPx(m[1].trim()) : null;
  };
  const marginPx = (body) => {
    const m = /margin-bottom:\s*([^;}]+)/.exec(body);
    return m ? padPx(m[1].trim()) : null;
  };
  // `axisBodies` rather than `ax.got[...]`: AXIS_INPUTS is the list of inputs the
  // CENTRING model is handed, and these two are not - adding them would widen a
  // list whose own comment says what it is for.
  const menuRule = axisBodies(".sidebar-menu");
  const groupRule = axisBodies(".sidebar-group");
  const menuGap = gapPx(menuRule.body);
  const groupGap = gapPx(groupRule.body);
  const groupMargin = marginPx(groupRule.body);
  const gapNums = menuRule.n === 1 && groupRule.n === 1 &&
    [menuGap, groupGap, groupMargin].every((v) => v !== null && !Number.isNaN(v));
  let seams = 0;
  let rowsInStacks = 0;
  for (const m of stacks) {
    const n = m.children.length;
    rowsInStacks += n;
    seams += (n - 1) * (menuGap || 0);              // .sidebar-menu { gap: … }
  }
  seams += (groups.length - 1) * (groupGap || 0);   // .sidebar-group { gap: … }
  seams += groups.length * (groupMargin || 0);      // { margin-bottom: … }
  // All three are AREAS. `seams` is a sum of lengths and has to be multiplied by
  // the rail's inner width like the other two - adding 36 (a length in px) to two
  // areas in px² made the seams look 55x smaller than they are and put the total's
  // floor within reach of a single term being deleted.
  const seamsArea = seams * inner;
  const strips = (flankPadL + flankPadR) * inner;     // .sidebar-content padding
  const band = (headerPx !== null && !Number.isNaN(headerPx)) ? headerPx * inner : null;
  return { band: band, strips: strips, seams: seamsArea, seamLen: seams,
           rows: rowsInStacks, groups: groups.length, stacks: stacks.length,
           gaps: { menuGap: menuGap, groupGap: groupGap, groupMargin: groupMargin, ok: gapNums },
           total: band === null ? null : band + strips + seamsArea };
})();
// EACH TERM as well as the sum. A single floor on the total was not enough on its
// own: zeroing `.sidebar-content`'s padding removes 440px² and leaves 3116 - still
// over the floor, so that mutation stayed GREEN. Three separate floors say what the
// inventory actually claims, which is that all three kinds of non-row area exist.
// The floors are roughly half of what each term computes, for the same reason the
// total's is.
const nonRowOK = ax.ok && nonRowWidths.gaps.ok && nonRowWidths.total !== null && nonRowWidths.total >= 3000 &&
  nonRowWidths.band >= 1500 && nonRowWidths.strips >= 200 && nonRowWidths.seams >= 900 &&
  nonRowWidths.rows === 10 && nonRowWidths.groups === 2 && nonRowWidths.stacks === 3;
if (nonRowOK) {
  ok("the rail offers " + Math.round(nonRowWidths.total) + "px2 of non-row area across " +
     nonRowWidths.groups + " groups and " + nonRowWidths.rows + " rows (header band " +
     Math.round(nonRowWidths.band) + " + content strips " + Math.round(nonRowWidths.strips) +
     " + seams " + Math.round(nonRowWidths.seams) + ")");
} else {
  bad("the rail offers enough non-row area to be usable",
    "total=" + nonRowWidths.total + " (band=" + nonRowWidths.band + " strips=" +
    nonRowWidths.strips + " seams=" + nonRowWidths.seams + " rows=" + nonRowWidths.rows +
    " groups=" + nonRowWidths.groups + " inputs-ok=" + ax.ok + " gaps-resolved=" + nonRowWidths.gaps.ok +
    " (menuGap=" + nonRowWidths.gaps.menuGap + " groupGap=" + nonRowWidths.gaps.groupGap +
    " groupMargin=" + nonRowWidths.gaps.groupMargin + ")" +
    " - under 3000px2, or the markup no longer matches the ten rows and two groups the seams are counted for");
}
const headerOK = ax.ok && headerPx !== null && !Number.isNaN(headerPx) && headerPx >= 40;
if (headerOK) {
  ok(".sidebar-header is a " + headerPx + "px band of pure non-row rail - the primary target, and it holds the collapse control");
} else {
  bad(".sidebar-header is a usable non-row band",
    "min-height=" + headerPx + " inputs-ok=" + ax.ok +
    " - under 40px tall there is no comfortable place to hover that is not a row");
}
// ---------------------------------------------------------------------------
// 10. The ONE collapse control, in both states. The plan's alternative - a
//     second button at the content column's top-left with its own id - was
//     rejected: two buttons with two ids means two aria-expanded values and two
//     things to keep in step. Instead the rail IS the top-left of the content
//     area once it leaves the grid, so the same button is in the right place in
//     both states and nothing has to move.
// ---------------------------------------------------------------------------

const collapseBtn = query(doc, "#sidebarCollapse");
const collapseInSidebar = !!(collapseBtn && sidebar && contains(sidebar, collapseBtn));
if (collapseInSidebar) {
  ok("#sidebarCollapse lives in the sidebar - one control, and it is what the collapsed rail shows");
} else {
  bad("#sidebarCollapse lives in the sidebar", "a second control elsewhere would need a second id and a second aria-expanded");
}
const collapseAttrs = (collapseBtn && collapseBtn.attrs) || {};
if (collapseAttrs["aria-controls"] === "sidebar" && collapseAttrs["aria-expanded"] === "true" &&
    /btn-icon-24/.test(collapseAttrs["class"] || "") && /sidebar-collapse/.test(collapseAttrs["class"] || "")) {
  ok("#sidebarCollapse starts aria-expanded=true, points at the sidebar, and keeps its size and alignment classes");
} else {
  bad("#sidebarCollapse's starting attributes",
    "got: aria-controls=" + collapseAttrs["aria-controls"] +
    " aria-expanded=" + collapseAttrs["aria-expanded"] +
    " class=" + collapseAttrs["class"]);
}
// The collapsed rail's own centring is what puts it at the top-left of the
// content area rather than at the far edge of a 256px box: the header row drops
// its inline padding, centres, and the control gives up `margin-left: auto`.
// Asserted here rather than only in the arithmetic block because THIS is the
// question - is the control the first thing in the collapsed content column.
if (/padding-left: 0/.test(selBodies('.sidebar[data-collapsed="true"] .sidebar-header')[0] || "") &&
    /justify-content: center/.test(selBodies('.sidebar[data-collapsed="true"] .sidebar-header')[0] || "") &&
    /margin-left: 0/.test(selBodies('.sidebar[data-collapsed="true"] .sidebar-collapse')[0] || "")) {
  ok("the collapsed rail's control is centred in its 56px column - the top-left of the content area, not the far edge of a 256px box");
} else {
  bad("the collapsed rail's control is centred in its 56px column",
    "header: " + (selBodies('.sidebar[data-collapsed="true"] .sidebar-header')[0] || "<no rule>") +
    " control: " + (selBodies('.sidebar[data-collapsed="true"] .sidebar-collapse')[0] || "<no rule>"));
}

// The header must not swallow the rail. It is a full-width band at --z-header
// (20) and the rail is --z-raised (15) - deliberately, so toasts and the header
// stay above the slide-out - and a transparent element still takes pointer
// events, so without `pointer-events: none` the top 56px of the rail (which is
// exactly where the control is) would be dead to hover and to clicks.
// Mutation: delete `pointer-events: none` from .app-header -> red.
// Mutation: delete `pointer-events: auto` from .header-left -> red (the phone's
//            hamburger stops working).
const headerNoPe = /pointer-events: none/.test(headerBody);
const headerLeftPe = /pointer-events: auto/.test((bodies(".header-left")[0] || ""));
if (headerNoPe && headerLeftPe) {
  ok(".app-header is click-through and .header-left takes the pointer back for the phone's hamburger");
} else {
  bad(".app-header is click-through and .header-left takes the pointer back",
    "header pointer-events:none=" + headerNoPe + " header-left pointer-events:auto=" + headerLeftPe +
    " - the band would cover the rail's own header row, hover and clicks both");
}

// The rail's rung, resolved against the token VALUES rather than the spelling.
// It has to clear the content column, which declares no z-index at all, and stay
// under --z-toast and --z-header: a nav drawer over the toasts is the same bug in
// the other direction. --z-raised (15) is the only rung in that window.
// Mutation: --z-dropdown for --z-raised -> red.
// Mutation: swap --z-toast and --z-header -> red here as well as in the scales.
function tokenNums(name) {
  const m = new RegExp("--" + name + "\\s*:\\s*([0-9]+)").exec(cssNoComments);
  return m ? Number(m[1]) : NaN;
}
const railZ = (/z-index: var\(--z-([a-z-]+)\)/.exec(railBody) || [])[1];
const zr = tokenNums("z-raised"), zt = tokenNums("z-toast"), zh = tokenNums("z-header");
if (railZ === "raised" && zr > 0 && zr < zt && zr < zh) {
  ok("the rail takes --z-raised (" + zr + "): above the content column, below --z-toast (" + zt + ") and --z-header (" + zh + ")");
} else {
  bad("the rail takes --z-raised, under the toast and header rungs",
    "z-index=" + (railZ || "<none>") + " raised=" + zr + " toast=" + zt + " header=" + zh);
}

// ---------------------------------------------------------------------------
// 11. TWO SURFACES THAT CENTRED THEMSELVES AGAINST THE WRONG BOX
//
// THE REPORT: #qaDrawer and .toast-stack sit 128px to the LEFT of the card, and
// only while the sidebar is showing. Both are `position: fixed`, so their `left`
// is measured from the VIEWPORT, while `.app-card` centres in the CONTENT COLUMN
// - `width: 100%`, `max-width: 820px`, `margin-inline: auto`, inside a grid whose
// first track is `--sidebar-width`. On a 1920px screen that is 1088 against 960,
// and the gap is `--sidebar-width / 2`. Measured in Firefox by the reviewer and
// independently by the round that recorded it; nothing here re-measures it.
//
// IT IS EXPANDED-ONLY, and that is not a smaller bug, it is the shape of one.
// Collapsed, `.app[data-collapsed="true"]` makes the grid `1fr`; below 640px the
// media query does the same. The column then IS the window, the two centres
// coincide, and the drift is zero - so the surfaces are RIGHT exactly when there
// is no sidebar and WRONG exactly when there is. Reading the rule text does not
// show that at all, which is why the arithmetic below runs at three widths in
// each of the three states rather than asserting a formula.
//
// THE FIX IS ONE PROPERTY, published by the grid and read by both surfaces:
// `--content-column-inset`. Two rules each working the offset out for themselves
// is how they came to disagree with each other and with the card in the first
// place, so the number now exists once and each surface contributes only the
// geometry its own box needs - a band for the sheet, a midpoint for the stack.
//
// WHAT IS DELIBERATELY NOT ASSERTED: that either surface is `position: fixed`,
// which it must be (an `absolute` sheet inside `.app-content` would stop tracking
// `keyboardResize`'s inline height on a phone, and the toast stack's parent
// declares no position, so `absolute` would resolve against the initial
// containing block and change nothing), and that the card is static (asserted in
// the card section above). Neither is what this bug was.
//
// WHAT IS ASSERTED ABOUT THE OTHER AXIS, because a centring fix that quietly
// moves something else is the usual outcome: the sheet keeps `bottom: 0` and no
// `top`, so it stays flush to the viewport's bottom edge rather than being lifted
// to meet the card - which does not reach the viewport bottom at all; the stack
// keeps `top` clearing the header band; and `--z-toast` still resolves below
// `--z-header`.
// ---------------------------------------------------------------------------

// The property, by name, once - the single source of truth both surfaces read.
const QA_INSET = "--content-column-inset";

// The three centres at one window width, in ONE function. Three copies of this
// walk the ancestor chain and take the first element whose resolved value is not
// null. A custom property inherits through the DOM regardless of layout and
// regardless of any `position`, which is the whole mechanism: `position: fixed`
// is not re-anchored by a positioned ancestor (only transform/perspective/filter/
// backdrop-filter/will-change/contain:paint do), and a stale comment in this file
// used to claim the opposite, so pinning `.app` was rejected on a false reason.
// `.app-card`'s staticness is asserted above and asserted on its own merits.
//
// Returning null rather than a default is deliberate: `:root` carries a
// `--content-column-inset` fallback and this walker SKIPS `:root` (the resolver
// does not model a pseudo-class), so a surface that is not inside `.app` reports
// null and goes red below - which is the DOM move ux-fix-2 declined to make,
// turned into an assertion rather than a note in a report.
function resolveInherited(el, prop, src) {
  for (let node = el; node; node = node.parent) {
    const found = resolveProperty(node, prop, src);
    if (found) return found.value;
  }
  return null;
}

// A written length -> a number, for the three declarations this section compares.
// `calcLen` already does this for the RAIL and is not reused, for a reason worth
// stating rather than hiding: it resolves nothing, so it cannot evaluate `100%`,
// and `100%` is the whole of the question here - it is how a `fixed` box's `left`
// reaches the viewport, and how `.app-card`'s `width: 100%` reaches the column.
//
// Substitution order is load-bearing. `var()` goes FIRST, because a token name
// contains `--` and any later pass that split on an operator would come apart
// inside it; `calcLen`'s comment records the exact bug that causes, and it bit
// this file once. Then `px`, then `%`.
//
// ctx is { pctBase, px }: `pctBase` is what a bare percentage is a percentage OF,
// which is NOT always the window - `left` on a `fixed` box is a percentage of the
// viewport and the card's `width` is a percentage of the column. Everything
// unrecognised returns null, and null makes the assertions below RED rather than
// wrong; so does a leftover operator or an unbalanced paren, which is a parse
// failure and not a result.
// Mutation: make this return 0 for everything -> red on the arithmetic, because
//            the card's side and the surfaces' sides travel by different paths.
function evalLen(expr, ctx) {
  if (expr === null || expr === undefined) return null;
  let s = String(expr).trim();
  s = s.replace(/var\(\s*(--[\w-]+)\s*\)/g, (m, n) => {
    const v = ctx.px(n);
    return Number.isFinite(v) ? String(v) : "@";
  });
  if (s.indexOf("@") !== -1) return null;
  s = s.replace(/(-?[\d.]+)px\b/g, (m) => String(parseFloat(m)));
  s = s.replace(/(-?[\d.]+)%/g, (m) => String(parseFloat(m) / 100 * ctx.pctBase));
  // `calc(` becomes a PARENTHESIS rather than nothing, so the parens stay
  // balanced. Unconditionally stripping the closing paren instead - which
  // `calcLen` documents as the hazard it guards - would break `calc((a + b) / 2)`.
  s = s.replace(/^calc\(/i, "(");
  const toks = s.match(/[()]|[^\s()]+/g) || [];
  let i = 0;
  const exprP = () => {
    let v = termP();
    while (toks[i] === "+" || toks[i] === "-") {
      const op = toks[i++];
      const r = termP();
      if (v === null || r === null) return null;
      v = op === "+" ? v + r : v - r;
    }
    return v;
  };
  const termP = () => {
    let v = factorP();
    while (toks[i] === "*" || toks[i] === "/") {
      const op = toks[i++];
      const r = factorP();
      if (v === null || r === null) return null;
      v = op === "*" ? v * r : v / r;
    }
    return v;
  };
  const factorP = () => {
    const t = toks[i];
    if (t === undefined) return null;
    i++;
    if (t === "(") {
      const v = exprP();
      if (toks[i] === ")") i++;
      return v;
    }
    if (t === "-") {
      const v = factorP();
      return v === null ? null : -v;
    }
    const n = parseFloat(t);
    return Number.isNaN(n) ? null : n;
  };
  const out = exprP();
  return (out === null || i !== toks.length || !Number.isFinite(out)) ? null : out;
}

// What the cascade hands THIS element for a property, following INHERITANCE -
// walk the ancestor chain and take the first element whose resolved value is not
// null. A custom property inherits through the DOM regardless of layout and
// regardless of any `position`, which is the whole mechanism: `position: fixed`
// is NOT re-anchored by a positioned ancestor - only transform, perspective,
// filter, backdrop-filter, will-change of those, or `contain: paint` do - so a
// positioned `.app` would not have brought the toast stack with it, and a comment
// in this file used to say it would. That comment has been corrected.
//
// Returning null rather than a default is deliberate: `:root` carries a
// `--content-column-inset` fallback and this walker SKIPS `:root` (the resolver
// does not model a pseudo-class), so a surface that is not inside `.app` reports
// null and goes red below - which is the DOM move ux-fix-2 declined to make,
// turned into an assertion rather than a note in a report.
function resolveInherited(el, prop, src) {
  for (let node = el; node; node = node.parent) {
    const found = resolveProperty(node, prop, src);
    if (found) return found.value;
  }
  return null;
}

const qaDrawerEl = query(doc, "#qaDrawer");
const toastStackEl = query(doc, ".toast-stack");
const drawerLeft = qaDrawerEl ? resolveProperty(qaDrawerEl, "left", topSrc) : null;
const drawerRight = qaDrawerEl ? resolveProperty(qaDrawerEl, "right", topSrc) : null;
const drawerTop = qaDrawerEl ? resolveProperty(qaDrawerEl, "top", topSrc) : null;
const drawerBottom = qaDrawerEl ? resolveProperty(qaDrawerEl, "bottom", topSrc) : null;
const drawerMargin = qaDrawerEl ? resolveProperty(qaDrawerEl, "margin", topSrc) : null;
const drawerMaxW = qaDrawerEl ? resolveProperty(qaDrawerEl, "max-width", topSrc) : null;
const drawerTx = qaDrawerEl ? resolveProperty(qaDrawerEl, "transform", topSrc) : null;
const toastLeft = toastStackEl ? resolveProperty(toastStackEl, "left", topSrc) : null;
const toastTop = toastStackEl ? resolveProperty(toastStackEl, "top", topSrc) : null;
const toastTx = toastStackEl ? resolveProperty(toastStackEl, "transform", topSrc) : null;
// What each surface ACTUALLY receives, which is a different question from what
// the rule says: both have to be inside `.app` for a custom property to reach
// them, and `#globalNotifications` is a direct child of `#app` while `#qaDrawer`
// is four levels down inside the card.
const drawerInset = qaDrawerEl ? resolveInherited(qaDrawerEl, QA_INSET, topSrc) : null;
const toastInset = toastStackEl ? resolveInherited(toastStackEl, QA_INSET, topSrc) : null;

// (1) THE PUBLICATION. One declaration, on the rule that creates the geometry,
// and equal to that rule's own first track - so the number cannot drift from the
// grid it describes without one of the two assertions below going red.
// Mutation: `var(--sidebar-rail-width)` -> red.
// Mutation: `0px` -> red.
// Mutation: a SECOND declaration -> red on the count.
const insetDecls = declsOf(appBody, QA_INSET);
const insetPx = evalLen(insetDecls[0] || "", { pctBase: 0, px: (n) => pxToken(n.slice(2)) });
const sidebarPx = pxToken("sidebar-width");
const railCols = declOf(appBody, "grid-template-columns");
if (insetDecls.length === 1 && insetPx !== null && sidebarPx !== null &&
    insetPx === sidebarPx && String(railCols || "").trim() === "var(--sidebar-width) 1fr") {
  ok(".app publishes the content column's left edge once, as " + QA_INSET + ", and it is the grid's own first track (" + insetPx + "px)");
} else {
  bad(".app publishes the content column's left edge as " + QA_INSET + ", equal to the grid's first track",
    insetDecls.length + " declaration(s): " + JSON.stringify(insetDecls) +
    " -> " + insetPx + "px, against --sidebar-width " + sidebarPx + "px and grid-template-columns: " + (railCols || "<none>") +
    " - both fixed surfaces read this, so any other value re-opens the gap between them and the card");
}

// (2) THE SHEET'S BOX. Its `left` is the published property and its `right` is 0,
// which together are the content column - and then the `margin: 0 auto` and
// `max-width` it already had do the centring, unchanged. `drawerInset !== null`
// is the half that makes it more than a spelling: the value has to REACH this
// element through the ancestor chain, which is what the DOM move of the toast
// stack discussed in ux-fix-2 would have broken.
//
// `centres` below ASSUMES these four declarations rather than reading them, and
// this is where the assumption is checked - it models the sheet's box from
// `left`/`right`/`max-width` and never from `margin`, so a dropped auto margin
// would move the sheet without the arithmetic in (4) noticing.
// The `transform` check is not tidiness. A `translateX` here would move the sheet
// back off the card while `left` still read correctly, and (4) would not see it.
//
// Mutation: `left: 0` -> red, and red on (4) as well.
// Mutation: `left: var(--sidebar-width)` -> red on THIS ONE ALONE, and that is
//            the whole reason it is asserted here rather than only through the
//            arithmetic: the value is identical - 256px - so (4) stays GREEN and
//            would keep staying green for as long as the sidebar is 256px wide.
// Mutation: `margin: 0 auto` -> `margin: 0` -> red on THIS ONE ALONE, for the
//            same reason and for the assumption named above.
// Mutation: `max-width: 900px` -> red on this one alone (the sheet is no longer
//            the card's width, and the band still centres it).
// Mutation: add `transform: translateX(-50%)` -> red on this one alone.
// Mutation: the `class="app"` taken off `#app` -> red here AND on (3) at once,
//            since neither surface then inherits anything. There is no mutation
//            that moves ONLY the sheet out of `.app` - the DOM move worth
//            watching is the toast stack's, and m-next below is that one.
const drawerRecipe = drawerLeft && drawerRight && drawerMargin && drawerMaxW &&
  /var\(--content-column-inset\)/.test(drawerLeft.value) &&
  evalLen(drawerRight.value, { pctBase: 0, px: (n) => pxToken(n.slice(2)) }) === 0 &&
  /^0(\.0+)?\s+auto$/.test(drawerMargin.value) &&
  drawerMaxW.value === cardMax.value &&
  drawerTx === null && drawerInset !== null;
if (drawerRecipe) {
  ok("#qaDrawer is bounded by the CONTENT COLUMN (" + drawerLeft.value + " .. " + drawerRight.value + ", auto margins, the card's own " + drawerMaxW.value + " cap) and nothing translates it");
} else {
  bad("#qaDrawer is bounded by the content column and nothing translates it",
    "left=" + (drawerLeft ? drawerLeft.value : "<none>") +
    " right=" + (drawerRight ? drawerRight.value : "<none>") +
    " margin=" + (drawerMargin ? drawerMargin.value : "<none>") +
    " max-width=" + (drawerMaxW ? drawerMaxW.value : "<none>") +
    " transform=" + (drawerTx ? drawerTx.value : "<none>") +
    " inherited " + QA_INSET + "=" + JSON.stringify(drawerInset) +
    " - a `fixed` box measured from the viewport is 128px left of the card, and a translate on top of a correct `left` would undo the correction invisibly");
}

// (3) THE STACK'S BOX, and its OTHER AXIS in the same assertion because the two
// halves are the same decision: this rule was edited, and the two things that
// must NOT move are its distance below the header band and the `translateX(-50%)`
// that centres the stack's own width on whatever `left` resolves to - which is
// what makes the arithmetic in (4) valid at all.
// `toastInset !== null` is the DOM claim: `#globalNotifications` is a direct
// child of `#app`, which is what puts the published property in reach.
// Mutation: `left: 50%` -> red on this and on (4): the shipped bug.
// Mutation: `left: calc(50% + 128px)` -> red on THIS ONE ALONE, and (4) stays
//            GREEN. That is not a gap in the arithmetic, it is arithmetic: the
//            sidebar is 256px on every screen, so a hardcoded half of it is
//            exactly right at every width and the centre equality cannot tell it
//            from the property. Only a check on the SOURCE can, which is why this
//            assertion reads the declaration and not the resulting number.
// Mutation: delete `transform: translateX(-50%)` (or set it to `none`) -> red on
//            this one alone. (4) reads `left` as the stack's centre BECAUSE of
//            that translate, so the arithmetic depends on it being there.
// Mutation: `top` pointed at 0 -> red on this one alone.
// Mutation: `#globalNotifications` moved out of `#app` - the DOM move ux-fix-2
//            declined to make, carried out here -> red on THIS ONE ALONE, on the
//            `toastInset` half.
const toastRecipe = toastLeft && toastTop && toastTx &&
  /var\(--content-column-inset\)/.test(toastLeft.value) &&
  /var\(--header-height\)/.test(toastTop.value) &&
  toastTx.value === "translateX(-50%)" && toastInset !== null;
if (toastRecipe) {
  ok(".toast-stack reads the published property for its left edge (" + toastLeft.value + "), still sits below the header band, and still centres its own width on it");
} else {
  bad(".toast-stack reads the published property, still clears the header, and still self-centres",
    "left=" + (toastLeft ? toastLeft.value : "<none>") +
    " top=" + (toastTop ? toastTop.value : "<none>") +
    " transform=" + (toastTx ? toastTx.value : "<none>") +
    " inherited " + QA_INSET + "=" + JSON.stringify(toastInset) +
    " - a `50%` on a `fixed` box is the viewport's midpoint, which is the shipped 128px drift");
}

// The three centres at one window width, in ONE function. Three copies of this
// formula is how a set of surfaces meant to agree comes to disagree.
//
// Every input is read out of the resolved cascade; nothing here is a number typed
// into this file. The card's side and the surfaces' sides travel by DIFFERENT
// paths on purpose - the card from the grid's track plus its own `width` and
// `max-width`, the surfaces from their `left` and `right` - so a broken
// evaluator shows up as a disagreement rather than as a shared wrong number.
//
// `cols` is the grid's own track list FOR THE STATE, so the collapsed and 640px
// grids are read from their own rules. A leading `fr` track means "whatever is
// left", i.e. nothing is reserved to the left of the column, which is precisely
// what `grid-template-columns: 1fr` says and why the correction must be a no-op
// in both of those states.
//
// TWO DECLARATIONS ARE ASSUMED RATHER THAN READ, and assertion (2) is where both
// are checked: that the sheet's `margin` is `auto` in both axes (this model puts
// it in the middle of its band because of them), and that the stack's `left` is
// its CENTRE (because of the `translateX(-50%)` assertion (3) requires). A model
// that quietly assumed something nothing checked is the shape of vacuous
// assertion this file has been caught at six times.
const centres = (w, cols, inset) => {
  if (!cardWidth || !cardMax || !drawerLeft || !drawerRight || !drawerMaxW || !toastLeft) return null;
  const pxFor = (n) => (n === QA_INSET ? inset : pxToken(n.slice(2)));
  const ctx = { pctBase: w, px: pxFor };
  const first = String(cols === null ? "" : cols).trim().split(/\s+/)[0];
  if (!first) return null;
  const colLeft = /fr$/.test(first) ? 0 : evalLen(first, ctx);
  if (colLeft === null) return null;
  const colW = w - colLeft;
  const cw = Math.min(
    evalLen(cardWidth.value, { pctBase: colW, px: pxFor }),
    evalLen(cardMax.value, { pctBase: colW, px: pxFor })
  );
  const dl = evalLen(drawerLeft.value, ctx);
  const dr = evalLen(drawerRight.value, ctx);
  const dw = evalLen(drawerMaxW.value, ctx);
  const tl = evalLen(toastLeft.value, ctx);
  if (cw === null || dl === null || dr === null || dw === null || tl === null) return null;
  const band = w - dl - dr;
  const sheet = Math.min(band, dw);
  // A CENTRE, so: where the box's left edge lands, plus half of the box. The
  // draft this replaces returned `colLeft + (colW - cw) / 2` - which is the card's
  // LEFT EDGE, not its middle - and reported 678 against a card centred at 1088.
  // It went red rather than quietly agreeing, because the toast's centre comes
  // from a different term (`left` itself, because of the -50% translate) and the
  // two disagreed by exactly the half-width.
  return {
    card: colLeft + (colW - cw) / 2 + cw / 2,
    drawer: dl + (band - sheet) / 2 + sheet / 2,
    toast: tl
  };
};
const spread = (r) => (r === null ? null : Math.max(r.card, r.drawer, r.toast) - Math.min(r.card, r.drawer, r.toast));
// The published value as the two surfaces actually receive it, so the top-level
// arithmetic uses the inherited number rather than the declaration re-read.
const insetLive = evalLen(String(drawerInset === null ? "" : drawerInset), { pctBase: 0, px: (n) => pxToken(n.slice(2)) });
const fmtRow = (rows) => rows.map((r) => r.g === null
  ? "w=" + r.w + " unresolved"
  : "w=" + r.w + " card=" + r.g.card + " sheet=" + r.g.drawer + " toast=" + r.g.toast).join("; ");

// (4) EXPANDED: all three centres agree, and they sit a half-sidebar to the RIGHT
// of the window's midpoint - the exact inverse of the reported 128px, which is
// the half that would survive an assertion that only asked "are they all equal".
// The inset is INHERITANCE-accurate here: a surface outside `.app` yields null
// and the row reads unresolved rather than silently using 0.
// Mutation: `left: 0` on the sheet -> red here and on (2).
// Mutation: `left: 50%` on the stack -> red here and on (3).
// Mutation: `right: 40px` on the sheet -> red here, on (2) and on all three
//            arithmetic rows. A band's right edge is half of what decides where
//            the sheet in the middle of it lands, so this is not a margin-only
//            change.
// NEGATIVE CONTROL, and the load-bearing one: `--sidebar-width: 256px` -> 300px
// leaves every suite GREEN, and that is the claim. Widening the sidebar moves
// the card, the sheet and the stack together, so the drift is still half of
// whatever the sidebar now is. The assertion would only go red if ONE of the
// three stopped following - which is what makes it evidence about the fix rather
// than about the current sidebar width. (This comment used to say that mutation
// went red. It does not, and it was written before the mutation was run.)
const WIDE = [1920, 1440, 1024, 900];
const wideRows = WIDE.map((w) => ({ w: w, g: centres(w, railCols, insetLive) }));
const wideSpread = Math.max.apply(null, wideRows.map((r) => {
  const s = spread(r.g);
  return s === null ? Infinity : s;
}));
const wideDrift = wideRows[0].g === null ? null : wideRows[0].g.card - wideRows[0].w / 2;
if (wideSpread <= 0.01 && wideDrift !== null && sidebarPx !== null &&
    Math.abs(wideDrift - sidebarPx / 2) <= 0.01) {
  ok("expanded, the card, the sheet and the toast stack share ONE centre at " + WIDE.length +
    " widths, " + wideDrift + "px right of the window's midpoint (half of --sidebar-width, was " +
    (-wideDrift).toFixed(0) + "px left)");
} else {
  bad("expanded, the card, the sheet and the toast stack share one centre",
    fmtRow(wideRows) + " - spread=" + wideSpread + " drift=" + wideDrift +
    " (want " + (sidebarPx === null ? "?" : sidebarPx / 2) + ") - a `fixed` box is measured from the viewport, so both surfaces need the column's own left edge");
}

// The two states with NO sidebar, and what each of them publishes. `insetOf`
// READS the state rather than resolving it, because `.app[data-collapsed="true"]`
// is an attribute selector and `resolveProperty` skips those on purpose - the
// cascade for the collapsed state is out of scope for the resolver by design, so
// the state is read and the arithmetic is what judges it.
// A state that stops declaring the property falls back to `.app`'s value here, so
// the failure message shows the real drift (128px) rather than "unresolved".
const insetOf = (body) => {
  const v = declOf(body, QA_INSET);
  if (v === null) return { declared: false, px: insetLive };
  const n = evalLen(v, { pctBase: 0, px: (k) => pxToken(k.slice(2)) });
  return { declared: n !== null, px: n === null ? insetLive : n };
};
// (5) COLLAPSED: one `1fr` column, so the column IS the window, the drift is
// zero, and the published inset has to be zero or the correction this file
// exists to make becomes a 128px shift in the one state where the bug is
// invisible. Both halves are in this assertion on purpose - a correct-looking
// `0px` that the grid contradicts, and a grid that is right while the property
// still carries 256px, are both wrong and only this can see either.
// Mutation: the `0px` -> `var(--sidebar-width)` -> red.
// Mutation: delete the declaration -> red (it inherits 256px).
// Mutation: the collapsed grid's `1fr` -> `var(--sidebar-width) 1fr` -> red.
const iCollapsed = insetOf(collapsedGridBody);
const collRows = WIDE.map((w) => ({ w: w, g: centres(w, collapsedCols, iCollapsed.px) }));
const collBad = collRows.filter((r) => r.g === null || Math.abs(r.g.card - r.w / 2) > 0.01 ||
  Math.abs(r.g.drawer - r.w / 2) > 0.01 || Math.abs(r.g.toast - r.w / 2) > 0.01);
if (iCollapsed.declared && iCollapsed.px === 0 && collBad.length === 0) {
  ok("collapsed, the published inset is 0 and all three centres fall on the window's midpoint at " + WIDE.length + " widths - the correction is a no-op, not a 128px shift");
} else {
  bad("collapsed, the published inset is 0 and all three centres coincide with the window's",
    "declares " + JSON.stringify(declOf(collapsedGridBody, QA_INSET)) + " -> " + iCollapsed.px +
    "px; grid-template-columns: " + (collapsedCols || "<none>") + "; " + fmtRow(collRows) +
    " - with one 1fr column the column IS the window, so a non-zero inset would move two surfaces the fix exists to leave alone");
}

// (6) BELOW 640px: the same no-op, on a phone, where `#app` is `position: fixed;
// inset: 0` and the grid is `1fr` as well. Asserted rather than assumed, because
// it is the state where a correction that is wrong everywhere else would be
// wrong on the smallest screen - and the arithmetic runs at phone widths so the
// claim is about a 420px viewport and not about a desktop rule applied to one.
// Mutation: the 640px rule's `0px` -> `var(--sidebar-width)` -> red.
// Mutation: delete it -> red (it inherits).
const iPhone = insetOf(gridInNarrow);
const PHONE = [420, 560, 640];
const phoneRows = PHONE.map((w) => ({ w: w, g: centres(w, declOf(gridInNarrow, "grid-template-columns"), iPhone.px) }));
const phoneBad = phoneRows.filter((r) => r.g === null || Math.abs(r.g.card - r.w / 2) > 0.01 ||
  Math.abs(r.g.drawer - r.w / 2) > 0.01 || Math.abs(r.g.toast - r.w / 2) > 0.01);
if (iPhone.declared && iPhone.px === 0 && phoneBad.length === 0) {
  ok("below 640px the published inset is 0 as well and all three centres coincide with the window's at " + PHONE.length + " phone widths");
} else {
  bad("below 640px the published inset is 0 and all three centres coincide with the window's",
    "declares " + JSON.stringify(declOf(gridInNarrow, QA_INSET)) + " -> " + iPhone.px +
    "px; grid-template-columns: " + (declOf(gridInNarrow, "grid-template-columns") || "<none>") + "; " + fmtRow(phoneRows) +
    " - on a phone the content column IS the viewport, so the correction must do nothing");
}

// (7) THE SHEET'S OTHER AXIS, which the fix must not have touched. `bottom: 0`
// with no `top` is what "flush to the viewport" means, and it is deliberately
// NOT the card's bottom: the card stops short of the window's bottom at the
// composer's own inset, so lifting the sheet to meet it would open a strip of
// --background under a sheet that is supposed to reach the screen edge.
// `drawerTop === null` is the half that is easy to break by accident: one `top`
// and the sheet stretches from the header band down instead of sitting at 46px.
// Mutation: `bottom: var(--header-height)` -> red.
// Mutation: add `top: 0` -> red.
// Mutation: delete `bottom` -> red.
if (drawerBottom && evalLen(drawerBottom.value, { pctBase: 0, px: (n) => pxToken(n.slice(2)) }) === 0 &&
    drawerTop === null) {
  ok("#qaDrawer stays flush to the viewport's bottom (" + drawerBottom.value + ", no `top`), so it is not lifted to the card's bottom - which does not reach the screen edge");
} else {
  bad("#qaDrawer stays flush to the viewport's bottom",
    "bottom=" + (drawerBottom ? drawerBottom.value : "<none>") + " top=" + (drawerTop ? drawerTop.value : "<none>") +
    " - the card stops short of the window's bottom, so a sheet that met it would show --background under itself");
}

// (8) THE FLUSH EDGE IS AN EDGE. No `border-bottom`, because a one-pixel border on
// the edge that meets the screen is a one-pixel line of --background under the
// sheet - the same defect as rounding the two corners there, which is why the
// radius keeps its `0 0` tail. The side borders ARE declared, so on a phone - the
// one width where the sheet's vertical edges really do sit on the screen's - the
// sheet still reads as a sheet rather than as a band of colour.
// test_scales.sh section 7 already pins the `border-radius` VALUE, so it is not
// re-asserted here; this is about the borders, which nothing else asks about.
// Mutation: add `border-bottom` -> red.
// Mutation: delete `border-left` -> red.
const drawerBBottom = qaDrawerEl ? resolveProperty(qaDrawerEl, "border-bottom", topSrc) : null;
const drawerBLeft = qaDrawerEl ? resolveProperty(qaDrawerEl, "border-left", topSrc) : null;
const drawerBRight = qaDrawerEl ? resolveProperty(qaDrawerEl, "border-right", topSrc) : null;
if (drawerBBottom === null && drawerBLeft && drawerBRight) {
  ok("the sheet's flush edge carries no border and its two vertical edges do, so it still reads as a sheet on a phone");
} else {
  bad("the sheet's flush edge carries no border and its vertical edges do",
    "border-bottom=" + (drawerBBottom ? drawerBBottom.value : "<none>") +
    " border-left=" + (drawerBLeft ? drawerBLeft.value : "<none>") +
    " border-right=" + (drawerBRight ? drawerBRight.value : "<none>") +
    " - a border on the edge that meets the screen is a line of --background under the sheet");
}

// (9) THE Z ORDER, resolved on the two ELEMENTS rather than on the two tokens.
// test_scales.sh section 2 already reads `--z-toast` and `--z-header` out of
// `:root` and compares the numbers, and that stays true whatever happens here -
// which is exactly its limit: it cannot see a `z-index` written on the stack or
// on the header. Both must still RESOLVE to the two tokens, and the tokens must
// still order as the toasts-under-the-header behaviour requires.
// Mutation: `.toast-stack { z-index: var(--z-header) }` -> red, and green in
//            test_scales.sh - which is the point.
// Mutation: `.toast-stack { z-index: 21 }` -> red (a literal, not a rung).
// Mutation: swap the two token VALUES -> red here and in the scales.
const toastZ = toastStackEl ? resolveProperty(toastStackEl, "z-index", topSrc) : null;
const headerZ = header ? resolveProperty(header, "z-index", topSrc) : null;
const zTok = (r) => (/var\((--[\w-]+)\)/.exec(String(r && r.value)) || [])[1];
const tzName = zTok(toastZ), hzName = zTok(headerZ);
const tzRung = tzName === "--z-toast" ? tokenNums("z-toast") : NaN;
const hzRung = hzName === "--z-header" ? tokenNums("z-header") : NaN;
if (tzName === "--z-toast" && hzName === "--z-header" &&
    Number.isFinite(tzRung) && Number.isFinite(hzRung) && tzRung < hzRung) {
  ok(".toast-stack and .app-header still resolve to --z-toast (" + tzRung + ") and --z-header (" + hzRung + "), so a toast passes under the fixed header - centring it on the column changed neither");
} else {
  bad(".toast-stack and .app-header still resolve to --z-toast below --z-header",
    "stack=" + (toastZ ? toastZ.value : "<none>") + " (" + tzName + "=" + tzRung + ")" +
    " header=" + (headerZ ? headerZ.value : "<none>") + " (" + hzName + "=" + hzRung + ")" +
    " - the scales check the two tokens and cannot see a z-index written on either element");
}

// (10) WHY THE SHEET IS ONLY HALF-FIXED, asserted rather than left as a note.
// This is a green assertion about a KNOWN defect, which is a shape that is usually
// a mistake, so the reasoning is the point: the defect cannot be seen by any
// arithmetic here, because it exists only while an animation is running, and what
// pins it is a STATIC fact - that `.dropdown-panel` animates a `transform`.
//
// `transform` on an ancestor is the ONE thing in the trap list that does re-anchor
// a `position: fixed` box, and #quickActionsPanel is both that ancestor and an
// element `.dropdown-panel`. So for the 200ms of `panel-drop` the sheet's
// containing block is the panel (measured centre 1216 with the inset applied) and
// for the rest of its life it is the viewport (measured 1088). `left: 0` was
// therefore correct for 200ms and wrong forever, which is why the bug read as
// inconsistent rather than simply wrong.
//
// BOTH HALVES, because "the containing block flips" is a claim about it being
// SOMETIMES the panel, and that takes two things to be true: the animation must
// carry a creating property, and the panel must not carry one permanently. The
// second half is not a nicety - `will-change: transform` on #quickActionsPanel was
// measured, and it pins the containing block for good: the transient disappears
// and this comment becomes a lie. With only the first half the assertion was GREEN
// under that mutation, which is the same gap as the resolver's combinator blind
// spot one level up, and this file has been caught by that twice.
//
// If someone drops the `transform` from `panel-drop`, this goes red and the
// message says to re-measure: the transient is gone, and the one-word
// `position: absolute` fix recorded at the rule becomes unnecessary.
//
// Mutation: `panel-drop` loses its `transform` (opacity only) -> red HERE, and
//            green everywhere else, which is exactly why the assertion exists.
// Mutation: `will-change: transform` on #quickActionsPanel -> red HERE.
const panelDrop = (() => {
  // `mediaRange` builds a `@media (...)` prelude, which is not this construct, and
  // the keyframes body is read with a brace counter rather than by pattern for the
  // reason every other read in this file is - a `[^{}]*` match stops at the first
  // nested `{`, and `panel-drop`'s body is nothing BUT nested blocks.
  const open = /@keyframes\s+panel-drop\s*\{/.exec(cssNoComments);
  if (!open) return "";
  let depth = 1, i = open.index + open[0].length;
  while (i < cssNoComments.length && depth > 0) {
    if (cssNoComments[i] === "{") depth++;
    else if (cssNoComments[i] === "}") depth--;
    i++;
  }
  return cssNoComments.slice(open.index, i);
})();
// The six properties that create a containing block for a `fixed` descendant, and
// the three individual transform properties, which animate like `transform` and
// create the same block. A keyframe that spells `translate` counts: an earlier
// version of this check only looked for `transform` and would have called a panel
// that slid with `translate` a non-creator.
const CB_CREATORS = ["transform", "perspective", "filter", "backdrop-filter", "will-change", "contain"];
const CB_ANIMATABLE = CB_CREATORS.concat(["translate", "scale", "rotate"]);
const qaPanelBody = bodies("#quickActionsPanel")[0] || "";
const panelOwnsACreator = CB_CREATORS.filter((p) => new RegExp("(?:^|[;{])\\s*" + p + "\\s*:").test(qaPanelBody));
const panelAnimatesCreator = CB_ANIMATABLE.some((p) => new RegExp("\\b" + p + "\\s*:").test(panelDrop));
const qaPanelCarriesTheClass = !!(qaPanel && qaPanel.classes.has("dropdown-panel"));
const drawerInsidePanel = !!(qaPanel && qaDrawerEl && contains(qaPanel, qaDrawerEl));
if (panelAnimatesCreator && panelOwnsACreator.length === 0 && qaPanelCarriesTheClass && drawerInsidePanel) {
  ok(".dropdown-panel's drop animation creates a containing block and #quickActionsPanel declares none of the six, which is why #qaDrawer is measured from the panel for its 200ms and from the viewport for the rest - the transient the rule's comment records");
} else {
  bad(".dropdown-panel's drop animation creates a containing block and #quickActionsPanel declares none",
    "panel-drop creates=" + panelAnimatesCreator +
    " panel declares=" + (panelOwnsACreator.length ? panelOwnsACreator.join(",") : "<none>") +
    " #quickActionsPanel has .dropdown-panel=" + qaPanelCarriesTheClass +
    " #qaDrawer inside it=" + drawerInsidePanel +
    " - if the panel stops creating a containing block for fixed descendants the sheet's no longer flips: re-measure, then either retire the note at the rule or drop the inset from #qaDrawer");
}

// The DONE sentinel. Printed LAST, after every assertion, and it is the only
// thing the wrapper treats as proof this harness reached its end.
//
// A summary line is not that proof. `process.exit()` inside a REQUIRED module
// kills the requiring module too, so a harness that dies partway through - or one
// that is stubbed to print nothing - can leave the other harness's assertions
// silently unrun while both processes still exit 0 and no FAIL line appears. The
// wrapper's at-least floor cannot see that either, because a crash after the last
// assertion has already printed all the PASS lines the floor counts. Only a line
// that cannot be reached without reaching the end can.
//
// The count travels WITH the sentinel so the wrapper never has to know how many
// assertions this file should have, and so "nav_dom_test reported 74, expected 24"
// names the half that is wrong.
//
// THE COUNT IS ASSERTIONS RUN, not assertions PASSED - `pass + fail`. It used to
// print `pass`, which made the wrapper's count gate answer two questions with one
// number: a single genuinely failing assertion dropped the count, so the gate
// reported "a lost assertion, or a DOUBLE-RUN one" - naming two causes when the
// cause was neither. Verified by mutation: removing `aria-current="page"` from
// the Chat row failed exactly ONE assertion, and the count gate then fired on top
// of it, so the run carried a bookkeeping complaint about a failure that had
// already been reported correctly.
//
// `pass + fail` is what the gate is actually asking, and it is invariant under a
// legitimate failure, so nothing is given up to buy a cleaner diagnosis: a lost
// assertion is not run, a double-run one runs twice, and neither changes with the
// pass/fail split. The tally stays on its own line above, which is where a real
// failure is reported from. See test_nav_shell.sh's half-2 comment.
console.log("");
console.log("  " + pass + " passed, " + fail + " failed");
console.log("DONE nav_dom_test " + (pass + fail));
process.exit(fail === 0 ? 0 : 1);