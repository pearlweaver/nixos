// jsdom-free effect harness for the sidebar shell's OVERLAY STACK.
//
// WHAT THIS FILE IS, AND WHY IT IS SEPARATE FROM nav_dom_test.js.
// nav_dom_test.js answers questions you can answer by READING the sources: does
// the element exist, what attributes does it carry, what does the cascade
// resolve to. This file answers questions you can only answer by RUNNING the
// code: where did focus end up, which `hidden` flags flipped, did `onClose` fire,
// does a second pop drain the stack.
//
// The separation is not tidiness. It is the difference between the two classes of
// defect the review found in Task 6, and both of them lived in the reading half:
//
//   - focus() landing on a `display:none` control. jsdom sets `activeElement`
//     regardless of visibility, so a jsdom smoke test reported "focus moved into
//     the sheet" green while the shipped code was focusing a hidden button. Every
//     source-reading assertion agreed with it.
//   - the four capabilities that decide whether a phone can open the sheet, focus
//     it, close it and get its sidebar back. Deleting any one of them left all
//     four suites green, because `popOverlay();` appears in three places and a
//     name matching itself proves nothing about what it does.
//
// So the functions are EXTRACTED FROM THE SHIPPED SOURCE AND CALLED. `compileFn`
// below is the whole mechanism, and it is the same technique code_copy_dom_test.js
// uses on a real function. The DOM they run against is the parser from
// nav_dom_test.js - required rather than duplicated, so the two halves cannot
// disagree about what a `[hidden]` subtree is.
//
// WHAT THE DOM HERE IS NOT. It is a fake, and it is browser-faithful about
// exactly TWO things: `focus()` on an element inside a `[hidden]` subtree is a
// no-op, and `blur()` moves focus to the document. Those two are what make the
// focus assertions meaningful, and they are documented on the methods themselves
// in nav_dom_test.js. Nothing else in the stub
// decides an assertion's outcome - the parser only turns text into nodes, and the
// functions under test are the shipped ones.
//
// jsdom is NOT a dependency of this repo, deliberately (see nav_dom_test.js's
// header). This file inherits that constraint: it requires nothing but its
// sibling and node's own modules.

const fs = require("fs");
const path = require("path");

const HERE = __dirname;
const SRC = path.join(HERE, "..");

const htmlSrc = fs.readFileSync(path.join(SRC, "perla-companion.html"), "utf8");
const jsSrc = fs.readFileSync(path.join(SRC, "perla-companion.js"), "utf8");

// The parser and its browser-faithful focus() live in the sibling, so there is
// one definition of both. Required here rather than copied: two parsers would be
// two definitions of `[hidden]`, and a disagreement between them would be
// invisible in exactly the assertions that matter most.
const dom = require("./nav_dom_test.js");
const { parseHTML, query, queryAll, contains, focusSinks } = dom;

let pass = 0;
let fail = 0;
const ok = (n) => { console.log("  PASS  " + n); pass++; };
const bad = (n, d) => { console.log("  FAIL  " + n); console.log("        " + d); fail++; };

// SCAN FLOOR. Same reasoning as the sibling's, and it matters more here: this
// file asserts nothing about the document's shape, so a parse that returned three
// nodes would make every "focus went nowhere" below look like a real verdict.
//
// Parsed ONCE and reused. The first draft called parseHTML twice in the same
// condition - once to prove it returns something, once to query it - directly
// under a comment arguing that a bad parse has to be visible, which is the worst
// place to parse the document twice: two parses means two chances to disagree,
// and the cost is paid for a result the first one already holds.
const scanDoc = parseHTML(htmlSrc);
if (scanDoc && query(scanDoc, "#sidebarSheet")) {
  ok("the sheet parsed and is reachable, so the effect assertions below have something to act on");
} else {
  bad("the sheet parsed and is reachable",
    "the parser could not find #sidebarSheet - every result below would be untrustworthy");
}

// ---------------------------------------------------------------------------
// Extract a shipped function and make it callable.
// ---------------------------------------------------------------------------

// The body of `function name(...) { ... }` at this file's indentation, which ends
// at a line holding exactly four spaces then `}`. That is this script's
// convention for a top-level function inside the spliced <script>, and it is what
// makes the extraction stop at the END of the function rather than running on to
// the next one. KNOWN LIMIT: a nested closure indented deeper would not confuse
// it (it needs exactly four spaces), but a top-level function CLOSING at a
// different indent would. Verified by the assertions below, which go red rather
// than silently passing a truncated body if either function is reformatted.
function fnBody(name) {
  const m = new RegExp("function " + name + "\\([^)]*\\) \\{([\\s\\S]*?)\\n {4}\\}").exec(jsSrc);
  return m ? m[1] : null;
}

// Compile that body into a callable, with the free names its source expects
// supplied as parameters. Every name in `params` is a PARAMETER of the compiled
// function, which is why a function's own arguments belong in the list: they are
// part of its signature, not something it closes over.
function compileFn(name, params) {
  const body = fnBody(name);
  if (body === null) return null;
  try {
    // No eslint-disable comment here, unlike what an earlier draft of this file
    // carried: there is no eslint config in this repo and no lint step in
    // run.sh, so the pragma suppressed nothing and only implied a rule that is
    // not enforced anywhere. code_copy_dom_test.js and selection_dom_test.js
    // both build code from source with no such comment.
    return new Function(...params, body);
  } catch (e) {
    return null;
  }
}

const pushOverlayFn = compileFn("pushOverlay", ["document", "overlayStack", "el", "onClose"]);
const popOverlayFn = compileFn("popOverlay", ["overlayStack"]);
// The OPEN half of the sequence, compiled and called for the same reason as the
// other two: syncSidebarSheetState is what actually sets `collapse.hidden`, and
// staging that flag by hand asserts a state the shipped code never produces.
// `sidebarTrigger`, `sidebarOverlay` and `document` are the free names its body
// reads, so they are supplied; `document` is a one-method stub because
// `getElementById` is the whole of what it uses. Its OWN parameter `open` is
// declared too, which compileFn needs - see above.
const syncSheetStateFn = compileFn("syncSidebarSheetState",
  ["open", "sidebarTrigger", "sidebarOverlay", "document"]);

// ---------------------------------------------------------------------------
// Everything below proves the overlay stack WORKS. The plumbing being spelled is
// asserted in nav_dom_test.js; naming a function proves nothing about what it
// does, and `popOverlay();` appears in closeSidebarSheet, in closeTopOverlay
// and in the Escape dispatcher.
// ---------------------------------------------------------------------------

