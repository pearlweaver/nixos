// Drives the REAL attachCodeBlockCopyButtons against a minimal DOM stub and
// asserts the structural invariant behind the reported bug: the copy button
// scrolled away with the code instead of staying pinned in the corner.
//
// Root cause: .code-copy-btn is position:absolute, and it used to live INSIDE
// the <pre>. That <pre> is the horizontal scroll container, and an absolutely
// positioned descendant of a scroller is placed against the scroller's CONTENT
// and scrolls with it — so `right: 6px` meant 6px past the end of the longest
// line, not the visible edge.
//
// This was NOT assertable by grepping the source. `const wrap = pre` — aliasing
// the wrapper to the scroller — leaves every relevant line of code in place and
// restores the bug exactly, so a source assertion passes while the behaviour is
// broken. Only running the function can tell the difference, hence the stub.
//
// The stub is deliberately faithful about one thing the real DOM is strict
// about: a node cannot contain itself. appendChild throws in that case, so an
// aliased wrapper fails loudly here instead of passing quietly.
const fs = require("fs");

function makeEl(tag) {
  // className and classList MUST read the same set: the implementation sets
  // className by assignment (btn.className = "... code-copy-btn") and tests
  // membership via classList.contains. Two separate stores made every lookup
  // miss, which reads as "no button was created" rather than "the stub is wrong".
  const cls = new Set();
  const el = {
    tagName: tag, children: [], parentNode: null, dataset: {},
    _text: "", _html: "", _attrs: {}, _h: {},
    get className() { return [...cls].join(" "); },
    set className(v) { cls.clear(); String(v).split(/\s+/).filter(Boolean).forEach((c) => cls.add(c)); },
    get textContent() { return this._text; },
    set textContent(v) { this._text = v; this.children = []; },
    get innerHTML() { return this._html; },
    set innerHTML(v) { this._html = v; },
    setAttribute(k, v) { this._attrs[k] = v; },
    addEventListener(ev, fn) { this._h[ev] = fn; },
    appendChild(c) {
      if (c === this) {
        throw new Error("HierarchyRequestError: a node cannot contain itself");
      }
      if (c.parentNode) c.parentNode.removeChild(c);
      c.parentNode = this;
      this.children.push(c);
      return c;
    },
    insertBefore(node, ref) {
      if (node === ref) throw new Error("NotFoundError: node is its own reference");
      if (node === this) throw new Error("HierarchyRequestError: a node cannot contain itself");
      if (node.parentNode) node.parentNode.removeChild(node);
      const i = this.children.indexOf(ref);
      node.parentNode = this;
      this.children.splice(i < 0 ? this.children.length : i, 0, node);
      return node;
    },
    removeChild(c) {
      const i = this.children.indexOf(c);
      if (i >= 0) this.children.splice(i, 1);
      c.parentNode = null;
      return c;
    },
    querySelector(sel) { return this.querySelectorAll(sel)[0] || null; },
    querySelectorAll(sel) {
      const out = [];
      const tagSel = sel.trim();
      const clsSel = tagSel.startsWith(".") ? tagSel.slice(1) : null;
      (function walk(n) {
        for (const c of n.children) {
          if (clsSel ? c.classList.contains(clsSel) : c.tagName === tagSel) out.push(c);
          walk(c);
        }
      })(el);
      return out;
    },
  };
  el.classList = {
    add: (c) => cls.add(c),
    remove: (c) => cls.delete(c),
    contains: (c) => cls.has(c),
    toggle: (c, on) => {
      const want = on === undefined ? !cls.has(c) : !!on;
      if (want) cls.add(c); else cls.delete(c);
      return want;
    },
  };
  return el;
}

global.document = { createElement: makeEl };
global.COPY_ICON_SVG = '<svg></svg>';
global.CHECK_ICON_SVG = '<svg></svg>';
global.copyTextToClipboard = () => {};

// Pull just attachCodeBlockCopyButtons out of the real source. Brace-matched so
// the test tracks the implementation instead of pinning a line range.
const src = fs.readFileSync(process.argv[2], "utf8");
const start = src.indexOf("function attachCodeBlockCopyButtons");
if (start < 0) throw new Error("attachCodeBlockCopyButtons not found in " + process.argv[2]);
let depth = 0, i = src.indexOf("{", start), end = -1;
for (let j = i; j < src.length; j++) {
  if (src[j] === "{") depth++;
  else if (src[j] === "}") {
    depth--;
    if (depth === 0) { end = j + 1; break; }
  }
}
const attachCodeBlockCopyButtons = eval("(" + src.slice(start, end) + ")");

// --- fixture: one code block inside a chat bubble ---
const bubble = makeEl("div");
bubble.className = "entry-bubble";
const prose = makeEl("div");
prose.className = "prose";
bubble.appendChild(prose);
const pre = makeEl("pre");
const code = makeEl("code");
code.textContent = "const x = 1;";
pre.appendChild(code);
prose.appendChild(pre);

let threw = null;
try {
  attachCodeBlockCopyButtons(prose);
} catch (e) {
  threw = e;
}

let fails = 0;
const out = (ok, name, detail) => {
  if (!ok) fails++;
  process.stdout.write((ok ? "PASS\t" : "FAIL\t") + name + (ok || !detail ? "" : "\t" + detail) + "\n");
};

out(threw === null, "wiring the copy button does not throw",
    threw ? String(threw && threw.message) : "");

const btn = prose.querySelector(".code-copy-btn");
out(btn !== null, "a .code-copy-btn exists", "none was created");
const wrap = prose.querySelector(".code-block");

if (btn) {
  // The assertion that actually distinguishes the fix from the bug. An aliased
  // wrapper (const wrap = pre) makes these two the same node.
  out(btn.parentNode !== pre,
      "the button is NOT a child of the scrolling <pre>",
      "button.parentNode === pre, so it is inside the scroll container again");
  out(btn.parentNode === wrap,
      "the button's parent is the .code-block wrapper",
      "button.parentNode.className = " + (btn.parentNode && JSON.stringify(btn.parentNode.className)));
}
if (wrap) {
  out(wrap.tagName === "div", ".code-block is a <div>", "got <" + wrap.tagName + ">");
  out(wrap.parentNode === prose,
      "the wrapper sits inside the prose block, in flow",
      "the wrapper was not inserted where the pre was");
  out(pre.parentNode === wrap,
      "the <pre> was re-parented into the wrapper",
      "the pre is still a direct child of .prose");
  out(wrap.children.length === 2,
      "the wrapper holds exactly the pre and the button",
      "got " + wrap.children.length + " children: " +
      wrap.children.map((c) => c.tagName + "." + c.className).join(", "));
  // Order matters for painting: the button after the pre so it floats over.
  out(wrap.children[wrap.children.length - 1] === btn,
      "the button is the wrapper's last child (paints over the code)",
      "children: " + wrap.children.map((c) => c.tagName).join(", "));
}

// The copied text is captured before the re-parenting, so this also guards the
// real risk of the refactor: had the button stayed inside the <pre>, the text
// walked for copying would have picked up whatever the button contributes.
let copied = null;
global.copyTextToClipboard = (text) => { copied = text; };
if (btn && btn._h.click) {
  btn._h.click({ stopPropagation() {} });
  out(copied === "const x = 1;",
      "clicking copies the code text and nothing else",
      "copied: " + JSON.stringify(copied));
} else {
  out(false, "clicking copies the code text and nothing else", "no click handler was attached");
}

process.stdout.write(fails === 0 ? "\nALL PASS\n" : "\n" + fails + " FAILED\n");
process.exit(fails === 0 ? 0 : 1);