if (!pushOverlayFn || !popOverlayFn || !syncSheetStateFn) {
  bad("pushOverlay, popOverlay and syncSidebarSheetState compile out of the shipped source",
    "pushOverlay: " + (pushOverlayFn ? "ok" : "missing/uncompilable") +
    ", popOverlay: " + (popOverlayFn ? "ok" : "missing/uncompilable") +
    ", syncSidebarSheetState: " + (syncSheetStateFn ? "ok" : "missing/uncompilable"));
} else {
  // The exact state openSidebarSheet hands to pushOverlay: the sidebar's nodes
  // moved into the sheet, and #sidebarCollapse - the FIRST focusable among them -
  // already hidden.
  //
  // The hidden flag is produced by the SHIPPED syncSidebarSheetState(true), not
  // assigned here. Round 1 of this review staged `collapse.hidden = true` by
  // hand, which meant the focus assertions below proved only that pushOverlay
  // copes with a hand-built state - not that the shipped open path produces it.
  // Swapping the two calls in openSidebarSheet (push before sync) or deleting
  // `if (collapse) collapse.hidden = open;` outright both reproduce the original
  // focus bug, and with a hand-staged flag neither was visible here. Calling the
  // real function makes the state the shipped code reaches it, so those two
  // defects now show up as a red assertion below rather than as a green suite.
  function stageSheet() {
    const d = parseHTML(htmlSrc);
    // #app ships `hidden` and the gate hides it on load, so the real state at
    // push time is an UNLOCKED app. Left hidden, every focus() below would be
    // refused by the browser-faithful rule and the harness would be testing
    // nothing. This one IS staged by hand, and deliberately: it is app-level
    // state the gate owns, not something the sheet's open path sets.
    query(d, "#app").hidden = false;
    const side = query(d, "#sidebar");
    const sh = query(d, "#sidebarSheet");
    const trigger = query(d, "#sidebarTrigger");
    const overlay = query(d, "#sidebarOverlay");
    const collapse = query(d, "#sidebarCollapse");
    while (side.firstChild) sh.appendChild(side.firstChild);
    sh.hidden = true;
    focusSinks.activeElement = trigger;
    // The shipped call, in the shipped order relative to the node move (which
    // openSidebarSheet does first, and which is why getElementById can still
    // find #sidebarCollapse inside the sheet - the ORDER of those three calls is
    // asserted in nav_dom_test.js, and run end to end here).
    // `open` is the function's own parameter, passed first, as the signature says.
    syncSheetStateFn(true, trigger, overlay, { getElementById: (id) => query(d, "#" + id) });
    return { d, sh, trigger, collapse, overlay };
  }

  // --- stage, then push ----------------------------------------------------
  const P = stageSheet();
  const stack = [];
  let onCloseRan = 0;
  pushOverlayFn({ activeElement: P.trigger }, stack, P.sh, () => { onCloseRan++; });
  if (P.sh.hidden === false) {
    ok("pushOverlay reveals the overlay it is given");
  } else {
    bad("pushOverlay reveals the overlay it is given",
      "el.hidden is still true - the mobile sheet would never appear on screen");
  }
  // The state that focus assertion depends on must be the SHIPPED one, or it is
  // asserting a state the app never reaches. Checked here so the dependency is
  // visible rather than assumed: syncSidebarSheetState(true) is what hides
  // #sidebarCollapse, and if it did not, everything below would be testing a
  // focus() the real open path never performs.
  if (P.collapse.hidden === true) {
    ok("the open path really does hide #sidebarCollapse (the shipped syncSidebarSheetState, called not hand-staged)");
  } else {
    bad("the open path really does hide #sidebarCollapse",
      "syncSidebarSheetState(true) left it visible - the focus assertions below are measuring a state the app does not produce");
  }

  // The OTHER two things syncSidebarSheetState owns, and the only ones nothing
  // else looks at. The structure half asserts the scrim STARTS hidden and the
  // trigger STARTS aria-expanded=false, which are statements about the MARKUP and
  // say nothing about the open path. A function that hid the collapse control but
  // never revealed the scrim would leave a permanently un-dismissible drawer: no
  // visible target to tap, and Escape the only way out. So the open path is run
  // and all three are looked at.
  if (P.overlay.hidden === false) {
    ok("the open path reveals #sidebarOverlay (the scrim that dismisses the sheet)");
  } else {
    bad("the open path reveals #sidebarOverlay",
      "syncSidebarSheetState(true) left the scrim hidden - a phone would have a visible drawer with nothing to tap to close it");
  }
  if (P.trigger.getAttribute("aria-expanded") === "true") {
    ok("the open path sets aria-expanded=true on the trigger");
  } else {
    bad("the open path sets aria-expanded=true on the trigger",
      'got "' + P.trigger.getAttribute("aria-expanded") + '" - the control that opened the dialog does not say it is open');
  }
  const landed = focusSinks.activeElement;
  if (landed && contains(P.sh, landed)) {
    ok("pushOverlay moves focus INTO the overlay");
  } else {
    bad("pushOverlay moves focus into the overlay",
      "focus is still on " + ((landed && landed.attrs.id) || "nothing") +
      " - a dialog carrying aria-modal=true that never receives focus tells a screen reader the page is inert while the caret is still on it");
  }
  // The shipped bug this whole file exists for: the FIRST focusable in the moved
  // nodes is #sidebarCollapse, which syncSidebarSheetState has just hidden. A
  // browser refuses focus() there.
  if (landed && landed !== P.collapse && !landed.closest("[hidden]")) {
    ok("the focused control is VISIBLE - #sidebarCollapse is hidden before the push, so a plain first-match would target a display:none button");
  } else {
    bad("the focused control is visible",
      landed
        ? "focus landed on " + (landed.attrs.id || landed.tagName) +
          ", which is inside a [hidden] subtree - focus() on a display:none element is a no-op in a real browser, so focus stays OUTSIDE the aria-modal dialog"
        : "nothing took focus at all");
  }
  if (landed && landed.classes && landed.classes.has("sidebar-menu-button")) {
    ok("focus lands on a nav row (#" + (landed.attrs.id || "unnamed") + "), the first visible control in the sheet");
  } else {
    bad("focus lands on a nav row",
      landed ? "got <" + landed.tagName + "> " + JSON.stringify(landed.attrs.id || "") : "nothing took focus");
  }

  // --- pop -----------------------------------------------------------------
  const popped = popOverlayFn(stack);
  if (popped === true && P.sh.hidden === true) {
    ok("popOverlay closes the overlay and reports that it did");
  } else {
    bad("popOverlay closes the overlay and reports that it did",
      "returned " + JSON.stringify(popped) + ", el.hidden=" + P.sh.hidden +
      " - closeSidebarSheet routes entirely through popOverlay, so with this broken the sheet can never be dismissed at all");
  }
  if (onCloseRan === 1) {
    ok("popOverlay runs the layer's onClose (parkSidebarRows)");
  } else {
    bad("popOverlay runs the layer's onClose",
      "fired " + onCloseRan + " time(s) - the sidebar's nodes are never moved back, so the desktop sidebar stays empty after one phone sheet close");
  }
  if (focusSinks.activeElement === P.trigger) {
    ok("popOverlay hands focus back to where it came from");
  } else {
    bad("popOverlay hands focus back to where it came from",
      "focus is on " + ((focusSinks.activeElement && focusSinks.activeElement.attrs.id) || "nothing") +
      " - a modal that opens without remembering its origin strands the caret on the document");
  }

  // --- pop on an empty stack ----------------------------------------------
  const emptyStack = [];
  const emptyResult = popOverlayFn(emptyStack);
  const afterEmpty = { hidden: P.sh.hidden, focus: focusSinks.activeElement };
  if (emptyResult === false && afterEmpty.hidden === true && afterEmpty.focus === P.trigger) {
    ok("popOverlay on an empty stack is a no-op that reports false (so Escape falls through)");
  } else {
    bad("popOverlay on an empty stack is a no-op",
      "returned " + JSON.stringify(emptyResult) + ", hidden=" + afterEmpty.hidden +
      " - a truthy return here would make Escape swallow the keystroke with nothing to close");
  }

  // --- stacking order is top-down, by EFFECT -------------------------------
  const A = stageSheet();
  const B = parseHTML(htmlSrc);
  query(B, "#app").hidden = false;
  const bSheet = query(B, "#sidebarSheet");
  bSheet.hidden = true;
  const twoStack = [];
  const closeOrder = [];
  pushOverlayFn({ activeElement: A.trigger }, twoStack, A.sh, () => closeOrder.push("A"));
  pushOverlayFn({ activeElement: A.trigger }, twoStack, bSheet, () => closeOrder.push("B"));
  popOverlayFn(twoStack);
  const midState = A.sh.hidden;
  popOverlayFn(twoStack);
  // After the FIRST pop the bottom layer is still OPEN: that is what "one press
  // closes exactly one layer" means, and it is the assertion that would fail if
  // a single pop unwound the whole stack.
  if (closeOrder.join(",") === "B,A" && midState === false && bSheet.hidden === true &&
      A.sh.hidden === true) {
    ok("two stacked overlays unwind newest-first, one layer per pop");
  } else {
    bad("two stacked overlays unwind newest-first",
      "close order was [" + closeOrder.join(",") + "], after the first pop A.hidden=" + midState +
      ", at the end A.hidden=" + A.sh.hidden + " B.hidden=" + bSheet.hidden +
      " - closing the bottom layer first is the original Escape bug with the stack on top of it");
  }
  const drained = popOverlayFn(twoStack);
  if (drained === false) {
    ok("a third pop on a drained stack reports false");
  } else {
    bad("a third pop on a drained stack reports false", "returned " + JSON.stringify(drained));
  }
}

// The mechanism, named. The effect test above is the load-bearing one; this
// says WHY it passes, so that a future rewrite which fixes the same thing a
// different way is not read as a regression of the filter.
const pushBody = fnBody("pushOverlay");
if (pushBody && /closest\("\[hidden\]"\)/.test(pushBody)) {
  ok("pushOverlay's focusable lookup excludes [hidden] subtrees");
} else {
  bad("pushOverlay's focusable lookup excludes [hidden] subtrees",
    "no closest(\"[hidden]\") filter - querySelector matches hidden descendants happily, and a browser will not focus one");
}

// ---------------------------------------------------------------------------
// THE NAV ROUTER, RUN. Four shipped functions in ONE closure, so the state they
// share is shared for real.
//
// Why the Chat route is a question only RUNNING can answer. setDestination used
// to move aria-current and stop, so the Chat row - which, unlike the four
// overlay rows, has no feature site and no handler of its own to do anything -
// did nothing when pressed. Making it work means routing it to switchTier, and
// "route" and "which tier" are both invisible to a regex: the whole defect is
// that a name appears where no call does, and a shape check passes on a comment.
//
// Why `with`. switchTier assigns activeTier and closeHistoryPanel assigns
// activeOverlay, and both have to PERSIST across the calls below - a second
// switchTier has to see what the first committed, because that is the whole
// question ("is it the last tier USED, or a constant?"). A primitive parameter
// cannot carry a mutation out of a `new Function`, so the usual answer is to
// rewrite the source to `state.activeTier`, and THAT is the trap: a rewrite that
// missed a name would silently change the behaviour under test, and the
// assertions would be measuring the harness. `with (state) { ... }` leaves every
// shipped byte untouched - a name the block does not declare resolves through
// the object, a name it does declare (lastActiveTier, and the four functions)
// shadows it - so the code that runs is the code that ships.
//
// The one thing spliced in from outside is the `let lastActiveTier = ...;`
// DECLARATION, read out of the shipped source by regex rather than written here.
// It has to be spliced because it is not inside any of the four bodies, and it
// must be the shipped line rather than a copy: the effect of seeding it wrong is
// exactly what the assertions below look for, so a harness that seeded it
// correctly itself would be asserting against its own fixture.
// Mutation: `let lastActiveTier = 1;` -> red on the initialisation assertion.
// Mutation: delete the `lastActiveTier = tier;` line from switchTier -> red on
//            the recorded-tier assertion.
// Mutation: `switchTier(1)` in setDestination -> red on the last-used assertion.
const lastDeclM = /^[ \t]*let lastActiveTier = [^;]+;[ \t]*$/m.exec(jsSrc);
// The overlay->destination map is spliced for the same reason as the declaration
// above: updateTierButtonHighlight reads it, and a copy written here would be a
// fixture the assertions then agree with by construction.
const destMapM = /^ {4}const DESTINATION_FOR_OVERLAY = \{[\s\S]*?\n {4}\};[ \t]*$/m.exec(jsSrc);
const navBodies = {
  switchTier: fnBody("switchTier"),
  setDestination: fnBody("setDestination"),
  updateTierButtonHighlight: fnBody("updateTierButtonHighlight"),
  closeHistoryPanel: fnBody("closeHistoryPanel"),
  closeDrivePanel: fnBody("closeDrivePanel"),
};
const navParts = [lastDeclM, destMapM].concat(
  Object.entries(navBodies).map(([k, v]) => (v ? true : null)));
const navBuild = navParts.every(Boolean)
  ? new Function("state", `
      with (state) {
        ${lastDeclM[0].trim()}
        ${destMapM[0].trim()}
        function switchTier(tier) {
${navBodies.switchTier}
        }
        function setDestination(name) {
${navBodies.setDestination}
        }
        function updateTierButtonHighlight() {
${navBodies.updateTierButtonHighlight}
        }
        function closeHistoryPanel() {
${navBodies.closeHistoryPanel}
        }
        function closeDrivePanel() {
${navBodies.closeDrivePanel}
        }
        return {
          switchTier, setDestination, updateTierButtonHighlight,
          closeHistoryPanel, closeDrivePanel,
          getLast: () => lastActiveTier,
          getActive: () => activeTier,
          getOverlay: () => activeOverlay,
        };
      }
    `)
  : null;

if (navBuild) {
  // A stub that performed the behaviour under test would make these assertions
  // pass with the real code deleted, so every one of them is a RECORD of
  // something the shipped function did: sessionStorage writes are how switchTier
  // commits a tier, and output.innerHTML is what it paints. closeHistoryPanel is
  // the SHIPPED one, compiled in above - stubbing it would have made the
  // re-entrant path (overlay closes -> updateTierButtonHighlight ->
  // setDestination("chat") -> switchTier) unreachable, and that path is the
  // whole risk in this change.
  function stageNav(activeTier, activeOverlay) {
    const d = parseHTML(htmlSrc);
    const navDoc = {
      // Only turns text into nodes: the same selector engine the rest of this
      // suite uses, so "[data-destination]" means what it means everywhere else.
      querySelectorAll: (sel) => queryAll(d, sel),
    };
    const commits = [];
    const closed = [];
    // Transcript reads. See the getChatLog stub below for why this exists rather
    // than `output.innerHTML`.
    const repaints = [];
    const state = {
      document: navDoc,
      activeTier: activeTier,
      activeOverlay: activeOverlay,
      liveOutputHTML: null,
      // switchTier's commit, observed where the app actually records it.
      sessionStorage: { setItem: (k, v) => commits.push(k + "=" + v) },
      output: { innerHTML: "initial", scrollIntoView: () => {} },
      // A distinct transcript per tier, so "which tier's chat got painted" is
      // readable rather than inferred.
      //
      // The CALL is also counted, and that count is the only thing that can
      // actually observe a repaint. `output.innerHTML` cannot: switchTier assigns
      // `output.innerHTML = getChatLog(tier)` and the stub returns the same string
      // whichever tier it is asked for at the same point in the flow, so the
      // assignment looks identical whether it happened once or twice. The first
      // draft of the "commits AND repaints" assertion relied on that value and its
      // second half was therefore vacuous - it passed under a mutation that
      // repainted twice. `repaints` counts the reads of the transcript, which is
      // one per switchTier that gets past the early return, so one-per-tap is a
      // real measurement and a double repaint is visible.
      getChatLog: (tier) => { repaints.push(tier); return "log-of-tier-" + tier; },
      setChatLog: () => {},
      saveCurrentTierDraft: () => {},
      restoreTierDraft: () => {},
      restoreFailedSendState: () => {},
      showWelcome: () => {},
      clearTierUnread: () => {},
      updateTier2UnreadBadge: () => {},
      updateComposerMode: () => {},
      closeRemindersPanel: () => closed.push("reminders"),
      closeQuickActionsPanel: () => closed.push("quick-actions"),
      // closeDrivePanel is the SHIPPED one, compiled in above. A stub that merely
      // RECORDED the call went green while re-entering forever: switchTier sees
      // activeOverlay === "drive", calls this, and if it does not clear
      // activeOverlay the derived setDestination routes straight back into
      // switchTier - unbounded recursion, and the assertion below never got to
      // print. That was a defect in the harness, not a finding: the real
      // closeDrivePanel sets activeOverlay = null, which is the one line the
      // re-entrancy depends on, so the shipped function is what runs here.
      closeHistoryDayMenu: () => {},
      closeDriveItemMenu: () => {},
      closeFileViewerModal: () => {},
      driveBtn: { classList: { add: () => {}, remove: () => {} } },
      drivePanel: { hidden: false },
      contentWrap: { hidden: false },
      // NO tierBadge, and its absence is the point. This stage's state is built
      // from what the shipped functions actually reference, so a stub for an
      // element nothing reads is a stub that would hide a writer coming back - or
      // a removal that stopped happening. Nothing in this harness needs it: the
      // tier pill and the Full Mode countdown were both removed at ux-fix-5 and
      // the functions below (toggleSidebar, applySidebarCollapsed,
      // releaseSidebarFocus) never touched them.
      tier1Btn: { classList: { toggle: () => {} } },
      tier2Btn: { classList: { toggle: () => {} } },
      historyBtn: { classList: { add: () => {}, remove: () => {} } },
      historyPanel: { hidden: false },
      historyTierFilter: { querySelectorAll: () => [] },
      historyDayBtnLabel: { textContent: "" },
      historyStatus: { textContent: "" },
      historySelectedDate: "",
      historyEntriesCache: [],
      historyTierMode: "all",
    };
    const nav = navBuild(state);
    return {
      nav: nav, state: state, commits: commits, closed: closed,
      repaints: repaints, doc: d,
    };
  }
  const tierCommits = (s) => s.commits.filter((c) => c === "perla_active_tier=1" ||
    c === "perla_active_tier=2");

  // --- 1. initialisation must NOT commit anything --------------------------
  // The shipped call order that makes this reachable: initAppState() calls
  // updateTierButtonHighlight() -> setDestination("chat"), so the Chat route
  // runs on a plain page load with nothing to go back from. With lastActiveTier
  // equal to activeTier - which is what seeding it from activeTier buys -
  // switchTier takes its `wasSameTier && !hadOverlay` early return and touches
  // nothing. Seeded with a literal instead, this same call would see a
  // disagreement and commit the wrong tier over the restored one, which is the
  // clobber the seeding exists to prevent.
  const init = stageNav(2, null);
  if (init.nav.getLast() === 2) {
    ok("lastActiveTier starts out equal to activeTier, so the Chat route is a no-op on load");
  } else {
    bad("lastActiveTier starts out equal to activeTier",
      "seeded as " + init.nav.getLast() + " while activeTier is 2 - a reload on Tier 2 would be dragged to Tier 1 by the Chat row's own route");
  }
  init.nav.setDestination("chat");
  if (tierCommits(init).length === 0 && init.state.output.innerHTML === "initial") {
    ok("setDestination(\"chat\") during initialisation commits no tier and repaints nothing");
  } else {
    bad("setDestination(\"chat\") during initialisation is a no-op",
      "commits=" + JSON.stringify(tierCommits(init)) + " output=" + init.state.output.innerHTML +
      " - initAppState() calls updateTierButtonHighlight(), so this runs on every load and would overwrite the restored tier");
  }

  // --- 2. Chat returns to the LAST USED tier, not a constant ---------------
  // On Tier 2 with History open. A hardcoded switchTier(1) here commits 1 and
  // paints tier 1's transcript, which is the bug in its most expensive form: the
  // user reads History, presses Chat, and lands in the other conversation.
  const used = stageNav(2, "history");
  used.nav.setDestination("chat");
  const usedCommits = tierCommits(used);
  if (usedCommits.length === 1 && usedCommits[0] === "perla_active_tier=2") {
    ok("Chat returns to the LAST USED tier (2), not a constant - and commits it exactly once");
  } else {
    bad("Chat returns to the last used tier",
      "committed " + JSON.stringify(usedCommits) +
      " - a literal tier, or a re-entrant second commit, would show up as one of these");
  }
  if (used.closed.length === 0 && used.nav.getOverlay() === null &&
      used.state.output.innerHTML === "log-of-tier-2") {
    ok("Chat closed the open overlay and painted the LAST USED tier's transcript");
  } else {
    bad("Chat closed the overlay and painted the last tier's transcript",
      "overlay=" + used.nav.getOverlay() + " output=" + used.state.output.innerHTML +
      " - the overlay's read-only chrome is still up, or the wrong conversation was restored");
  }

  // --- 3. the recorded tier FOLLOWS a real switch --------------------------
  // switchTier(2) on a page sitting at Tier 1, then the same scenario. This is
  // what makes the previous assertion "last USED" rather than "tier 2": the value
  // has to move when the user switches, and move back again.
  const moved = stageNav(1, null);
  moved.nav.switchTier(2);
  const movedRecorded = moved.nav.getLast();
  moved.nav.setDestination("quick-actions"); // a different destination: must not touch the tier
  moved.state.activeOverlay = "history";
  moved.nav.setDestination("chat");
  const movedCommits = tierCommits(moved);
  if (movedRecorded === 2 && movedCommits.length === 2 &&
      movedCommits[0] === "perla_active_tier=2" && movedCommits[1] === "perla_active_tier=2") {
    ok("the recorded tier follows switchTier in both directions, so it is the last USED and not a frozen value");
  } else {
    bad("the recorded tier follows switchTier",
      "recorded=" + movedRecorded + " commits=" + JSON.stringify(movedCommits) +
      " - switchTier(2) must record 2, and the Chat route must then return to 2");
  }

  // --- 3b. the tier BUTTONS, pressed over an open overlay ------------------
  // This is the path the PLACEMENT of `lastActiveTier = tier` inside switchTier
  // actually decides, and it is the one a user takes most: Tier 1, History open,
  // press T2. switchTier closes History, closing it calls
  // updateTierButtonHighlight, and that reaches setDestination("chat") ->
  // switchTier(lastActiveTier) while activeTier is still the OLD tier. So what
  // the nested call does depends entirely on which value lastActiveTier holds at
  // that instant: recorded AFTER the closes, it still holds the old tier, the
  // nested call matches `wasSameTier && !hadOverlay` and returns having done
  // nothing. Recorded BEFORE them, it already holds the new tier, the nested call
  // misses that exit, and one tap on T2 commits and repaints the whole tier
  // twice.
  //
  // An earlier draft of this file asserted only the Chat route, which reaches the
  // same nested call with lastActiveTier and activeTier already EQUAL - so it
  // could not tell the two placements apart, and the mutation that moved the
  // assignment above the closes stayed green. Hence this scenario, which is the
  // only one where the placements differ. It is therefore a SINGLE POINT OF
  // FAILURE for that placement, which is why both halves below are measured.
  //
  // BOTH halves, and they are measured DIFFERENTLY on purpose. `repaints` counts
  // the transcript reads `switchTier` performs; `output.innerHTML` cannot, because
  // the stub returns the same string on both passes and the assignment looks
  // identical whether it ran once or twice. The first draft checked
  // `output.innerHTML === "log-of-tier-2"` and called that a repaint check - it
  // was vacuous, and the repaint half of the name was measuring the commit half a
  // second time. `repaints.length === 1` is a genuine second measurement: the
  // misplaced assignment runs the repaint twice and this catches it on its own.
  const btn = stageNav(1, "history");
  btn.nav.switchTier(2);
  const btnCommits = tierCommits(btn);
  if (btnCommits.length === 1 && btnCommits[0] === "perla_active_tier=2" &&
      btn.repaints.length === 1 && btn.repaints[0] === 2 &&
      btn.nav.getLast() === 2 && btn.nav.getActive() === 2 &&
      btn.closed.length === 0 && btn.state.output.innerHTML === "log-of-tier-2") {
    ok("pressing a tier button over an open overlay commits once and repaints once - the re-entrant Chat call returns without acting");
  } else {
    bad("pressing a tier button over an open overlay commits once and repaints once",
      "commits=" + JSON.stringify(btnCommits) + " repaints=" + JSON.stringify(btn.repaints) +
      " lastActiveTier=" + btn.nav.getLast() +
      " activeTier=" + btn.nav.getActive() + " output=" + btn.state.output.innerHTML +
      " - a second commit or repaint means the nested setDestination(\"chat\") missed switchTier's early return, which is what decides where lastActiveTier is assigned");
  }

  // --- 4. the other four destinations keep their behaviour -----------------
  // Two shapes, because one is not enough. With nothing open, switchTier would
  // hit its early return anyway, so a setDestination that switched tiers for
  // EVERY destination would go unnoticed - which is exactly the mutation this
  // pair of checks exists to catch: dropping the `name === "chat"` guard leaves
  // the no-overlay case identical and only misbehaves once something is open.
  //
  // The second shape is the shipped OPEN path, not a synthetic one: opening Drive
  // sets activeOverlay and then calls updateTierButtonHighlight(), which derives
  // the destination. With the guard gone that same call switches tier, which
  // closes the Drive panel that was being opened.
  const other = stageNav(2, null);
  other.nav.setDestination("drive");
  if (tierCommits(other).length === 0 && other.state.output.innerHTML === "initial") {
    ok("a non-chat destination with nothing open only moves aria-current");
  } else {
    bad("a non-chat destination with nothing open only moves aria-current",
      "commits=" + JSON.stringify(tierCommits(other)) + " output=" + other.state.output.innerHTML);
  }
  const opening = stageNav(2, "drive");
  opening.nav.updateTierButtonHighlight();
  if (tierCommits(opening).length === 0 && opening.closed.length === 0 &&
      opening.nav.getOverlay() === "drive") {
    ok("deriving a destination for an OPEN overlay - the shipped Drive-open path - does not switch tiers, or close the panel being opened");
  } else {
    bad("deriving a destination for an open overlay does not switch tiers",
      "commits=" + JSON.stringify(tierCommits(opening)) + " panelsClosed=" + JSON.stringify(opening.closed) +
      " overlay=" + opening.nav.getOverlay() +
      " - setDestination's tier route is guarded on name === \"chat\"; unguarded it closes the overlay the open path just raised");
  }
  // --- 5. aria-current survives the new call ------------------------------
  // setDestination grew a second statement, and the loop above it is the ONE
  // writer of the attribute - so what matters is that the ADDITION did not
  // swallow it.
  //
  // Reached the way the app reaches it rather than by calling setDestination
  // directly: the overlay is up, updateTierButtonHighlight() derives "history is
  // the current page", then the SHIPPED closeHistoryPanel() runs. That is the
  // transition that has to move the claim off History and onto Chat, and it is
  // the only shape in which the REMOVAL half is exercised at all.
  //
  // An earlier draft started from the markup's own state and pressed Chat, which
  // passed with the harness's removeAttribute stubbed to do NOTHING - Chat already
  // claimed aria-current there, so the four removals were removing an attribute
  // none of the rows had, and the assertion could not fail. Both halves are in
  // the condition: the precondition names who claims it BEFORE, because a
  // precondition that silently did not hold would leave the assertion green for
  // the wrong reason.
  // Mutation: stub removeAttribute as a no-op -> red.
  const aria = stageNav(2, "history");
  const ariaClaims = () => queryAll(aria.doc, "[data-destination]")
    .filter((el) => el.getAttribute("aria-current") === "page")
    .map((el) => el.getAttribute("data-destination"))
    .sort();
  aria.nav.updateTierButtonHighlight();
  const whileOverlayUp = ariaClaims();
  aria.nav.closeHistoryPanel();
  const claims = ariaClaims();
  if (whileOverlayUp.join(",") === "history" && claims.join(",") === "chat") {
    ok("closing the overlay moves aria-current off it and onto Chat, and exactly one row claims it throughout");
  } else {
    bad("closing the overlay moves aria-current onto Chat",
      "with the overlay up: [" + whileOverlayUp.join(", ") + "], after closing: [" + claims.join(", ") + "]" +
      " - two rows claiming it is a screen reader announcing \"current page\" twice, and a row that never lost it is the attribute set without being removed");
  }
} else {
  bad("the six nav functions and lastActiveTier's declaration compile out of the shipped source",
    "declaration: " + (lastDeclM ? "ok" : "missing") +
    ", DESTINATION_FOR_OVERLAY: " + (destMapM ? "ok" : "missing") +
    ", " + Object.keys(navBodies).map((k) => k + ": " + (navBodies[k] ? "ok" : "missing")).join(", ") +
    " - every result below would be untrustworthy");
}

// ---------------------------------------------------------------------------
// THE COLLAPSE TOGGLE, RUN. `applySidebarCollapsed` and `toggleSidebar` are
// extracted and called, because both halves of the shift fix are decisions this
// function makes and neither is visible to a regex:
//
//   1. it writes `data-collapsed` on the SIDEBAR (which is what takes the rail
//      out of the flow and swaps the grid to one column), and
//   2. it writes the SAME flag on #app.
//
// (2) is the one that is easy to lose and impossible to see. `grid-template-
// columns` has to be re-declared for the grid to react, there is no other
// selector that could carry it (`:has()` was rejected - see the CSS comment), and
// nothing in the stylesheet mentions #app's attribute. Delete that one line and
// every source-reading assertion in the sibling stays green while the chat jumps
// 256px right on every collapse.
//
// aria-expanded is the third: it has to stay TRUE in both states, which means it
// tracks `!sidebarCollapsed` and not `sidebarCollapsed`. The inverse is a single
// character and it makes the control announce the wrong thing to a screen reader
// in every state - which is precisely the class of bug no assertion here could
// have found by reading, and which the markup's own `aria-expanded="true"` start
// value cannot catch on its own.
// ---------------------------------------------------------------------------

// `with (state)`, for the same reason the router harness above uses it and not
// `new Function` parameters: toggleSidebar ASSIGNS to sidebarCollapsed, and a
// primitive parameter cannot carry a mutation back out. A parameter list would
// therefore compile it into a function that flips a local copy, calls apply, and
// commits the right thing while leaving the caller's state untouched - every
// assertion here green, and the real toggle doing nothing to the page. `with`
// leaves the shipped body byte-for-byte.
const applyBody = fnBody("applySidebarCollapsed");
const toggleBody = fnBody("toggleSidebar");
const releaseBody = fnBody("releaseSidebarFocus");
const applyFn = applyBody === null ? null : new Function("state", `with (state) {\n${applyBody}\n}`);
const toggleFn = toggleBody === null ? null : new Function("state", `with (state) {\n${toggleBody}\n}`);
const releaseFn = releaseBody === null ? null : new Function("state", `with (state) {\n${releaseBody}\n}`);

// A SCAN FLOOR, and it is placed HERE - above the whole collapsed-state section,
// not inside it - for a reason that was found by mutation. Delete
// releaseSidebarFocus from the shipped source and every call to it throws, so the
// harness CRASHES inside `t.toggle()` long before a check written further down is
// reached. The crash is red and it is caught (the DONE sentinel and the exit-code
// gate exist for exactly that), but it is red for a coarse reason: it says the
// harness died, not which capability went missing. Asserted up here, the same
// mutation is red with a diagnosis instead of a stack trace - and the assertion
// that guards it is not shadowed by an earlier crash.
if (releaseFn) {
  ok("releaseSidebarFocus compiles out of the shipped source");
} else {
  bad("releaseSidebarFocus compiles out of the shipped source",
    "the function the collapse path calls could not be extracted, so every focus assertion below would be measuring nothing");
}

// A real document, not a stub: the function looks its targets up by id, and the
// claim is about WHICH element carries the flag. A `getElementById` that returned
// the same object for every id would make "both elements carry it" true by
// construction.
// A bare element with a dataset and nothing else, for `document.body`. It is
// deliberately not a parsed node: the only thing any assertion asks of it is
// whether the collapsed state was written to it.
function makePlainNode() {
  const attrs = {};
  return {
    attrs: attrs,
    dataset: new Proxy({}, {
      get: (_t, k) => attrs["data-" + String(k).replace(/[A-Z]/g, (c) => "-" + c.toLowerCase())],
      set: (_t, k, v) => { attrs["data-" + String(k).replace(/[A-Z]/g, (c) => "-" + c.toLowerCase())] = String(v); return true; },
    }),
  };
}

function stageCollapse(collapsed) {
  const d = parseHTML(htmlSrc);
  const sidebar = query(d, "#sidebar");
  const app = query(d, "#app");
  const btn = query(d, "#sidebarCollapse");
  // #app ships `hidden` and the gate reveals it on unlock, so the real state at
  // any moment a person can press the collapse control is an UNLOCKED app. Left
  // hidden, every focus() below is refused by the browser-faithful rule in
  // nav_dom_test.js - the whole subtree is a [hidden] subtree - and the harness
  // would report the collapse fix as not working while testing a state no user
  // can reach. The sibling harness stages this the same way, and for the same
  // reason. It is app-level state the gate owns, not something the collapse path
  // sets, which is why it is staged rather than produced.
  app.hidden = false;
  // `#sidebarCollapse` is the REAL parsed node, not a hand-built wrapper around
  // its attributes. The collapse fix moves focus by asking the focused element
  // `closest(".sidebar")` and by landing focus on a real element, and a wrapper
  // carrying only `attrs`/`hidden`/`setAttribute` cannot answer either - it
  // would have to be given a `closest` and a `focus` that decide the very
  // question under test, which is the shape of stub this file's header calls
  // out. The wrapper it replaced shared `btn.attrs` anyway, so every assertion
  // reading `getAttribute`/`dataset` off it reads the same bytes as before.
  const cell = btn;
  cell.hidden = false;
  // `#app` and `#sidebar` are two DIFFERENT nodes from the same parsed tree, so
  // "the flag reached both" is a fact about the document and not about one
  // object wearing two names.
  // `body` exists because every real document has one, and a second writer of the
  // collapsed state reaching for `document.body.dataset` is the plausible way to
  // break the single-writer claim. Without it, that mutation CRASHED the harness
  // instead of failing one assertion - red for the wrong reason, and it took the
  // assertions after it down with it.
  //
  // `activeElement` and `querySelector` are here for the same reason the node is:
  // releaseSidebarFocus() reads the focused element and looks the landing target
  // up. Both are the shipped document, not a decision - `activeElement` reads the
  // one sink makeNode's browser-faithful `focus()` writes, and `querySelector`
  // is the sibling's own matcher over this parsed tree, so "focus is on <main>"
  // is a fact about these nodes.
  const fakeDoc = {
    body: makePlainNode(),
    getElementById: (id) => (id === "sidebarCollapse" ? cell : null),
    get activeElement() { return focusSinks.activeElement; },
    querySelector: (sel) => query(d, sel),
  };
  const commits = [];
  // applySidebarCollapsed is spliced as the SHIPPED compiled body rather than
  // stubbed: the whole claim is that one function writes both flags, and a stub
  // that "wrote both" would satisfy it while the real one wrote one.
  const state = {
    sidebar: sidebar, sidebarCollapsed: collapsed, document: fakeDoc,
    sessionStorage: { setItem: (k, v) => commits.push(k + "=" + v) },
  };
  // toggleSidebar calls `applySidebarCollapsed()` with NO ARGUMENT, so the
  // compiled body - which reads its state through `with` - is bound by an arrow
  // rather than by the call. Passing the state through the argument list would
  // have meant rewriting the shipped call site, which is exactly the rewrite
  // this harness exists to avoid.
  state.applySidebarCollapsed = () => applyFn(state);
  // releaseSidebarFocus() is bound the same way: it is a real shipped function,
  // not a stub, so deleting its body has to fail an assertion here rather than
  // leave the harness agreeing with a function that does nothing.
  state.releaseSidebarFocus = releaseBody === null ? null : () => releaseFn(state);
  // #app is reached through the SAME getElementById applySidebarCollapsed uses -
  // the point is which element it writes, and a second lookup invented here
  // would not be the one the shipped function makes.
  fakeDoc.getElementById = (id) => {
    if (id === "sidebarCollapse") return cell;
    if (id === "app") return app;
    return null;
  };
  return {
    d: d, sidebar: sidebar, app: app, btn: cell,
    apply: (c) => { state.sidebarCollapsed = c; state.applySidebarCollapsed(); },
    toggle: () => toggleFn(state),
    commits: commits,
    get flag() { return state.sidebarCollapsed; },
  };
}

if (applyFn && toggleFn) {
  const expanded = stageCollapse(false);
  expanded.apply(false);
  const expandedBoth = expanded.sidebar.dataset.collapsed === "false" &&
    expanded.app.dataset.collapsed === "false" &&
    expanded.btn.getAttribute("aria-expanded") === "true";
  if (expandedBoth) {
    ok("expanded: BOTH #sidebar and #app carry data-collapsed=false, and aria-expanded says true");
  } else {
    bad("expanded: both elements carry the flag and aria-expanded is true",
      "sidebar=" + expanded.sidebar.dataset.collapsed + " app=" + expanded.app.dataset.collapsed +
      " aria-expanded=" + expanded.btn.getAttribute("aria-expanded") +
      " - #app missing means the grid never drops to one column, so collapsing would shift the chat 256px right");
  }

  const collapsed = stageCollapse(true);
  collapsed.apply(true);
  const collapsedBoth = collapsed.sidebar.dataset.collapsed === "true" &&
    collapsed.app.dataset.collapsed === "true" &&
    collapsed.btn.getAttribute("aria-expanded") === "false" &&
    /Expand navigation/.test(collapsed.btn.getAttribute("aria-label") || "");
  if (collapsedBoth) {
    ok("collapsed: both elements carry data-collapsed=true, aria-expanded flips to false, and the verb follows");
  } else {
    bad("collapsed: both elements carry the flag and aria-expanded is false",
      "sidebar=" + collapsed.sidebar.dataset.collapsed + " app=" + collapsed.app.dataset.collapsed +
      " aria-expanded=" + collapsed.btn.getAttribute("aria-expanded") +
      " aria-label=" + collapsed.btn.getAttribute("aria-label"));
  }

  // The real path: toggleSidebar() flips the flag and commits, then calls the
  // shipped applySidebarCollapsed(). A harness that called apply() directly above
  // would never exercise the commit, and the commit is what makes the state
  // survive a reload - so this is the only place that half is checked.
  const t = stageCollapse(false);
  t.toggle();
  const afterToggle = t.sidebar.dataset.collapsed === "true" &&
    t.app.dataset.collapsed === "true" &&
    t.btn.getAttribute("aria-expanded") === "false" &&
    t.commits.join(",") === "perla_sidebar_collapsed=1";
  if (afterToggle) {
    ok("toggleSidebar() flips BOTH flags, tells the control, and commits the state for the next load");
  } else {
    bad("toggleSidebar() flips both flags and commits",
      "sidebar=" + t.sidebar.dataset.collapsed + " app=" + t.app.dataset.collapsed +
      " aria-expanded=" + t.btn.getAttribute("aria-expanded") +
      " commits=[" + t.commits.join(", ") + "]");
  }
  t.toggle();
  if (t.sidebar.dataset.collapsed === "false" && t.app.dataset.collapsed === "false" &&
      t.btn.getAttribute("aria-expanded") === "true" &&
      t.commits.join(",") === "perla_sidebar_collapsed=1,perla_sidebar_collapsed=0") {
    ok("toggling back round returns both flags, aria-expanded and the committed value together");
  } else {
    bad("toggling back round returns everything together",
      "sidebar=" + t.sidebar.dataset.collapsed + " app=" + t.app.dataset.collapsed +
      " aria-expanded=" + t.btn.getAttribute("aria-expanded") +
      " commits=[" + t.commits.join(", ") + "]");
  }

  // The two flags cannot DISAGREE, because one function writes both and it is
  // the only writer. Asking for it here is not belt-and-braces: a second writer
  // added later would leave both green while the grid and the sidebar disagreed
  // about the state, which is a layout nothing asserts.
  const one = (jsSrc.match(/dataset\.collapsed\s*=/g) || []).length;
  if (one === 2) {
    ok("exactly two `dataset.collapsed =` writes in the file, both inside applySidebarCollapsed");
  } else {
    bad("exactly two dataset.collapsed writes, both in applySidebarCollapsed",
      one + " found - a second writer is how the grid and the sidebar start disagreeing about the same state");
  }

  // -------------------------------------------------------------------------
  // FOCUS LEAVES THE SIDEBAR WHEN THE COLUMN COLLAPSES.
  //
  // The reported bug: pressing the collapse control did nothing. The control
  // lives INSIDE the sidebar, and the collapsed rail's keyboard arm is
  // `.sidebar[data-collapsed="true"]:focus-within:not(:has(.sidebar-menu-button
  // :focus-visible))` - so the button that was just pressed satisfied
  // `:focus-within`, the `:not()` passed because the collapse control is not a
  // `.sidebar-menu-button`, and the rail slid straight back out. Nothing about
  // the ATTRIBUTE was wrong: `data-collapsed` was true, and the rail was open.
  //
  // Why it has to be an EFFECT assertion. Every reading assertion above is
  // compatible with this bug - the arm is in the stylesheet and correct, the
  // toggle flips the flag correctly - so a test that reads sources could only
  // have said "the code looks right", which is what the code did. What is wrong
  // is a property of the two together, and the only way to hold them together is
  // to run the shipped toggle against the shipped tree and look at where the
  // focus ended up.
  //
  // Staged the way the bug happens: focus sits on #sidebarCollapse, the control
  // inside the sidebar, and the toggle is called once.
  // -------------------------------------------------------------------------
  if (!releaseFn) {
    // Already reported above, as a scan floor, where it is not shadowed by the
    // crash that removing the function causes. Nothing to add here: the effect
    // assertions cannot run against a function that does not exist, and saying so
    // twice would make one missing capability look like two findings.
  } else {
    // The whole premise, asserted: the focused element really IS inside the
    // sidebar before the toggle runs. Without it the assertion below would also
    // pass for a document where focus had never been in the sidebar at all -
    // which is a different situation with the same final answer, and would make
    // the fix look like it works by accident.
    const stage = stageCollapse(false);
    focusSinks.activeElement = stage.btn;
    const beforeInside = contains(stage.sidebar, focusSinks.activeElement);
    stage.toggle();
    const landed = focusSinks.activeElement;
    const afterInside = landed ? contains(stage.sidebar, landed) : false;
    if (beforeInside && !afterInside) {
      ok("collapsing moves focus OFF the sidebar - the control that was pressed is inside it, and the collapsed rail's :focus-within arm would otherwise re-open the column");
    } else {
      bad("collapsing moves focus off the sidebar",
        "focus was inside the sidebar before the toggle: " + beforeInside +
        ", and is still inside it after: " + afterInside +
        " - the rail opens on :focus-within for as long as the collapse control holds focus, so collapsing appears to do nothing until the user clicks elsewhere");
    }

    // WHERE it went, because "not in the sidebar" is satisfied by a dozen wrong
    // answers - body, the document, a random descendant. The transcript is the
    // region that took the space the sidebar gave up, it is not a text field (so
    // no on-screen keyboard is summoned on a phone by a gesture the user did not
    // ask for), and it is where a keyboard user's next Tab should start.
    if (landed && landed.tagName === "main" && landed.classes.has("page")) {
      ok("…and it lands on the transcript (<main class=\"page\">), not merely off the sidebar");
    } else {
      bad("collapsing lands focus on the transcript",
        "focus ended on " + (landed ? "<" + landed.tagName + ">" +
          (landed.attrs.id ? " id=" + landed.attrs.id : "") +
          (landed.classes.size ? " class=" + [...landed.classes].join(".") : "") : "nothing") +
        " - <main class=\"page\"> is the region that just took the sidebar's space");
    }

    // THE ASYMMETRY, and it is the half that is easy to get wrong in the other
    // direction. EXPANDING leaves focus alone: the user is reaching for the
    // collapse control in the rail, and that control is inside the sidebar, so
    // focus there is what opens the column - the same `:focus-within` arm, used
    // the way it was designed. Moving focus out on expand would mean pressing
    // the control in the rail collapsed the column again behind it.
    const back = stageCollapse(true);
    focusSinks.activeElement = back.btn;
    back.toggle();
    const stayedOnBtn = focusSinks.activeElement === back.btn;
    if (stayedOnBtn && back.sidebar.dataset.collapsed === "false") {
      ok("EXPANDING leaves focus on the control - the rail opens on focus within, which is how the rail is meant to be re-opened");
    } else {
      bad("expanding leaves focus on the control",
        "sidebar=" + back.sidebar.dataset.collapsed +
        " focus is on " + ((focusSinks.activeElement && (focusSinks.activeElement.attrs.id || focusSinks.activeElement.tagName)) || "nothing") +
        " - moving focus out on expand would leave the rail's own control unreachable by keyboard");
    }

    // FOCUS IS NOT STOLEN FROM OUTSIDE. The collapse gesture is reachable from
    // the sidebar, so in practice focus is inside - but the function has to be
    // safe if it is ever called with focus elsewhere, because a transcript that
    // steals the caret from a half-typed composer is worse than the bug it fixes.
    const outside = stageCollapse(false);
    const composer = query(outside.d, "#textInput");
    focusSinks.activeElement = composer;
    outside.toggle();
    if (composer && focusSinks.activeElement === composer) {
      ok("collapsing with focus OUTSIDE the sidebar does not steal it - the fix is scoped to focus it actually took");
    } else {
      bad("collapsing with focus outside the sidebar leaves it alone",
        "focus moved to " + ((focusSinks.activeElement && (focusSinks.activeElement.attrs.id || focusSinks.activeElement.tagName)) || "nothing") +
        " - the composer the user was typing into lost the caret");
    }

    // THE FALLBACK IS NOT DEAD CODE. With no <main> to land on, focus still has
    // to leave the sidebar, or the bug returns the moment that element is
    // renamed - which is the failure mode of a fix that is only as durable as
    // the query it depends on. <main> is removed from this document only; nothing
    // else is restaged.
    const noMain = stageCollapse(false);
    const mainEl = query(noMain.d, "main");
    if (mainEl && mainEl.parent) mainEl.parent.removeChild(mainEl);
    focusSinks.activeElement = noMain.btn;
    noMain.toggle();
    // The invariant, and not "did it focus something in particular": focus is not
    // inside the sidebar afterwards. Nothing focused satisfies it - the harness's
    // browser-faithful blur() leaves the document with no focused element, where
    // a browser would leave it on <body> - and both mean the same thing here,
    // which is that `:focus-within` can no longer match. Written as the
    // INVARIANT rather than as a second identity check so it cannot pass by
    // focusing a different element that happens not to be an ancestor.
    const stillInside = focusSinks.activeElement
      ? contains(noMain.sidebar, focusSinks.activeElement)
      : false;
    if (!stillInside) {
      ok("with no <main> to land on, collapsing still moves focus off the sidebar rather than silently doing nothing");
    } else {
      bad("with no <main> to land on, collapsing still moves focus off the sidebar",
        "focus is still on " +
          (focusSinks.activeElement.attrs.id || focusSinks.activeElement.tagName) +
        " - a conditional query must not be able to restore the bug it was added to fix");
    }
  }

  // -------------------------------------------------------------------------
  // THE HOVER LOCK - Item 4's actual cause, and its fix, RUN.
  //
  // WHY THIS BLOCK EXISTS AT ALL, because the block above it asserts the opposite
  // half of the same bug and passes: releaseSidebarFocus moved focus to <main> on
  // every staged collapse and :focus-within went false, which is correct and is
  // what ux-fix-3 fixed. The user's report was that collapsing still did not take
  // effect. Measured in Firefox 156 with real pointer input, the cause was the
  // OTHER arm: the pointer is still sitting on the sidebar when the control is
  // pressed, so `.sidebar[data-collapsed="true"]:hover` matched on the next
  // recalculation and the column slid straight back out. A reading harness could
  // have found it; an EFFECT harness is where it is provable, because the state
  // being asserted - "is the pointer over the rail" - is a state the reader has
  // to set.
  //
  // The parser's node carries `hoverState` and a listener registry for exactly
  // this. Both are documented at their definitions in nav_dom_test.js, and the
  // listener registry is a real one rather than a no-op: an assertion that could
  // pass with the shipped `pointerleave` never bound is not an assertion.
  //
  // FOUR claims, in the order they matter:
  //
  //   1. collapsing while the pointer IS over the rail arms the lock. Without it,
  //      the bug is unfixed and every other assertion here is describing a state
  //      that cannot happen.
  //   2. collapsing while the pointer is NOT over it - the keyboard case - does
  //      not arm it. A flag set there would never be cleared, because
  //      pointerleave does not fire for a pointer that was never inside, and the
  //      rail would then refuse to open on the next real hover. This is the half
  //      that is easy to get wrong by writing `if (sidebarCollapsed)` alone.
  //   3. the flag does not stop focus being released: the keyboard collapse still
  //      lands on <main>, so the two mechanisms do not fight.
  //   4. EXPANDING does not arm it, and does not clear it either - and both of
  //      those are deliberate, recorded at toggleSidebar. Asserted so a future
  //      edit that "tidies up" the asymmetry cannot do so silently.
  if (applyFn && toggleFn) {
    const hovered = stageCollapse(false);
    hovered.sidebar.hoverState = true;
    hovered.toggle();
    const lockedWhenHovered = hovered.sidebar.dataset.hoverSuppressed === "true";

    const unhovered = stageCollapse(false);
    unhovered.sidebar.hoverState = false;
    focusSinks.activeElement = unhovered.btn;
    unhovered.toggle();
    const lockedWhenNot = unhovered.sidebar.dataset.hoverSuppressed !== undefined;
    const focusStillReleased = focusSinks.activeElement !== null &&
      !contains(unhovered.sidebar, focusSinks.activeElement);

    if (lockedWhenHovered) {
      ok("collapsing with the pointer ON the rail arms data-hover-suppressed - the hover arm can no longer re-open the column under the cursor that just pressed the control");
    } else {
      bad("collapsing with the pointer on the rail arms the hover lock",
        "data-hover-suppressed is " + (hovered.sidebar.dataset.hoverSuppressed === undefined ? "absent" : hovered.sidebar.dataset.hoverSuppressed) +
        " - toggleSidebar only arms it when sidebar.matches(':hover'), and the sidebar was staged as hovered");
    }
    if (!lockedWhenNot && focusStillReleased) {
      ok("collapsing with the pointer ELSEWHERE does not arm it, and still moves focus off the sidebar - so the keyboard path is unaffected and cannot leave a flag nothing would clear");
    } else {
      bad("a keyboard collapse does not arm the hover lock",
        "flag " + (lockedWhenNot ? "SET anyway" : "absent") + "; focus still released: " + focusStillReleased +
        " - a flag armed with no pointer over the rail is never cleared, because pointerleave does not fire for a pointer that was never inside");
    }

    // THE CLEARER, and it is the shipped `clearHoverLock` compiled out of the
    // source and bound to the node - not a call to whatever the app happens to
    // have bound. That mirrors how this harness already treats
    // `applySidebarCollapsed`, which is also registered at top level and also
    // bound here rather than reached through its registration: a top-level
    // `addEventListener` call is not a function body to extract, so the harness
    // binds the extracted one and the READING half - that the subscription
    // exists at all, and carries this name - is pinned in nav_dom_test.js.
    // Between the two, a missing listener and a broken clearer are both red.
    const clearBody = fnBody("clearHoverLock");
    if (clearBody === null) {
      bad("clearHoverLock compiles out of the shipped source",
        "the only thing that removes the hover lock could not be extracted, so the clearing assertions below would be measuring nothing");
    } else {
      ok("clearHoverLock compiles out of the shipped source");
      const clearFn = new Function("state", `with (state) {\n${clearBody}\n}`);
      const clearing = stageCollapse(false);
      clearing.sidebar.hoverState = true;
      clearing.toggle();
      const armedBeforeLeave = clearing.sidebar.dataset.hoverSuppressed === "true";
      clearing.sidebar.hoverState = false;
      // Bound the way the shipped top-level line binds it.
      clearing.sidebar.addEventListener("pointerleave", () => clearFn(clearing));
      clearing.sidebar.__fire("pointerleave", { type: "pointerleave" });
      const clearedAfterLeave = clearing.sidebar.dataset.hoverSuppressed === undefined;
      // ...and the re-arm, because a lock that cleared and then could not be set
      // again would be a rail that opens once and never again. The pointer goes
      // back over the rail first - `hoverState = true` again - because that is
      // the state the re-collapse has to happen in, and without it the collapse
      // correctly declines to arm and this half would report the documented
      // asymmetry as a failure. Two toggles rather than one for the same reason:
      // the stage is already collapsed, so one toggle would expand.
      clearing.sidebar.hoverState = true;
      clearing.toggle();
      clearing.toggle();
      const rearmed = clearing.sidebar.dataset.hoverSuppressed === "true";
      if (armedBeforeLeave && clearedAfterLeave && rearmed) {
        ok("clearing the hover lock on pointerleave, and the next collapse re-arms it - the rail re-opens on the hover AFTER the pointer leaves and comes back, which is the condition the fix promises");
      } else {
        bad("the hover lock clears on pointerleave, and the next collapse re-arms it",
          "armed before the leave: " + armedBeforeLeave + "; cleared by it: " + clearedAfterLeave +
          "; re-armed by the next collapse: " + rearmed +
          " - a lock that never clears makes the rail permanently un-openable, and one that never re-arms makes it open on the first hover after a single collapse");
      }

      // EXPANDING: asserted as "does not arm", which is the half that matters,
      // and "does not clear an armed flag", which is the half that looks like a
      // leak and is not. The reason is at toggleSidebar: at full width the rail's
      // hover rules do not apply, and a collapse with the pointer still over the
      // sidebar re-arms the flag on its own. The stage therefore STARTS with the
      // flag set - which is the only way "expand did not clear it" is a question
      // with a non-trivial answer; starting from absent, "not cleared" and
      // "absent" are the same statement and the assertion would be vacuous.
      const expandPath = stageCollapse(true);
      expandPath.sidebar.hoverState = true;
      expandPath.sidebar.dataset.hoverSuppressed = "true";
      expandPath.toggle();
      const expandArmedAnother = expandPath.sidebar.dataset.hoverSuppressed === "true";
      const expandCleared = expandPath.sidebar.dataset.hoverSuppressed === undefined;
      // And the expand must not ARM one either, staged from absent this time -
      // because the previous stage could not have told those apart.
      const expandFresh = stageCollapse(true);
      expandFresh.sidebar.hoverState = true;
      expandFresh.toggle();
      const expandArmedFromNothing = expandFresh.sidebar.dataset.hoverSuppressed !== undefined;
      if (expandArmedAnother && !expandCleared && !expandArmedFromNothing) {
        ok("expanding neither arms nor clears data-hover-suppressed, deliberately - at full width the flag is inert, and the next collapse re-arms it if the pointer is still over the rail");
      } else {
        bad("expanding leaves data-hover-suppressed exactly as it found it",
          "an armed flag survived the expand: " + expandArmedAnother + "; it was cleared: " + expandCleared +
          "; a flag appeared from nothing: " + expandArmedFromNothing +
          " - arming on expand would suppress a hover that is not possible at full width, and clearing would be a second place the two halves of the flag could disagree");
      }
    }
  }

  // THE OVERLAY STACK DECISION, asserted rather than only documented: the hover
  // slide-out must not push. Nothing in the shipped source calls pushOverlay or
  // popOverlay from a hover or focus path, so pressing Escape while the rail is
  // open cannot consume it.
  //
  // This is a NEGATIVE assertion over the call sites of two names that appear in
  // three functions, so it is stated as precisely as the source allows: every
  // call site is inside the sheet's own open/close/park path. `openSidebarSheet`,
  // `closeSidebarSheet` and the Escape dispatcher's `closeTopOverlay` are the
  // three places the stack is ever touched, and none of them is reachable from a
  // hover.
  // WHICH FUNCTION each call site sits in, rather than how many there are.
  // A bare count cannot answer this: `pushOverlay(` also matches the definition,
  // and `popOverlay()` matches three unrelated things, so any threshold is one
  // refactor away from being wrong. `fnBody` already returns the shipped text of
  // a function; searching for its source span and asking which span CONTAINS
  // each call is the question that is actually load-bearing.
  // The span of `function NAME(…) { … }`, found by COUNTING braces from its opening
  // one. The previous version ended it at the first `\n    }`, which is a
  // first-match read of exactly the class this repo has been bitten by four times -
  // `rule_body`, the `.sidebar-rail` assertion, `Object.keys` on a Map, and the
  // reduced-motion needle. It happened to land on the right place for the four
  // functions that existed when it was written, which is what makes it dangerous:
  // a fifth function with a `}` at that indentation inside it, or a nested closure
  // indented four spaces, would have made every `ownerOf()` answer below name the
  // wrong function - and those answers are the whole of the overlay-stack
  // assertion. `withoutAtRuleBodies` and `mediaRange` in the sibling already count.
  function fnSpan(name) {
    const i = jsSrc.indexOf("function " + name + "(");
    if (i === -1) return null;
    let depth = 0, started = false;
    for (let j = jsSrc.indexOf("{", i); j < jsSrc.length; j++) {
      if (jsSrc[j] === "{") { depth++; started = true; }
      else if (jsSrc[j] === "}") { depth--; if (started && depth === 0) return [i, j]; }
    }
    return null;
  }
  function callSites(re) {
    const out = [];
    const r = new RegExp(re, "g");
    let m;
    while ((m = r.exec(jsSrc)) !== null) out.push(m.index);
    return out;
  }
  // `parkSidebarRows` and `applySidebarCollapsed` are here only so a call inside
  // either of them is NAMED rather than silently reported as top level.
  const owners = ["pushOverlay", "popOverlay", "closeTopOverlay", "openSidebarSheet",
    "closeSidebarSheet", "parkSidebarRows", "applySidebarCollapsed", "toggleSidebar"];
  const spans = {};
  for (const n of owners) spans[n] = fnSpan(n);
  function ownerOf(idx) {
    for (const n of owners) {
      const sp = spans[n];
      if (sp && idx > sp[0] && idx < sp[1]) return n;
    }
    // The Escape dispatcher is an anonymous arrow on a document listener, so it
    // has no name to look up - it is identified by the listener it is attached
    // to, and calling it anything but that would be inventing a name the source
    // does not have.
    return /addEventListener\("keydown"/.test(jsSrc.slice(Math.max(0, idx - 400), idx)) ? "the Escape dispatcher" : "<top level>";
  }
  // Definitions are `function NAME(`; a call site is anything else. Asked by
  // looking BACKWARDS at the text before the match, because a slice starting at
  // the match itself can never see the word `function`.
  const isDef = (i) => /function\s*$/.test(jsSrc.slice(Math.max(0, i - 12), i));
  const pushTouch = callSites("pushOverlay\\(").filter((i) => !isDef(i));
  const popTouch = callSites("(?:popOverlay|closeTopOverlay)\\(\\)").filter((i) => !isDef(i));
  const pushOwners = pushTouch.map(ownerOf);
  const popOwners = popTouch.map(ownerOf);
  // And no hover or focus handler anywhere reaches them: the rail's slide-out is
  // `:hover` / `:focus-within` in the STYLESHEET, so the script's part is simply
  // to have no pointer listener that could open a stack layer.
  //
  // THE CLAIM IS NOW ABOUT HANDLER BODIES, NOT EVENT NAMES, and the change is a
  // fix rather than a relaxation. The previous form was a bare regex over the file
  // asking whether ANY pointer event name was ever subscribed to, which is a proxy
  // for the real question rather than the question itself - and a pointer listener
  // exists that has nothing to do with the stack: toggleSidebar's `pointerleave`,
  // which deletes `data-hover-suppressed` so the collapsed rail re-arms when the
  // pointer leaves (Item 4's fix). Under the old regex that correct line made this
  // assertion red, and the two available responses were both wrong: deleting the
  // listener to make a test green, or widening the event list until the test
  // stopped seeing.
  //
  // What it now asks is the real thing: for every pointer/mouse subscription in the
  // file, does the HANDLER'S OWN BODY mention the stack? A handler that cannot name
  // pushOverlay/popOverlay/closeTopOverlay cannot put a layer on the stack or take
  // one off, whatever event it listens for.
  //
  // The handler body is found by counting parens from `addEventListener(` to the
  // call's closing one and then, if a `{` follows, counting braces from there -
  // the same technique `fnSpan` above uses, and for the same reason: a first-match
  // read of a closing token stops at the first one, which is usually not the end of
  // the thing being read.
  const STACK_NAMES = /pushOverlay|popOverlay|closeTopOverlay/;
  function handlerSpan(from) {
    let depth = 0;
    let i = jsSrc.indexOf("(", from);
    for (; i < jsSrc.length; i++) {
      if (jsSrc[i] === "(") depth++;
      else if (jsSrc[i] === ")") { depth--; if (depth === 0) break; }
    }
    if (i === jsSrc.length) return null;
    const after = jsSrc.slice(i + 1);
    const open = after.indexOf("{");
    // A `;` before any `{` means this is an expression, not a block - an inline
    // handler passed as an arrow without braces cannot contain a statement block
    // either, so there is nothing to read and nothing to check.
    const semi = after.indexOf(";");
    if (open === -1 || (semi !== -1 && semi < open)) return [i + 1, i + 1];
    let d = 0;
    for (let j = i + 1 + open; j < jsSrc.length; j++) {
      if (jsSrc[j] === "{") d++;
      else if (jsSrc[j] === "}") { d--; if (d === 0) return [i + 1, i + 1 + j]; }
    }
    return null;
  }
  const pointerHooks = [...jsSrc.matchAll(
    /addEventListener\(\s*"(?:mouseenter|mouseleave|mouseover|mouseout|mousemove|mousedown|mouseup|mousedrag|pointerenter|pointerleave|pointermove|pointerdown|pointerup)"/g)]
    .map((m) => m.index);
  // Each hook is reported with its event and what its body says, so a failure names
  // the subscription rather than just counting.
  const pointerHookDetail = pointerHooks.map((i) => {
    const sp = handlerSpan(i);
    const body = sp ? jsSrc.slice(sp[0], sp[1]) : "";
    const ev = /addEventListener\(\s*"([^"]+)"/.exec(jsSrc.slice(i, i + 60));
    return { ev: ev ? ev[1] : "?", touches: STACK_NAMES.test(body), body: body };
  });
  const pointerHook = pointerHookDetail.some((h) => h.touches);
  // ...and the count is part of the answer, so "there are no pointer listeners at
  // all" cannot pass this by being vacuously true about bodies that do not exist.
  const pointerHooksBounded = pointerHooks.length > 0;
  // The three pop paths, named: closeSidebarSheet's own body, closeTopOverlay's
  // body, and the Escape dispatcher. Every one of them is reachable only when the
  // user opened the SHEET.
  const popSorted = popOwners.slice().sort().join(",");
  if (pushOwners.join(",") === "openSidebarSheet" &&
      popSorted === "closeSidebarSheet,closeTopOverlay,the Escape dispatcher" &&
      pointerHooksBounded && !pointerHook) {
    ok("the stack is touched only by the sheet's own open/close path (push: " + pushOwners.join(", ") + "; pop: " + popOwners.join(", ") + ") - and none of the " +
       pointerHooks.length + " pointer subscriptions in the file (" +
       pointerHookDetail.map((h) => h.ev).join(", ") + ") names the stack in its body, so the hover slide-out never pushes it");
  } else {
    bad("the hover slide-out stays off the overlay stack",
      "push called from: [" + pushOwners.join(", ") + "]; pop/close called from: [" + popOwners.join(", ") +
      "]; pointer subscriptions: " + (pointerHooks.length || "none") +
      "; of those, the ones whose body names the stack: " +
      (pointerHookDetail.filter((h) => h.touches).map((h) => h.ev).join(", ") || "none"));
  }
} else {
  bad("applySidebarCollapsed and toggleSidebar compile out of the shipped source",
    "applySidebarCollapsed: " + (applyFn ? "ok" : "missing") +
    ", toggleSidebar: " + (toggleFn ? "ok" : "missing") +
    " - every result below would be untrustworthy");
}
// The DONE sentinel. Printed LAST, after every assertion, and it is the only
// thing the wrapper treats as proof this harness reached its end.
//
// A summary line is not that proof. `process.exit()` inside a REQUIRED module
// kills the requiring module too, so a harness that dies partway through - or one
// that is stubbed to print nothing - can leave the OTHER harness's assertions
// silently unrun while both processes still exit 0 and no FAIL line appears. The
// wrapper's at-least floor cannot see that either, because a crash after the last
// assertion has already printed every PASS line the floor counts. Only a line
// that cannot be reached without reaching the end can.
//
// The count travels WITH the sentinel so the wrapper never has to know how many
// assertions this file should have, and so "nav_focus_effect_test reported 74,
// expected 13" names the half that is wrong.
//
// THE COUNT IS ASSERTIONS RUN, not assertions PASSED - `pass + fail`. It used to
// print `pass`, which made the two questions the wrapper asks collapse into one
// and produced a misleading diagnosis: a single genuinely failing assertion
// dropped the count below the expected one, so the wrapper reported "a lost
// assertion, or a DOUBLE-RUN one" - naming two causes when the cause was neither.
// The real failure was already printed as its own FAIL line and counted as one;
// the count gate then re-reported it as a bookkeeping problem.
//
// `pass + fail` is what the gate is actually asking. How many assertions did this
// harness RUN? That is invariant under a legitimate failure and still catches both
// defects the gate exists for:
//   - a LOST assertion (deleted, or a harness that died before reaching it)
//   - a DOUBLE-RUN one (the split seam losing its `require.main` guard)
// so neither is given up to buy a cleaner diagnosis. The failure tally stays on
// its own line above, which is where a real failure is reported from.
console.log("");
console.log("  " + pass + " passed, " + fail + " failed");
console.log("DONE nav_focus_effect_test " + (pass + fail));
process.exit(fail === 0 ? 0 : 1);