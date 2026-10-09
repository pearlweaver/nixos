
    const CONFIG = {
      ENDPOINT: "https://nixos.fish-glyptodon.ts.net",           // Tailscale HTTPS address
      TEXT_PATH: "/api/text",
      VOICE_PATH: "/api/voice",
      QUESTION_PATH: "/api/question",
      PERMISSION_PATH: "/api/permission",
      INTERRUPT_PATH: "/api/interrupt",
      HEALTH_PATH: "/api/health",
      GATE_PATH: "/api/gate",
      HISTORY_DAYS_PATH: "/api/history/days",
      HISTORY_DAY_PATH: "/api/history/day",
      REMINDERS_PATH: "/api/reminders",
      QUICK_ACTION_PATH: "/api/quick-action",
      SCOPED_COMMAND_PATH: "/api/scoped-command",
      AVATAR_PATH: "/api/avatar",
      DRIVE_LIST_PATH: "/api/drive/list",
      DRIVE_MKDIR_PATH: "/api/drive/mkdir",
      DRIVE_DELETE_PATH: "/api/drive/delete",
      DRIVE_RESTORE_PATH: "/api/drive/restore",
      DRIVE_UPLOAD_PATH: "/api/drive/upload",
      DRIVE_DOWNLOAD_PATH: "/api/drive/download",
      DRIVE_VIEW_PATH: "/api/drive/view",
      DRIVE_COPY_PATH: "/api/drive/copy",
      DRIVE_MOVE_PATH: "/api/drive/move",
      DRIVE_ADD_TO_CHAT_PATH: "/api/drive/add-to-chat",
    };

    const GATE_PASSWORD = "goharumer"; // UX gate only — short, human-typeable

    let authToken = sessionStorage.getItem("perla_session_token") || null;

    // ---------- Custom avatar (profile.jpg) ----------
    // Unauthenticated probe — the server serves this without auth since a
    // profile picture isn't sensitive, and the browser's own favicon fetch
    // can't carry an Authorization header anyway. Falls back to the "P"
    // mark (already in the markup) if the file isn't there.
    (function loadAvatar() {
      if (!CONFIG.ENDPOINT) return;
      const avatarUrl = CONFIG.ENDPOINT + CONFIG.AVATAR_PATH;
      const probe = new Image();
      probe.onload = () => {
        document.querySelectorAll("#gateMark, #brandMark").forEach((mark) => {
          mark.textContent = "";
          const img = document.createElement("img");
          img.src = avatarUrl;
          img.alt = "Perla";
          mark.appendChild(img);
        });
        let favicon = document.querySelector('link[rel="icon"]');
        if (favicon) favicon.href = avatarUrl;
      };
      probe.onerror = () => {
        // No profile.jpg deployed yet — keep the default "P" mark and SVG
        // favicon already in the markup, no action needed.
      };
      probe.src = avatarUrl;
    })();

    // ---------- Tier state (separate Tier 1 / Tier 2 chats) ----------
    // Each tier keeps its own chat transcript. Stored in sessionStorage so a
    // reload within the same gate-unlock doesn't lose either conversation,
    // but a fresh gate unlock always starts clean at Tier 1 per spec.
    let activeTier = parseInt(sessionStorage.getItem("perla_active_tier") || "1", 10);
    // The tier the user was LAST using, which is what the Chat nav row returns
    // to. Recorded in switchTier and nowhere else, so there is one writer and no
    // second copy to drift; seeded from activeTier rather than a literal because
    // activeTier is RESTORED from sessionStorage, and setDestination("chat") runs
    // during initialisation (initAppState -> updateTierButtonHighlight). Seeded
    // with a literal 1, that call would find lastActiveTier disagreeing with
    // activeTier, miss switchTier's early-return exit, and commit Tier 1 over a
    // reload that had restored Tier 2. The two agree by construction until a
    // switch says otherwise, which is the point: they are the same fact, and this
    // one is the user's CHOICE rather than a derived piece of app state.
    let lastActiveTier = activeTier;
    let isElevated = sessionStorage.getItem("perla_elevated") === "1";
    let tier1Unread = sessionStorage.getItem("perla_tier1_unread") === "1";
    let tier2Unread = sessionStorage.getItem("perla_tier2_unread") === "1";

    // The typing indicator is transient UI and must never outlive the turn it
    // belongs to. It used to be captured into the saved transcript by every
    // setChatLog(output.innerHTML) call, so switching tiers mid-reply persisted a
    // stale indicator; switching back then painted it into the chat, and it came
    // back AFTER the message had already been sent. Stripped on both write and
    // read — the read side also repairs transcripts already saved with one.
    function stripThinking(html) {
      if (!html || html.indexOf("thinkingIndicator") === -1) return html;
      const tpl = document.createElement("template");
      tpl.innerHTML = html;
      tpl.content.querySelectorAll("#thinkingIndicator, .thinking").forEach((n) => n.remove());
      return tpl.innerHTML;
    }

    function getChatLog(tier) {
      return stripThinking(sessionStorage.getItem("perla_chat_t" + tier) || "");
    }

    function setChatLog(tier, html) {
      try {
        sessionStorage.setItem("perla_chat_t" + tier, stripThinking(html));
      } catch (e) {
        // sessionStorage quota exceeded or unavailable — chat still works
        // in-memory for this page view, just won't survive a reload.
      }
    }

    // Overlay view state (history / reminders share the main output area
    // as a read-only overlay on top of whichever tier's chat is active).
    // Declared here (not where first used) so addEntry, defined below, can
    // reference activeOverlay without relying on hoisting/call-order luck.
    let liveOutputHTML = null;
    let activeOverlay = null;  // "history" | "reminders" | "quick-actions" | "drive" | null

    // ---------- Overlay stack ----------
    // Escape walks this top-down, so the topmost layer closes first and exactly
    // one layer closes per press. There were two `document` keydown listeners -
    // one for the image editor / lightbox / file viewer and one for the
    // file-viewer modal - and because both ran on the same press, a single
    // Escape closed the lightbox AND the modal sitting behind it. Layer 9 pushes
    // its own layers here.
    let overlayStack = [];

    // Focus is captured on the way in and handed back on the way out. A modal
    // that opens without remembering where focus came from strands it on the
    // document, so closing it puts the caret at the top of the page.
    //
    // The `[hidden]` filter is load-bearing, not tidiness. openSidebarSheet hides
    // #sidebarCollapse (the FIRST focusable in the nodes it moves into the sheet)
    // BEFORE calling this, and a browser treats focus() on a display:none element
    // as a no-op. Focusing it anyway would leave focus OUTSIDE an element
    // carrying aria-modal="true": a screen reader has been told the rest of the
    // page is inert, focus is not in the dialog, and Tab walks into content the
    // user was told does not exist. querySelector finds hidden descendants happily;
    // only the filter knows they are not focusable. jsdom sets activeElement
    // regardless of visibility, so a jsdom harness reports this green either way -
    // which is exactly why the guard is asserted from source in nav_dom_test.js.
    function pushOverlay(el, onClose) {
      const prev = document.activeElement;
      overlayStack.push({ el: el, prev: prev, onClose: onClose });
      el.hidden = false;
      const first = Array.from(el.querySelectorAll(
        "button, [href], input, select, textarea, [tabindex]:not([tabindex='-1'])"))
        .find((n) => !n.closest("[hidden]"));
      if (first) first.focus();
    }

    function popOverlay() {
      const top = overlayStack.pop();
      if (!top) return false;
      if (top.onClose) top.onClose();
      if (top.el) top.el.hidden = true;
      if (top.prev && typeof top.prev.focus === "function") top.prev.focus();
      return true;
    }

    function closeTopOverlay() {
      return popOverlay();
    }

    // ---------- Gate ----------
    const gate = document.getElementById("gate");
    const app = document.getElementById("app");
    const gatePassword = document.getElementById("gatePassword");
    const gateSubmit = document.getElementById("gateSubmit");
    const gateError = document.getElementById("gateError");
    const gateCard = document.querySelector(".gate-card");

    // If we already have a session token, skip the gate — this is a reload
    // within the same gate-unlock, so restore whatever tier/chat state was
    // saved rather than resetting to Tier 1. The actual initAppState() call
    // happens at the end of the script, once all DOM refs below exist.
    if (authToken) {
      gate.style.display = "none";
      app.hidden = false;
    }

    function initAppState(freshUnlock) {
      if (freshUnlock) {
        // New gate session: always start at Tier 1, drop any elevation and
        // chat transcripts left over from a previous session.
        sessionStorage.removeItem("perla_chat_t1");
        sessionStorage.removeItem("perla_chat_t2");
        sessionStorage.removeItem("perla_draft_t1");
        sessionStorage.removeItem("perla_draft_t2");
        sessionStorage.removeItem("perla_elevate_until");
        sessionStorage.setItem("perla_active_tier", "1");
        sessionStorage.setItem("perla_elevated", "0");
        sessionStorage.setItem("perla_tier1_unread", "0");
        sessionStorage.setItem("perla_tier2_unread", "0");
        // lastActiveTier rides along: this reset is the app choosing Tier 1, and
        // updateTierButtonHighlight() two lines below reaches setDestination("chat")
        // -> switchTier(lastActiveTier). Leave lastActiveTier holding the value
        // activeTier had before this reset and that call commits the old tier over
        // the fresh unlock, which is the one thing a fresh unlock must not do.
        activeTier = lastActiveTier = 1;
        isElevated = false;
        tier1Unread = false;
        tier2Unread = false;
        if (typeof tierDrafts !== "undefined") {
          tierDrafts[1] = { text: "", attachQueue: [], textFileQueue: [] };
          tierDrafts[2] = { text: "", attachQueue: [], textFileQueue: [] };
        }
      }
      setElevated(isElevated);
      // No tierBadge.textContent here any more. It wrote the "T1"/"T2" pill
      // into #tierBadge, which the user asked to remove; the active tier is
      // still announced by the tier ROW's own .active highlight and by
      // aria-current on the Chat destination, both below.
      updateTierButtonHighlight();
      updateTier2UnreadBadge();
      const savedLog = getChatLog(activeTier);
      if (savedLog) {
        output.innerHTML = savedLog;
        // A reload that happens while a request is in flight can leave the
        // thinking indicator's markup as the last thing painted before the
        // tab closed — strip any stray copy so it doesn't reappear frozen
        // on the next load with no request actually pending.
        const staleThinking = output.querySelector("#thinkingIndicator");
        if (staleThinking) staleThinking.remove();
        output.querySelectorAll(".entry.meta-visible").forEach((el) => el.classList.remove("meta-visible"));
        // blob: URLs from a previous page load don't survive a reload —
        // swap any stale screenshot image for a plain notice instead of
        // showing a broken-image icon.
        output.querySelectorAll("img.entry-image").forEach((img) => {
          if (img.src.startsWith("blob:")) {
            const wrap = img.closest(".entry-image-wrap");
            if (wrap) wrap.innerHTML = '<span class="entry-image-error">Screenshot no longer available after reload.</span>';
          }
        });
        output.scrollIntoView({ block: "end" });
        notify("success", "Session restored", "Your previous conversation is loaded.");
      } else {
        showWelcome(activeTier);
      }
      if (typeof restoreTierDraft === "function") {
        restoreTierDraft(activeTier);
      }
    }

    async function tryUnlock() {
      const value = gatePassword.value;
      if (value.length === 0) return;

      // Client-side UX check first (fast fail, no network)
      if (value !== GATE_PASSWORD) {
        gateError.textContent = "Wrong password.";
        gateError.hidden = false;
        gateCard.classList.remove("shake");
        void gateCard.offsetWidth;
        gateCard.classList.add("shake");
        gatePassword.value = "";
        gatePassword.focus();
        return;
      }

      // Exchange gate password for a server-issued session token
      try {
        const res = await fetch(CONFIG.ENDPOINT + CONFIG.GATE_PATH, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ password: value }),
        });
        if (!res.ok) throw new Error("gate rejected");
        const data = await res.json();
        authToken = data.token;
        sessionStorage.setItem("perla_session_token", authToken);
        gate.style.display = "none";
        app.hidden = false;
        initAppState(true);
      } catch (e) {
        gateError.hidden = false;
        gateError.textContent = "Server rejected the password.";
        gateCard.classList.remove("shake");
        void gateCard.offsetWidth;
        gateCard.classList.add("shake");
        gatePassword.value = "";
        gatePassword.focus();
      }
    }

    gateSubmit.addEventListener("click", tryUnlock);
    gatePassword.addEventListener("keydown", (e) => {
      if (e.key === "Enter") tryUnlock();
    });

    // ---------- Status ----------
    //
    // #statusDot is GONE, at the user's request, and with it this whole block:
    // setStatusText, checkConnection and the two calls to it at unlock. The
    // reason they are deleted rather than left writing into nothing is that
    // every one of them existed ONLY to paint that dot - there is no second
    // consumer of the health result, so a surviving checkConnection() would be a
    // fetch whose answer is discarded, which is worse than no probe.
    //
    // WHAT IS LOST, stated plainly because it is a capability change rather than
    // a deletion of decoration: there is no longer an ambient "is the daemon
    // reachable" signal anywhere in the UI. What is NOT lost is the case that
    // actually matters - an unreachable daemon fails every send, and
    // sendTextTurn's retry path already raises a toast saying exactly that
    // ("Couldn't reach Perla. Check the connection."), as does the voice path.
    // So the failure is loud; only the standing green light is gone.
    //
    // A minimal non-pill surface was considered and rejected: the brief was to
    // remove the green dot and the T# pill, and inventing a replacement
    // indicator is new UI the user did not ask for.

    // ---------- Sidebar ----------
    // The shell's only navigation. #menuBtn and #appMenu are gone, and the eleven
    // closeAppMenu() call sites that went with them were found first: four rows
    // became DESTINATIONS, the tier switcher and the status line moved to the
    // footer, and Clear chat / Check session / Restart service became the Session
    // group. Nothing #appMenu could reach is unreachable now.
    const sidebar = document.getElementById("sidebar");
    const sidebarTrigger = document.getElementById("sidebarTrigger");
    const sidebarSheet = document.getElementById("sidebarSheet");
    const sidebarOverlay = document.getElementById("sidebarOverlay");
    let sidebarCollapsed = sessionStorage.getItem("perla_sidebar_collapsed") === "1";

    // Which nav row an open overlay means. activeOverlay is the OVERLAY's own
    // name and the nav row's key is the DESTINATION's, and the two spellings are
    // not the same word in one case (`quick-actions` vs `actions`) - which is
    // precisely the kind of near-miss that leaves a nav row stuck claiming
    // aria-current for a surface that is not on screen.
    const DESTINATION_FOR_OVERLAY = {
      history: "history",
      reminders: "reminders",
      drive: "drive",
      "quick-actions": "actions",
    };

    // The ONE writer of aria-current, across both presentations. A second writer
    // - one on click and one derived from state - is how the highlight starts
    // lying the first time a surface is opened by anything other than its own
    // nav row, so the click handlers below deliberately do not touch this
    // attribute. Layer 3 replaces the body of this switch with the frame swap.
    function setDestination(name) {
      document.querySelectorAll("[data-destination]").forEach((b) => {
        if (b.getAttribute("data-destination") === name) {
          b.setAttribute("aria-current", "page");
        } else {
          b.removeAttribute("aria-current");
        }
      });
      // Chat is the one destination with no surface of its own to open - the other
      // four rows each hand over to their overlay's open/close - so "go to Chat" is
      // "put back the tier the user was actually using", which is switchTier's job.
      // lastActiveTier, not a literal: arriving here from History while on Tier 2
      // and being dropped into Tier 1 would throw away the conversation they were
      // reading.
      //
      // LAST in the body, deliberately. switchTier re-enters this function through
      // updateTierButtonHighlight - twice, on the overlay path - and the loop above
      // is the ONE writer of aria-current, so it has to be the last thing to run
      // rather than something a re-entrant call can pre-empt. That is safe because
      // switchTier sees lastActiveTier still holding the OLD tier while it is
      // closing the overlay, so the nested call matches `wasSameTier && !hadOverlay`
      // and returns without doing anything.
      if (name === "chat") switchTier(lastActiveTier);
    }

    // The Chat row is the one destination row with nothing to open, which is
    // exactly why it had no handler: unlike Drive/History/Reminders/Quick Actions
    // there is no panel for it to hand over to. Bound here, beside the router it
    // routes through, and looked up by its data-destination like the other four -
    // so it also travels into #sidebarSheet on a phone and needs no second
    // binding there. Routing through setDestination rather than calling
    // switchTier directly keeps aria-current in one place, and leaves Layer 3 a
    // single place to swap frames.
    const chatBtn = sidebar.querySelector('[data-destination="chat"]');
    if (chatBtn) chatBtn.addEventListener("click", () => { setDestination("chat"); });

    // The ONE writer of the collapsed state, on BOTH elements that carry it, and
    // they have to be written together: `grid-template-columns` on #app is what
    // lets the content column keep the full viewport width once the rail leaves
    // the grid, and there is no selector that could derive one from the other
    // without :has(). Two elements, one function, so they cannot disagree.
    function applySidebarCollapsed() {
      if (!sidebar) return;
      const flag = String(sidebarCollapsed);
      sidebar.dataset.collapsed = flag;
      const app = document.getElementById("app");
      if (app) app.dataset.collapsed = flag;
      const btn = document.getElementById("sidebarCollapse");
      if (btn) {
        const verb = sidebarCollapsed ? "Expand" : "Collapse";
        btn.setAttribute("aria-label", verb + " navigation");
        btn.setAttribute("title", verb + " navigation");
        // aria-expanded tracks the PERSISTENT state and nothing else. The rail
        // also opens on hover and on :focus-within, and neither can be operated
        // from the keyboard, so promising "expanded" for a pointer gesture would
        // be a lie to a screen reader that had no way to act on it. This says the
        // one thing a keyboard user can actually change.
        btn.setAttribute("aria-expanded", String(!sidebarCollapsed));
      }
    }

    function toggleSidebar() {
      sidebarCollapsed = !sidebarCollapsed;
      sessionStorage.setItem("perla_sidebar_collapsed",
        sidebarCollapsed ? "1" : "0");
      // THE HOVER LOCK, set on the COLLAPSE direction and only then, and only
      // when the pointer is actually over the rail. It is Item 4's fix, and the
      // reason it lives here rather than in the focus half below is that focus was
      // never what was holding the column open - see releaseSidebarFocus's comment
      // and the measurement in ux-fix-5.
      //
      // WHAT WAS HAPPENING, measured in Firefox 156 with real pointer input
      // rather than inferred: pressing the collapse control flipped
      // data-collapsed, releaseSidebarFocus moved focus to <main> exactly as
      // designed (document.activeElement really was MAIN and
      // :focus-within really was false), and the column slid straight back out
      // anyway - because the pointer was still sitting on the sidebar, on the
      // control just pressed. `.sidebar[data-collapsed="true"]:hover` matched on
      // the next recalculation. The user is not asked to move the mouse to make a
      // button work.
      //
      // WHY data-hover-suppressed RATHER THAN A GRACE PERIOD. A timeout would have
      // to be guessed at (how long is long enough?), it would have to be cleared
      // when the user collapses twice, and it would still pop the column open
      // under a pointer that never moved - the original bug, just later. "The
      // pointer must LEAVE and come back" is the condition that actually matches
      // the intent, it needs no constant, and it is a state a test can assert.
      //
      // ONLY WHEN :hover, because the flag means "the pointer is on the rail and
      // must leave before it counts as a hover". Setting it on a keyboard collapse
      // with the pointer elsewhere would leave a stale flag with nothing to clear
      // it - no pointerleave ever fires for a pointer that was never inside - and
      // the rail would then refuse to open on the next real hover.
      //
      // ON EXPAND the flag is left alone rather than deleted: expanding puts the
      // column open at full width, where the rail's hover rules do not apply at
      // all, and if the pointer was still over the sidebar the next collapse will
      // re-arm it anyway. Deleting it here would only add a way for the two
      // halves to disagree.
      if (sidebarCollapsed && sidebar && sidebar.matches(":hover")) {
        sidebar.dataset.hoverSuppressed = "true";
      }
      applySidebarCollapsed();
      // Focus leaves on the COLLAPSE direction only, and the asymmetry is the
      // point rather than an oversight. Collapsing from inside the sidebar is the
      // only way to reach this, and the collapsed rail's `:focus-within` arm
      // opens the column for as long as anything inside it holds focus - so the
      // control just pressed is what kept the rail open. Expanding must NOT move
      // focus: the user is reaching for that same control in the rail, focus
      // inside the sidebar is precisely how the column re-opens, and a focus move
      // here would collapse the column behind the button they are holding.
      //
      // This is still load-bearing after the hover lock, and it is the KEYBOARD
      // half: a keyboard collapse has no pointer over the rail, so nothing sets
      // data-hover-suppressed, and the `:focus-within` arm would open the column
      // again on its own. Measured: with focus parked on #sidebarCollapse and the
      // flag absent, :focus-within is true and the column is open.
      if (sidebarCollapsed) releaseSidebarFocus();
    }

    // THE FLAG'S ONLY CLEARER. pointerleave - not pointerout, and not a timer -
    // because it is the event that means exactly the thing being waited for: the
    // pointer has left the sidebar and everything inside it. `pointerout` would
    // also fire when the pointer crosses from the rail onto one of its rows,
    // which is not leaving at all.
    //
    // A NAMED function rather than an inline arrow, for no reason that is about
    // this file's tests rather than about JavaScript: the effect harness compiles
    // shipped functions out of the source and runs them, and an inline handler at
    // top level is not a function it can extract, so the clearing would be the one
    // part of the fix nothing could exercise.
    function clearHoverLock() {
      if (sidebar) delete sidebar.dataset.hoverSuppressed;
    }

    // Bound ONCE, here. A listener added inside toggleSidebar would accumulate
    // one per press, and the second press's listener would go on clearing a flag
    // the first press had never set.
    if (sidebar) sidebar.addEventListener("pointerleave", clearHoverLock);

    // WHY FOCUS HAS TO LEAVE AT ALL, since `data-collapsed` was true throughout
    // and the rail was still open: the bug is not in the state, it is in the two
    // states being in the same place. `.sidebar[data-collapsed="true"]
    // :focus-within` matches while ANY descendant holds focus, and #sidebarCollapse
    // - inside the sidebar - is what a click or an Enter leaves focused. So the
    // press set the flag, the focus-within arm opened the column, and nothing
    // appeared to happen until the user clicked elsewhere.
    //
    // THE `:not(:has(.sidebar-menu-button:focus-visible))` THIS USED TO QUOTE has
    // been removed from the rule, and it is worth being precise about why that
    // does not undo the fix. The carve-out existed so that tabbing onto a ROW
    // would show that row's chip instead of opening the column - the chip is
    // retired, so the carve-out went with it, and focus on a row now opens the
    // column like everything else. But the collapse control was never a
    // `.sidebar-menu-button` and still is not, so the `:not()` never applied to it
    // in the first place: it saved the row case and never the button case. The
    // guard that mattered was always releaseSidebarFocus, and that is unchanged.
    //
    // THIS IS THE KEYBOARD HALF ONLY, and ux-fix-5 measured that the mouse half
    // had a second, independent cause: with a real pointer, the `:hover` arm
    // re-opened the column after this function had already done its job. Hence
    // data-hover-suppressed in toggleSidebar, which does not affect this path at
    // all - a keyboard collapse never sets it.
    //
    // THE TARGET IS THE TRANSCRIPT, and `blur()` was rejected for a reason worth
    // keeping: blurring drops focus on <body>, so the next Tab restarts at the top
    // of the document. A keyboard user who collapsed the nav would be thrown back
    // to the top-left, and Tab from there walks into the rail and re-opens it -
    // the fix would trade a stuck-open column for a lost place. <main
    // class="page"> is the region that just took the space the sidebar gave up,
    // it is not a text field so this cannot summon an on-screen keyboard on a
    // phone, and it is where forward navigation belongs. It carries
    // tabindex="-1" for exactly this: programmatically focusable, not a stop in
    // the Tab order.
    //
    // ONLY WHEN FOCUS IS ACTUALLY INSIDE. Reaching this function means the
    // control was used, so it normally is - but the guard is what stops a
    // transcript stealing the caret from a half-typed composer, and a caret is
    // worth more than the collapsed column.
    //
    // THE FALLBACK IS NOT DEFENSIVE PROGRAMMING, it is the invariant. If <main>
    // is renamed or removed and the only thing standing between a collapse and
    // the original bug is one querySelector, the bug comes back silently. So the
    // one job - focus is not inside the sidebar afterwards - does not depend on
    // the target existing.
    function releaseSidebarFocus() {
      const active = document.activeElement;
      if (!active || !active.closest(".sidebar")) return;
      const landing = document.querySelector("main");
      if (landing && typeof landing.focus === "function") landing.focus();
      else if (typeof active.blur === "function") active.blur();
    }

    // THE HOVER SLIDE-OUT IS NOT ON THE OVERLAY STACK, deliberately, and this
    // is where that decision is written down.
    //
    // pushOverlay/popOverlay exist to model a THING THE USER OPENED AND CAN CLOSE:
    // it takes focus, marks the layer aria-modal, and Escape pops the top of the
    // stack. The rail's hover slide-out is none of those. The user did not open
    // it - they moved a pointer across a strip of icons - and they cannot close
    // it with Escape any more than they opened it with the keyboard; the pointer
    // leaving does it. Putting it on the stack would mean every Escape press
    // consumed by something the user never asked for: a sheet open behind it
    // would have to be dismissed twice, and an Escape with an empty stack would
    // silently close the nav instead of doing nothing.
    //
    // :focus-within is the one case that DOES put focus inside the sidebar, and it
    // closes itself when focus leaves - which is the same thing Escape would have
    // done, reached the way a keyboard user reaches it. So the affordance is
    // intact and the stack stays clean.

    // Everything that has to change together when the sheet opens or closes, in
    // one routine because there are three callers - open, close, and Escape
    // through the stack - and they must never disagree about what is on screen.
    function syncSidebarSheetState(open) {
      if (sidebarTrigger) sidebarTrigger.setAttribute("aria-expanded", String(open));
      if (sidebarOverlay) sidebarOverlay.hidden = !open;
      // Collapse is a DESKTOP-rail control and the sheet shows the same nodes,
      // so without this the phone gets a rail-only button that silently remembers
      // a collapse for the next desktop load.
      const collapse = document.getElementById("sidebarCollapse");
      if (collapse) collapse.hidden = open;
    }

    // The sheet holds the sidebar's OWN nodes, moved in and back out - NOT a
    // clone, which is what this replaced. A clone (sidebarSheet.innerHTML =
    // sidebar.innerHTML) would duplicate every id in the sidebar: #tier1Btn,
    // #tier1Badge, #brandMark and the rest. On a phone the persistent
    // sidebar is display:none inside the grid, so document.getElementById would
    // keep resolving to the INVISIBLE copy and the sheet would show a tier badge
    // that never updates, and a collapse button with no click handler at all.
    // Moving keeps one element per id, one set of handlers, and therefore one
    // implementation rather than two.
    //
    // #tierBadge and #statusDot are named no longer, having been removed from
    // the markup; #tier1Badge and #tier2Badge are the same class of problem and
    // are still live, which is why they are named here instead.
    function parkSidebarRows() {
      if (sidebar && sidebarSheet) {
        while (sidebarSheet.firstChild) sidebar.appendChild(sidebarSheet.firstChild);
      }
      syncSidebarSheetState(false);
    }

    function openSidebarSheet() {
      if (!sidebarSheet || !sidebar) return;
      while (sidebar.firstChild) sidebarSheet.appendChild(sidebar.firstChild);
      syncSidebarSheetState(true);
      pushOverlay(sidebarSheet, parkSidebarRows);
    }

    function closeSidebarSheet() {
      // Everything - a chosen destination, the scrim, Escape - funnels through
      // the stack, so parkSidebarRows runs exactly once per open.
      popOverlay();
    }

    if (sidebarTrigger) {
      sidebarTrigger.addEventListener("click", () => {
        if (sidebarSheet && !sidebarSheet.hidden) closeSidebarSheet();
        else openSidebarSheet();
      });
    }
    if (sidebarOverlay) sidebarOverlay.addEventListener("click", closeSidebarSheet);

    // Choosing anything from the sheet dismisses it. Delegated on the DOCUMENT,
    // and that is load-bearing rather than tidy: the rows MOVE into #sidebarSheet
    // when it opens, so a listener bound to #sidebar would not see the click at
    // all - which is the entire interaction on a phone, and the reason the first
    // version of this bound to #sidebar and left the sheet open on every tap.
    // Delegated rather than per-row because one node has to work in two places.
    // The containment check keeps it to the nav: .sidebar-menu-button is also
    // what the tier rows use, so a bare class test would dismiss the sheet for
    // an unrelated control elsewhere on the page.
    document.addEventListener("click", (e) => {
      const row = e.target.closest(".sidebar-menu-button");
      if (!row) return;
      if ((sidebar && sidebar.contains(row)) ||
          (sidebarSheet && sidebarSheet.contains(row))) {
        closeSidebarSheet();
      }
    });

    const sidebarCollapse = document.getElementById("sidebarCollapse");
    if (sidebarCollapse) sidebarCollapse.addEventListener("click", toggleSidebar);

    // ---------- Elevation (Tier 2) ----------
    // Tier 2's chat is always viewable (including its history) whether or
    // not the session is currently elevated — only SENDING requires the
    // token. So instead of a separate "Full Mode" menu item + dropdown,
    // elevation lives inline: the composer footer itself swaps for a token
    // bar whenever Tier 2 is the active, on-screen chat and isn't elevated
    // yet, and swaps back to the normal composer the moment it is. See
    // updateComposerMode() below, called from switchTier/setElevated/the
    // overlay open+close functions — anywhere the three inputs to "which
    // footer, if any, should show" (activeTier, isElevated, activeOverlay)
    // can change.
    const elevateInput = document.getElementById("elevateInput");
    const elevateSubmit = document.getElementById("elevateSubmit");
    const elevateStatus = document.getElementById("elevateStatus");
    // #tierBadge and #statusIndicator are gone from the markup, and so are their
    // two consts here. Nothing else in this file read them: the only writers
    // were the "T" + tier writes and the one hidden toggle in
    // updateComposerMode, all of which are removed with them.

    elevateSubmit.addEventListener("click", async () => {
      const token = elevateInput.value.trim();
      if (!token) return;
      elevateStatus.textContent = "Activating…";
      try {
        const res = await fetch(CONFIG.ENDPOINT + "/api/elevate", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: "Bearer " + authToken,
          },
          body: JSON.stringify({ token }),
        });
        const data = await res.json();
        if (res.ok && data.tier === 2) {
          elevateStatus.textContent = "";
          elevateInput.value = "";
          setElevated(true);
          notify("success", "Full Mode activated for 5 minutes.");

          const until = Date.now() + (data.expires_in || 0) * 1000;
          sessionStorage.setItem("perla_elevate_until", String(until));

          // This timeout - not the deleted countdown - is what expires Full
          // Mode, and it is why removing the countdown changes nothing about the
          // elevation's lifetime. It re-locks Tier 2 and posts the notice.
          clearTimeout(window._elevateExpiryTimer);
          window._elevateExpiryTimer = setTimeout(() => {
            sessionStorage.removeItem("perla_elevate_until");
            setElevated(false);
            if (activeTier === 2) {
              notify("error", "Full Mode expired, Tier 2 is locked again.");
            } else {
              notify("error", "Full Mode expired.");
            }
          }, (data.expires_in || 0) * 1000);
        } else {
          if (res.status === 401) {
            relockSession();
            return;
          }
          elevateStatus.textContent = data.error || "Failed";
        }
      } catch (e) {
        elevateStatus.textContent = "Connection error";
      }
    });

    elevateInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") elevateSubmit.click();
    });

    // ---------- Output ----------
    const output = document.getElementById("output");

    // Touch devices have no :hover, so tapping a message toggles its meta
    // row (timestamp + play button) instead. Delegated on `output` so it
    // covers every entry, including ones restored from session storage or
    // history, without attaching a listener per bubble. A tap on the play
    // button itself shouldn't also toggle the row it just revealed.
    output.addEventListener("click", (e) => {
      if (e.target.closest(".replay-btn") || e.target.closest(".copy-btn") || e.target.closest(".entry-image")) return;
      const entry = e.target.closest(".entry");
      if (!entry || !output.contains(entry)) return;
      const wasVisible = entry.classList.contains("meta-visible");
      output.querySelectorAll(".entry.meta-visible").forEach((el) => {
        if (el !== entry) el.classList.remove("meta-visible");
      });
      entry.classList.toggle("meta-visible", !wasVisible);
    });

    // ---------- Markdown rendering ----------
    // Pure-function mini renderer for Perla's bubbles. Everything begins as
    // HTML-escaped text, so the only tags that can reach the DOM are the ones
    // these transforms emit — safe by construction, no sanitizer needed.
    // Fenced code blocks are hoisted first so inline rules never touch them.
    function renderMarkdown(text) {
      function esc(s) {
        return String(s)
          .replace(/&/g, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;")
          .replace(/"/g, "&quot;")
          .replace(/'/g, "&#39;");
      }

      // Inline transforms, applied only on already-escaped source text.
      //
      // Code spans are lifted out to placeholders BEFORE any other rule runs
      // and dropped back at the end. Doing it in-line instead (letting the
      // code rule emit <code> and carrying on) let every LATER rule rewrite
      // the text inside it, so `**not bold**` rendered as bold and
      // `[x](http://evil.com)` became a live link inside code. The placeholder
      // keys are built from a character that can't appear in escaped output
      // (\\x00), so no amount of user text can forge one.
      function inline(s) {
        const spans = [];
        s = s.replace(/(`+)([\s\S]*?[^`])\1(?!`)/g, (m, ticks, code) => {
          spans.push(code);
          return "\x00" + (spans.length - 1) + "\x00";
        });

        s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
        s = s.replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, "$1<em>$2</em>");
        s = s.replace(/(^|[^_])_([^_\n]+)_(?!_)/g, "$1<em>$2</em>");
        s = s.replace(/~~([^~]+)~~/g, "<del>$1</del>");
        s = s.replace(/!\[([^\]]*)\]\(((?:[^()]|\([^()]*\))*)\)/g, "$1");
        s = s.replace(/\[([^\]]+)\]\(((?:[^()]|\([^()]*\))*)\)/g, (m, label, url) => {
          if (/^[a-z][a-z0-9+.-]*:/i.test(url) && !/^(https?|mailto|tel):/i.test(url)) {
            return m; // render the raw text — never emit javascript:/data:/vbscript:/file: etc.
          }
          return '<a href="' + url + '" target="_blank" rel="noopener">' + label + "</a>";
        });

        return s.replace(/\x00(\d+)\x00/g, (m, i) => {
          // Only a placeholder this function actually wrote gets restored. A
          // stray NUL in the source (legal in JSON, so a model could emit one)
          // must not be able to forge an index and splice in a bogus <code>.
          const n = Number(i);
          if (n >= spans.length) return "";
          return "<code>" + spans[n] + "</code>";
        });
      }

      // Split a pipe-table row into trimmed cells. A leading and/or trailing
      // pipe is optional GFM, so an empty first or last cell from the edge is
      // dropped. "\|" is a literal pipe, not a cell break.
      function splitRow(row) {
        const cells = [];
        let cur = "";
        for (let k = 0; k < row.length; k++) {
          const ch = row[k];
          if (ch === "\\" && row[k + 1] === "|") {
            cur += "|";
            k++;
          } else if (ch === "|") {
            cells.push(cur);
            cur = "";
          } else {
            cur += ch;
          }
        }
        cells.push(cur);
        if (cells.length > 1 && cells[0].trim() === "") cells.shift();
        if (cells.length > 1 && cells[cells.length - 1].trim() === "") cells.pop();
        return cells.map((c) => c.trim());
      }

      // A delimiter row is the only thing that makes a piped line a table:
      // cells of dashes, each optionally colon-wrapped for alignment. Returns
      // the per-cell alignment, or null if this line is not a delimiter row.
      // Every cell must qualify — "a | b" is a header, not a delimiter.
      function delimiterRow(row) {
        if (row.indexOf("-") === -1 || row.indexOf("|") === -1) return null;
        const cells = splitRow(row);
        if (!cells.length) return null;
        const aligns = [];
        for (const c of cells) {
          const m = c.match(/^(:)?-{1,}(:)?$/);
          if (!m) return null;
          aligns.push(m[1] && m[2] ? "center" : m[2] ? "right" : "left");
        }
        return aligns;
      }

      function alignAttr(align) {
        return align && align !== "left" ? ' class="prose-align-' + align + '"' : "";
      }

      const lines = String(text).replace(/\r\n/g, "\n").split("\n");
      const out = [];
      let i = 0;

      // Opening fence for ``` or ~~~, with an optional info string. Returns
      // {marker, lang} or null. The closing fence must use the same marker
      // and be at least as long, per CommonMark.
      function openFence(line) {
        const m = line.match(/^\s{0,3}(`{3,}|~{3,})[ \t]*([^\s`]*)[^\n]*$/);
        if (!m) return null;
        return { marker: m[1][0].repeat(m[1].length), lang: m[2] || "" };
      }

      function closesFence(line, marker) {
        const m = line.match(/^\s{0,3}(`{3,}|~{3,})[ \t]*$/);
        return !!m && m[1][0].repeat(m[1].length).charAt(0) === marker.charAt(0)
          && m[1].length >= marker.length;
      }

      // Code is content, never markup: escape it and hand back a <pre> with
      // inline() deliberately NOT applied, so nothing inside can become bold,
      // a link, or anything else.
      function codeBlock(body) {
        return '<pre class="scroll-area"><code>' + esc(body) + "</code></pre>";
      }

      while (i < lines.length) {
        const line = lines[i];

        const fence = openFence(line);
        if (fence) {
          const buf = [];
          i++;
          while (i < lines.length && !closesFence(lines[i], fence.marker)) {
            buf.push(lines[i]);
            i++;
          }
          i++; // consume the closing fence (or run off the end on an unclosed one)
          out.push(codeBlock(buf.join("\n")));
          continue;
        }

        // 4-space (or one-tab) indented code block — the other standard way to
        // mark up code. Without this these lines fell through to the paragraph
        // branch and their markdown was rendered as formatting.
        if (/^(?: {4}|\t)/.test(line) && line.trim() !== "") {
          const buf = [];
          while (i < lines.length && (/^(?: {4}|\t)/.test(lines[i]) || lines[i].trim() === "")) {
            // A blank line only continues the block if more indented code
            // follows; otherwise it ends the block (CommonMark).
            if (lines[i].trim() === "") {
              let j = i;
              while (j < lines.length && lines[j].trim() === "") j++;
              if (j >= lines.length || !/^(?: {4}|\t)/.test(lines[j])) break;
              for (let b = i; b < j; b++) buf.push("");
              i = j;
              continue;
            }
            buf.push(lines[i].replace(/^(?: {4}|\t)/, ""));
            i++;
          }
          out.push(codeBlock(buf.join("\n")));
          continue;
        }

        const heading = line.match(/^(#{1,4})\s+(.*)$/);
        if (heading) {
          const level = heading[1].length;
          out.push("<h" + level + ">" + inline(esc(heading[2])) + "</h" + level + ">");
          i++;
          continue;
        }

        const quote = line.match(/^>\s?/);
        if (quote) {
          const buf = [];
          while (i < lines.length && /^>\s?/.test(lines[i])) {
            buf.push(lines[i].replace(/^>\s?/, ""));
            i++;
          }
          out.push("<blockquote>" + inline(esc(buf.join(" "))) + "</blockquote>");
          continue;
        }

        const ordered = /^\d+[.)]\s/.test(line);
        if (ordered || /^[-*+]\s/.test(line)) {
          const items = [];
          while (i < lines.length && (/^\d+[.)]\s/.test(lines[i]) || /^[-*+]\s/.test(lines[i]))) {
            const item = lines[i].replace(/^(?:[-*+]|\d+[.)])\s/, "");
            items.push("<li>" + inline(esc(item)) + "</li>");
            i++;
          }
          out.push((ordered ? "<ol>" : "<ul>") + items.join("") + (ordered ? "</ol>" : "</ul>"));
          continue;
        }

        // GFM pipe table: a header row whose next line is a delimiter row
        // (cells of dashes, optionally colon-aligned). Sits after the fence
        // and indented-code branches above, so a table inside a code block is
        // already consumed as code by the time this runs.
        const delim = i + 1 < lines.length ? delimiterRow(lines[i + 1]) : null;
        if (delim && line.indexOf("|") !== -1) {
          const aligns = splitRow(lines[i]).map((_, idx) => delim[idx] || "left");
          const heads = splitRow(lines[i]);
          let html = '<div class="prose-table-wrap"><table class="prose-table"><thead><tr>';
          heads.forEach((h, idx) => {
            html += "<th" + alignAttr(aligns[idx]) + ">" + inline(esc(h)) + "</th>";
          });
          html += "</tr></thead><tbody>";
          i += 2; // consume the header and the delimiter row
          while (i < lines.length && lines[i].trim() !== "" && lines[i].indexOf("|") !== -1 && !openFence(lines[i])) {
            const cells = splitRow(lines[i]);
            html += "<tr>";
            heads.forEach((_, idx) => {
              html += "<td" + alignAttr(aligns[idx]) + ">" + inline(esc(cells[idx] || "")) + "</td>";
            });
            html += "</tr>";
            i++;
          }
          html += "</tbody></table></div>";
          out.push(html);
          continue;
        }

        if (/^-{3,}$/.test(line) || /^\*{3,}$/.test(line)) {
          out.push("<hr>");
          i++;
          continue;
        }

        if (line.trim() === "") {
          i++;
          continue;
        }

        const buf = [];
        while (
          i < lines.length &&
          lines[i].trim() !== "" &&
          !openFence(lines[i]) &&
          !/^(?: {4}|\t)/.test(lines[i]) &&
          !/^(#{1,4})\s/.test(lines[i]) &&
          !/^>\s?/.test(lines[i]) &&
          !/^\d+[.)]\s/.test(lines[i]) &&
          !/^[-*+]\s/.test(lines[i]) &&
          !/^-{3,}$/.test(lines[i]) &&
          !(delimiterRow(lines[i]) && lines[i - 1] !== undefined && lines[i - 1].indexOf("|") !== -1)
        ) {
          buf.push(lines[i]);
          i++;
        }
        out.push("<p>" + inline(esc(buf.join(" "))) + "</p>");
      }

      return out.join("");
    }

    // ---- Delivering entries to a specific tier's chat, live or backgrounded ----
    // A response belongs to whichever tier the request was SENT from, not
    // whatever the user happens to be looking at when it arrives — someone
    // can send in Tier 2, flip to Tier 1 (or open History/Reminders) before
    // the reply comes back, and the reply must land in Tier 2's transcript
    // either way: painted live if they're still looking at it, or saved
    // silently into that tier's stored log (plus an unread badge) if not.
    //
    // A detached scratch element mirrors the exact DOM shape `output` would
    // have gotten, so building an entry doesn't need two code paths — the
    // caller always gets back the real, live `<div class="entry ...">` node
    // (for addCopyButton/addReplayButton to attach to), and afterwards it's
    // either already in the live page or copied into storage as HTML.
    const backgroundScratch = document.createElement("div");

    function isViewingTierChat(tier) {
      return activeOverlay === null && activeTier === tier;
    }

    // Appends `entry` to the right place for `forTier`: live `output` if
    // that tier's plain chat is on screen, otherwise a detached scratch pad
    // that gets folded into that tier's saved chat log instead. Returns
    // whether it went live, so callers can skip live-only side effects
    // (scrolling into view, playing audio) when it didn't.
    function deliverEntry(entry, forTier) {
      if (isViewingTierChat(forTier)) {
        output.appendChild(entry);
        setChatLog(forTier, output.innerHTML);
        return true;
      }
      backgroundScratch.innerHTML = "";
      backgroundScratch.appendChild(entry);
      const existing = getChatLog(forTier);
      setChatLog(forTier, existing + backgroundScratch.innerHTML);
      markTierUnread(forTier);
      return false;
    }

    function addEntry(kind, label, text, forTier) {
      const targetTier = forTier !== undefined ? forTier : activeTier;
      const live = isViewingTierChat(targetTier);
      // A real exchange replaces the welcome card — only meaningful when
      // landing live, since a backgrounded reply's welcome card (if any)
      // lives inside the stored HTML string, not in a queryable DOM.
      //
      // The "system" exemption is now vestigial: every call site passes
      // "perla" or "user", and the .entry-system rules were removed with it
      // (app-scope notices moved to the notify() toasts long ago — see the
      // Global notifications section). Left in place because it is a cheap
      // guard, but note there is NO .entry-system styling left, so passing
      // "system" would now render an unstyled bubble.
      if (kind !== "system" && live) {
        output.querySelectorAll(".welcome").forEach((w) => w.remove());
      }
      const entry = document.createElement("div");
      entry.className = "entry entry-" + kind;
      const time = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
      const useMd = kind.startsWith("perla");
      entry.innerHTML =
        `<div class="entry-bubble">` + (useMd ? `<div class="prose"></div>` : `<p></p>`) + `</div>` +
        (kind !== "system" ? `<div class="entry-meta"><span class="entry-time">${time}</span></div>` : "");
      if (useMd) {
        const mdEl = entry.querySelector(".prose");
        mdEl.innerHTML = renderMarkdown(text);
        attachCodeBlockCopyButtons(mdEl);
      } else {
        entry.querySelector("p").textContent = text;
      }
      if (kind === "perla") addCopyButton(entry, text);
      const wentLive = deliverEntry(entry, targetTier);
      if (wentLive) {
        output.scrollIntoView({ block: "end" });
        entry.scrollIntoView({ behavior: "smooth", block: "end" });
      }
      return entry;
    }

    // Renders the server's "About to execute a potentially destructive
    // action. Confirm?" reply as an actual bubble with Confirm/Reject
    // buttons, instead of the dead end it used to be (data.confirm_required
    // was never read client-side, so the prompt just sat there with no way
    // to answer it). Confirm re-POSTs `originalMessage` with confirm:true
    // through the exact same /api/text path submitText already uses;
    // Reject just disables the buttons and leaves a note. Only ever
    // rendered live for the tier that's currently on screen — a
    // confirmation prompt has no meaning to leave "backgrounded" the way
    // a normal reply does, since it's blocking that specific pending action.
    function addConfirmationEntry(promptText, originalMessage, forTier) {
      const targetTier = forTier !== undefined ? forTier : activeTier;
      if (!isViewingTierChat(targetTier)) {
        // The user navigated away before the confirmation prompt came
        // back — surface it as a notification instead of silently
        // dropping it, since there's no natural "unread" home for a
        // prompt that needs an action, not just a read.
        notify("error", "A destructive action needs confirmation", promptText);
        markTierUnread(targetTier);
        return;
      }
      output.querySelectorAll(".welcome").forEach((w) => w.remove());

      const entry = document.createElement("div");
      entry.className = "entry entry-perla";
      const time = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

      const bubble = document.createElement("div");
      bubble.className = "entry-bubble";
      const p = document.createElement("p");
      p.textContent = promptText;
      bubble.appendChild(p);

      const actions = document.createElement("div");
      actions.style.display = "flex";
      actions.style.gap = "8px";
      actions.style.marginTop = "10px";

      const confirmBtn = document.createElement("button");
      confirmBtn.textContent = "Confirm";
      confirmBtn.className = "btn btn-md btn-destructive";
      confirmBtn.style.padding = "7px 14px";
      confirmBtn.style.fontSize = "0.78rem";

      const rejectBtn = document.createElement("button");
      rejectBtn.textContent = "Reject";
      rejectBtn.className = "qa-input-cancel";
      rejectBtn.style.padding = "7px 14px";

      confirmBtn.addEventListener("click", async () => {
        confirmBtn.disabled = true;
        rejectBtn.disabled = true;
        confirmBtn.textContent = "Confirming…";
        // Re-sending starts a fresh turn — give it the same in-flight Stop
        // control the original send had.
        const removeStop = addStopButton(entry, targetTier);
        showThinking(targetTier);
        try {
          const res = await fetch(CONFIG.ENDPOINT + CONFIG.TEXT_PATH, {
            method: "POST",
            headers: { "Content-Type": "application/json", Authorization: "Bearer " + authToken },
            body: JSON.stringify({ message: originalMessage, tier: targetTier, confirm: true }),
          });
          const data = await res.json();
          if (!res.ok) {
            if (res.status === 401) { relockSession(); return; }
            throw new Error(data.error || "request failed");
          }
          p.textContent = promptText;
          actions.remove();
          const note = document.createElement("div");
          note.style.marginTop = "6px";
          note.style.fontSize = "12px";
          note.style.color = "var(--accent-foreground)";
          note.style.fontStyle = "italic";
          note.textContent = "Confirmed.";
          bubble.appendChild(note);

          // A confirm re-send can itself hit a permission prompt or a
          // question, so route all three shapes rather than assuming a reply.
          if (data.question_required) {
            addQuestionEntry(data, targetTier);
          } else if (data.permission_required) {
            addPermissionEntry(data, targetTier);
          } else {
            renderReplyResult(data, targetTier);
          }
        } catch (e) {
          notify("error", "Couldn't confirm — try again.");
          confirmBtn.disabled = false;
          rejectBtn.disabled = false;
          confirmBtn.textContent = "Confirm";
        } finally {
          hideThinking(targetTier);
          removeStop();
        }
      });

      rejectBtn.addEventListener("click", () => {
        confirmBtn.disabled = true;
        rejectBtn.disabled = true;
        actions.remove();
        const note = document.createElement("div");
        note.style.marginTop = "6px";
        note.style.fontSize = "12px";
        note.style.color = "var(--accent-foreground)";
        note.style.fontStyle = "italic";
        note.textContent = "Rejected — nothing was run.";
        bubble.appendChild(note);
      });

      actions.appendChild(confirmBtn);
      actions.appendChild(rejectBtn);
      bubble.appendChild(actions);
      entry.appendChild(bubble);

      const meta = document.createElement("div");
      meta.className = "entry-meta";
      meta.innerHTML = `<span class="entry-time">${time}</span>`;
      entry.appendChild(meta);

      output.appendChild(entry);
      setChatLog(targetTier, output.innerHTML);
      output.scrollIntoView({ block: "end" });
      entry.scrollIntoView({ behavior: "smooth", block: "end" });
      return entry;
    }

    // Renders a final assistant reply payload (the shape every reply-path
    // endpoint returns) as either an image bubble, a sent-file bubble, or a
    // plain text bubble with optional TTS audio. Shared by submitText /
    // sendVoiceDraft and the /api/question answering flow so the question
    // round-trip's resolution renders identically to a normal reply.
    // Renders a finished turn's reply. This is the ONE place every completed
    // turn ends up (plain text, question round-trips, voice, drive), so it's
    // also where the in-flight Stop button gets taken back off the message.
    function renderReplyResult(data, requestTier) {
      clearStopButton(requestTier);
      if (data.image) {
        return addImageEntry("Perla", data.image, data.text || "", requestTier);
      }
      if (data.file) {
        return addSentFileEntry(data.file, data.text || "", requestTier);
      }
      const entry = addEntry("perla", "Perla", data.text || "(no response)", requestTier);
      if (data.audio && isViewingTierChat(requestTier)) {
        playAudio(data.audio);
        addReplayButton(entry, data.audio);
      }
      return entry;
    }

    // ---------------------------------------------------------------------
    // Question schema helpers.
    //
    // OpenCode's question payload declares two OPTIONAL flags
    // (@opencode-ai/sdk types.gen.d.ts, QuestionInfo):
    //     multiple?: boolean   "Allow selecting multiple choices"
    //     custom?:   boolean   "Allow typing a custom answer (default: true)"
    // Perla used to read NEITHER: every question was multi-select and every
    // question got a free-text box, so a question the model meant as one-of-three
    // could be answered with three ticks and the UI gave no hint that was wrong.
    //
    // `multiple` defaults to FALSE (absent means the model did not ask for
    // multi-select). `custom` defaults to TRUE — the schema says so explicitly —
    // so only an explicit `false` hides the input.
    // ---------------------------------------------------------------------
    function questionAllowsMultiple(q) {
      return !!(q && q.multiple === true);
    }

    function questionAllowsCustom(q) {
      return !(q && q.custom === false);
    }

    // The wire shape is Array<Array<string>> — one inner array per question, in
    // order — and must not change: the daemon forwards it verbatim to
    // /question/{id}/reply. Typed text is appended to its own question's answer,
    // and an unanswered question yields [] rather than a missing entry.
    function collectQuestionAnswers(groups) {
      return groups.map((g) => {
        const picked = Array.from(g._selected);
        const typed = (g._custom && g._custom.value || "").trim();
        if (typed) picked.push(typed);
        return picked;
      });
    }

    // Coerce a permission scope to a list rather than trusting its shape. The
    // SDK types permission metadata as { [key: string]: unknown }, and the
    // daemon's `or []` only catches a FALSY value, not a string — so a
    // single-string `directories` reached .join() and threw. That exception
    // escapes before the card is appended, so the prompt never renders and the
    // tool stays parked until the 900s turn timeout: exactly the hang this card
    // exists to prevent.
    function permissionScopeList(v) {
      if (v == null) return [];
      return Array.isArray(v) ? v : [v];
    }

    // Renders an interactive question card for the model's opencode `question`
    // tool payload. One question is shown at a time with Next/Back stepping
    // through them, honouring each question's `multiple` and `custom` flags
    // (see the helpers above). Typed text is appended to that question's
    // answers. Answering POSTs to /api/question; Skip rejects instead. The
    // daemon keeps the message turn open across round-trips: if answering
    // produces ANOTHER question, the card is re-rendered in place with the new
    // request_id; if it produces the final reply, that is rendered exactly as
    // a normal Perla reply. Cards are deduped by request_id (the daemon
    // surfaces the same pending question to every message sent while it's
    // unanswered, and the client must not stack spares).
    function addQuestionEntry(payload, forTier) {
      const targetTier = forTier !== undefined ? forTier : activeTier;
      const requestId = payload.request_id;
      if (requestId) {
        const existing = document.querySelector('[data-q-request="' + CSS.escape(requestId) + '"]');
        if (existing) {
          // Already showing this exact question — the duplicate came from a
          // second message sent while the first was still unanswered.
          if (isViewingTierChat(targetTier)) {
            output.scrollIntoView({ block: "end" });
            existing.scrollIntoView({ behavior: "smooth", block: "end" });
          }
          return existing;
        }
      }
      if (!isViewingTierChat(targetTier)) {
        const firstText = payload.questions && payload.questions[0] &&
          (payload.questions[0].question || payload.questions[0].text);
        notify("error", "Perla has a question for you", firstText || "check the chat");
        markTierUnread(targetTier);
        return null;
      }
      output.querySelectorAll(".welcome").forEach((w) => w.remove());

      const entry = document.createElement("div");
      entry.className = "entry entry-perla entry-question";
      if (requestId) entry.dataset.qRequest = requestId;
      const time = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

      const bubble = document.createElement("div");
      bubble.className = "entry-bubble";

      const card = document.createElement("div");
      card.className = "qac";

      const questions = Array.isArray(payload.questions) ? payload.questions : [];
      // Which question is on screen. One at a time, Next/Back steps through.
      let currentIndex = 0;

      const progress = document.createElement("div");
      progress.className = "qac-progress";

      // No class: this wrapper was created as .qac-stage and never had a rule,
      // so the class was a hook nothing read. It works as a plain block
      // container inside the question card. If the card later needs to style
      // this region, give it a rule then - as part of the .qac-* migration,
      // where the card's whole class set is decided at once.
      const stage = document.createElement("div");

      const actions = document.createElement("div");
      actions.className = "qac-actions";

      const backBtn = document.createElement("button");
      backBtn.type = "button";
      backBtn.className = "btn btn-sm";
      backBtn.textContent = "Back";

      const nextBtn = document.createElement("button");
      nextBtn.type = "button";
      nextBtn.className = "btn btn-sm btn-solid";
      nextBtn.textContent = "Next";

      const dismissBtn = document.createElement("button");
      dismissBtn.type = "button";
      dismissBtn.className = "btn btn-sm";
      dismissBtn.textContent = "Skip";

      const spacer = document.createElement("div");
      spacer.className = "qac-spacer";

      const statusNote = document.createElement("div");
      statusNote.className = "qac-status";

      // Per-question answer state, kept across Next/Back so stepping back and
      // forward does not lose what was already picked.
      const answers = questions.map(() => []);
      const typed = questions.map(() => "");

      // Rebuilds the visible question from state. Cheap and idempotent, which is
      // what makes Back safe: there is no separate "restore" path to get wrong.
      function renderStage() {
        const q = questions[currentIndex];
        stage.textContent = "";
        if (!q) return;

        if (q.header) {
          const hdr = document.createElement("div");
          hdr.className = "qac-progress";
          hdr.textContent = q.header;
          stage.appendChild(hdr);
        }

        const title = document.createElement("div");
        title.className = "qac-title";
        title.textContent = q.question || q.text || ("Question " + (currentIndex + 1));
        stage.appendChild(title);

        if (q.description) {
          const sub = document.createElement("div");
          sub.className = "qac-sub";
          sub.textContent = q.description;
          stage.appendChild(sub);
        }

        const multiple = questionAllowsMultiple(q);
        const allowCustom = questionAllowsCustom(q);
        const name = "qac-" + currentIndex + "-" + Math.random().toString(36).slice(2, 8);
        const options = Array.isArray(q.options) ? q.options : [];

        if (options.length) {
          const wrap = document.createElement("div");
          wrap.className = "qac-options";
          options.forEach((opt) => {
            const label = (opt && opt.label) || "";
            if (!label) return;

            const row = document.createElement("label");
            row.className = "qac-option";

            const input = document.createElement("input");
            input.type = multiple ? "checkbox" : "radio";
            input.name = name;
            input.className = multiple ? "checkbox" : "radio";
            input.checked = answers[currentIndex].indexOf(label) !== -1;
            if (input.checked) row.classList.add("is-selected");
            input.addEventListener("change", () => {
              if (multiple) {
                const at = answers[currentIndex].indexOf(label);
                if (input.checked && at === -1) answers[currentIndex].push(label);
                if (!input.checked && at !== -1) answers[currentIndex].splice(at, 1);
              } else {
                answers[currentIndex] = [label];
              }
              // Re-sync EVERY row from its own input state, not just this one.
              // In single-select the browser unchecks the previous radio
              // natively, but `change` fires only on the newly-checked input —
              // so toggling just this row left the previously selected option
              // wearing the selected border with an empty radio beside it.
              // Deriving the class from `checked` cannot drift from the input.
              wrap.querySelectorAll(".qac-option").forEach((r) => {
                r.classList.toggle("is-selected", r.querySelector("input").checked);
              });
              statusNote.textContent = "";
              syncNav();
            });

            const text = document.createElement("span");
            text.className = "qac-text";
            const nameEl = document.createElement("span");
            nameEl.className = "qac-label";
            nameEl.textContent = label;
            text.appendChild(nameEl);
            if (opt && opt.description) {
              const desc = document.createElement("span");
              desc.className = "qac-desc";
              desc.textContent = opt.description;
              text.appendChild(desc);
            }

            row.appendChild(input);
            row.appendChild(text);
            wrap.appendChild(row);
          });
          stage.appendChild(wrap);
        }

        // `custom: false` means the model closed this question to typed answers.
        if (allowCustom) {
          const custom = document.createElement("input");
          custom.type = "text";
          custom.className = "qac-custom";
          custom.placeholder = "Or type your own answer…";
          custom.value = typed[currentIndex];
          custom.addEventListener("input", () => {
            typed[currentIndex] = custom.value;
            statusNote.textContent = "";
            syncNav();
          });
          stage.appendChild(custom);
        }
      }

      // Next is only enabled once the visible question has something in it, so
      // the "pick something" message is a backstop rather than the main guard.
      function currentAnswered() {
        return answers[currentIndex].length > 0 || typed[currentIndex].trim() !== "";
      }

      function syncNav() {
        const last = currentIndex >= questions.length - 1;
        progress.textContent = questions.length > 1
          ? "Question " + (currentIndex + 1) + " of " + questions.length
          : "";
        backBtn.disabled = currentIndex === 0;
        nextBtn.disabled = !currentAnswered();
        nextBtn.textContent = last ? "Answer" : "Next";
      }

      function goTo(index) {
        currentIndex = Math.max(0, Math.min(index, questions.length - 1));
        renderStage();
        syncNav();
        statusNote.textContent = "";
      }

      backBtn.addEventListener("click", () => goTo(currentIndex - 1));
      nextBtn.addEventListener("click", () => {
        if (currentIndex < questions.length - 1) {
          goTo(currentIndex + 1);
          return;
        }
        answerAll();
      });

      // The wire format is unchanged: Array<Array<string>>. The groups are
      // assembled from the same per-question state the old Set held.
      function answerAll() {
        const unanswered = questions
          .map((q, i) => (answers[i].length > 0 || typed[i].trim() !== "" ? null : i))
          .filter((i) => i !== null);
        if (unanswered.length) {
          statusNote.textContent = "Pick an option (or type an answer) for question " +
            (unanswered[0] + 1) + ".";
          goTo(unanswered[0]);
          return;
        }
        const groups = questions.map((q, i) => ({
          _selected: new Set(answers[i]),
          _custom: { value: typed[i] },
        }));
        const payloadAnswers = collectQuestionAnswers(groups);

        disableButtons();
        nextBtn.textContent = "Answering…";
        showThinking(targetTier);
        submitAnswer({ tier: targetTier, request_id: requestId, answers: payloadAnswers })
          .then(({ res, d }) => {
            if (res.status === 401) { relockSession(); return; }
            if (!res.ok) throw new Error("answer rejected");
            entry.remove();
            if (d.question_required) {
              addQuestionEntry(d, targetTier);
            } else {
              renderReplyResult(d, targetTier);
            }
          })
          .catch(() => {
            notify("error", "Couldn't send your answer — try again.");
            rearmAnswer();
          })
          .finally(() => hideThinking(targetTier));
      }

      function rearmAnswer() {
        backBtn.disabled = currentIndex === 0;
        dismissBtn.disabled = false;
        nextBtn.disabled = !currentAnswered();
        nextBtn.textContent = currentIndex >= questions.length - 1 ? "Answer" : "Next";
      }

      function disableButtons() {
        backBtn.disabled = true;
        nextBtn.disabled = true;
        dismissBtn.disabled = true;
      }

      function submitAnswer(payloadToSend) {
        return fetch(CONFIG.ENDPOINT + CONFIG.QUESTION_PATH, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + authToken },
          body: JSON.stringify(payloadToSend),
        }).then((res) => res.json().then((d) => ({ res, d })));
      }

      dismissBtn.addEventListener("click", () => {
        disableButtons();
        dismissBtn.textContent = "Skipping…";
        showThinking(targetTier);
        submitAnswer({ tier: targetTier, request_id: requestId, dismiss: true })
          .then(({ res, d }) => {
            if (res.status === 401) { relockSession(); return; }
            if (!res.ok) throw new Error("dismiss rejected");
            entry.remove();
            if (d.question_required) {
              addQuestionEntry(d, targetTier);
              return;
            }
            renderReplyResult(d, targetTier);
          })
          .catch(() => {
            notify("error", "Couldn't skip — try again.");
            rearmAnswer();
            dismissBtn.textContent = "Skip";
          })
          .finally(() => hideThinking(targetTier));
      });

      actions.appendChild(backBtn);
      actions.appendChild(nextBtn);
      actions.appendChild(spacer);
      actions.appendChild(dismissBtn);

      card.appendChild(progress);
      card.appendChild(stage);
      card.appendChild(actions);
      card.appendChild(statusNote);
      bubble.appendChild(card);

      goTo(0);

      entry.appendChild(bubble);

      const meta = document.createElement("div");
      meta.className = "entry-meta";
      meta.innerHTML = `<span class="entry-time">${time}</span>`;
      entry.appendChild(meta);

      output.appendChild(entry);
      setChatLog(targetTier, output.innerHTML);
      output.scrollIntoView({ block: "end" });
      entry.scrollIntoView({ behavior: "smooth", block: "end" });
        return entry;
      }

      // Renders an OpenCode permission prompt as a card with the same three
    // choices the opencode TUI offers. These appear when a tool wants to act
    // outside the session's working directory (most often writing to /tmp) —
    // headless `opencode serve` has no UI to answer them, so the tool parks
    // forever and the turn hangs until the daemon's timeout. Surfacing them
    // here is what keeps the user in control instead of just blocked.
    //
    // Answering POSTs to /api/permission, which unblocks the tool and then
    // holds the request open until the turn's real reply lands — so the same
    // helper that renders a question card renders this one.
    function addPermissionEntry(payload, forTier) {
      const targetTier = forTier !== undefined ? forTier : activeTier;
      const requestId = payload.request_id;
      if (requestId) {
        const existing = document.querySelector('[data-perm-request="' + CSS.escape(requestId) + '"]');
        if (existing) return existing;
      }
      if (!isViewingTierChat(targetTier)) {
        notify("error", "Perla needs your approval to continue", "check the chat");
        markTierUnread(targetTier);
        return null;
      }
      output.querySelectorAll(".welcome").forEach((w) => w.remove());

      const entry = document.createElement("div");
      entry.className = "entry entry-perla entry-permission";
      if (requestId) entry.dataset.permRequest = requestId;
      const time = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

      const bubble = document.createElement("div");
      bubble.className = "entry-bubble";

      // Same .qac container as the question card, so the two read as one
      // surface rather than two designs that happen to share a chat.
      const card = document.createElement("div");
      card.className = "qac";

      const heading = document.createElement("div");
      heading.className = "qac-title";
      heading.textContent = "Permission needed";

      // The exact command is the thing being approved — show it verbatim so
      // the choice is informed rather than a blind trust click.
      const dirs = permissionScopeList(payload.directories).join(", ");
      const patterns = permissionScopeList(payload.patterns).join(", ");
      const scope = dirs || patterns || "";
      const detail = document.createElement("div");
      detail.className = "qac-sub";
      detail.textContent = payload.permission === "external_directory"
        ? "Wants to use " + (scope || "a path outside the working directory")
        : "Needs approval: " + (payload.permission || "unknown action");

      const statusNote = document.createElement("div");
      statusNote.className = "qac-status";

      const actions = document.createElement("div");
      actions.className = "qac-actions";

      const onceBtn = document.createElement("button");
      onceBtn.type = "button";
      onceBtn.className = "btn btn-sm btn-solid";
      onceBtn.textContent = "Allow once";

      const alwaysBtn = document.createElement("button");
      alwaysBtn.type = "button";
      alwaysBtn.className = "btn btn-sm";
      alwaysBtn.textContent = "Always allow";
      alwaysBtn.title = "Remember this choice for " + (scope || "this path");

      // Destructive, but flat: the token carries the signal, with no gradient or
      // glow. It should read as "don't" without looking like another product.
      const rejectBtn = document.createElement("button");
      rejectBtn.type = "button";
      rejectBtn.className = "btn btn-sm btn-destructive-flat";
      rejectBtn.textContent = "Reject";

      function disableAll() {
        onceBtn.disabled = true;
        alwaysBtn.disabled = true;
        rejectBtn.disabled = true;
      }

      function rearm(label) {
        onceBtn.disabled = false;
        onceBtn.textContent = "Allow once";
        if (label) statusNote.textContent = label;
      }

      function submitPermission(reply) {
        // A reject is forwarded with an explanatory message: OpenCode hands
        // it to the model, which then acknowledges in its own voice instead
        // of the turn ending on a bare "(no response)". Without it the user
        // just sees silence after choosing Reject, which reads as a bug.
        const body = { tier: targetTier, request_id: requestId, reply: reply };
        if (reply === "reject") {
          body.message = "The user rejected this action. Do not retry it. " +
            "Acknowledge briefly and move on.";
        }
        return fetch(CONFIG.ENDPOINT + CONFIG.PERMISSION_PATH, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + authToken },
          body: JSON.stringify(body),
        }).then((res) => res.json().then((d) => ({ res, d })));
      }

      // Shared by all three buttons: POST the answer, then render whatever
      // comes back — the turn's final reply, or another prompt if the model
      // hits another one right after.
      async function answer(reply, label) {
        disableAll();
        onceBtn.textContent = label + "…";
        try {
          const { res, d } = await submitPermission(reply);
          if (res.status === 401) { relockSession(); return; }
          if (!res.ok) {
            notify("error", (d && d.error) || "Couldn't send that decision.");
            rearm();
            return;
          }
          entry.remove();
          if (d.question_required) {
            addQuestionEntry(d, targetTier);
          } else if (d.permission_required) {
            addPermissionEntry(d, targetTier);
          } else {
            renderReplyResult(d, targetTier);
          }
        } catch (e) {
          notify("error", "Couldn't send that decision — try again.");
          rearm();
        }
      }

      onceBtn.addEventListener("click", () => answer("once", "Allowing"));
      alwaysBtn.addEventListener("click", () => answer("always", "Allowing"));
      rejectBtn.addEventListener("click", () => answer("reject", "Rejecting"));

      actions.appendChild(onceBtn);
      actions.appendChild(alwaysBtn);
      actions.appendChild(rejectBtn);

      card.appendChild(heading);
      card.appendChild(detail);
      if (payload.command) {
        const cmd = document.createElement("div");
        cmd.className = "qac-command";
        cmd.textContent = payload.command;
        card.appendChild(cmd);
      }
      card.appendChild(actions);
      card.appendChild(statusNote);
      bubble.appendChild(card);
      entry.appendChild(bubble);

      const meta = document.createElement("div");
      meta.className = "entry-meta";
      meta.innerHTML = `<span class="entry-time">${time}</span>`;
      entry.appendChild(meta);

      output.appendChild(entry);
      setChatLog(targetTier, output.innerHTML);
      output.scrollIntoView({ block: "end" });
      entry.scrollIntoView({ behavior: "smooth", block: "end" });
      return entry;
    }

    // Builds and delivers ONE user turn: an attachments block (file chips
    // and/or an image grid) as its OWN element ABOVE the message bubble —
    // not nested inside it — followed by the bubble holding just the typed
    // text, matching how Claude's UI separates attachments from the
    // message body. `textFiles` is [{filename, dataUrl}], `images` is
    // [{filename, dataUrl}] (both from the composer queues); either/both
    // may be empty as long as `message` or at least one attachment is
    // present. Sent attachments never get a remove button (see
    // buildFileChip) — only the composer's pending queue does.
    function addUserMessageEntry(message, images, textFiles, forTier) {
      const targetTier = forTier !== undefined ? forTier : activeTier;
      const live = isViewingTierChat(targetTier);
      if (live) {
        output.querySelectorAll(".welcome").forEach((w) => w.remove());
      }

      const entry = document.createElement("div");
      entry.className = "entry entry-user";
      const time = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

      // Attachments (file chips, images) render as their OWN element above
      // the message bubble — not nested inside its background — same
      // pattern as Claude's UI. Only created when there's actually
      // something to attach; a text-only message skips this entirely.
      if ((textFiles && textFiles.length) || (images && images.length)) {
        const attachments = document.createElement("div");
        attachments.className = "entry-attachments";

        if (textFiles && textFiles.length) {
          const row = document.createElement("div");
          row.className = "attach-file-row";
          textFiles.forEach((item) => {
            // Only plain text/code files can be decoded back to real
            // content client-side (their dataUrl IS the original text,
            // base64-wrapped). Document formats (PDF/DOCX/etc) are binary
            // at this layer — their extracted text only exists
            // server-side and isn't returned in the API response, so the
            // viewer will show its "content wasn't saved" fallback for
            // those until that's separately plumbed through.
            const ext = textFileExtension(item.filename);
            const content = TEXT_FILE_EXTENSIONS.has(ext)
              ? decodeDataUrlAsText(item.dataUrl)
              : null;
            row.appendChild(buildFileChip(item.filename, null, content, item.size));
          });
          // The images row is appended AFTER this one, then moved to the top
          // below — images above the other files.
          attachments.appendChild(row);
        }

        if (images && images.length) {
          // YOUR images keep their thumbnails. Flattening them into file rows
          // removed the image bar entirely and made a picture you just sent
          // indistinguishable from a document. Perla's own sent files stay
          // rows (buildDeliveredFileRow) — that is a different thing: a file she
          // handed back to you, not something you attached.
          const row = document.createElement("div");
          row.className = "attach-file-row attach-image-row";
          images.forEach((item) => {
            const card = buildImageCard(item, { onClick: () => openLightbox(item.dataUrl) });
            card.querySelector("img").classList.add("entry-image");
            row.appendChild(card);
          });
          // Images above the other files.
          attachments.insertBefore(row, attachments.firstChild);
        }

        entry.appendChild(attachments);
      }

      // The bubble now holds ONLY the text — if there's no typed message
      // (an attachment-only send), skip the bubble entirely so an empty
      // pink box doesn't render under the attachment for nothing.
      if (message) {
        const bubble = document.createElement("div");
        bubble.className = "entry-bubble";
        const p = document.createElement("p");
        p.textContent = message;
        bubble.appendChild(p);
        entry.appendChild(bubble);
      }

      const meta = document.createElement("div");
      meta.className = "entry-meta";
      meta.innerHTML = `<span class="entry-time">${time}</span>`;
      entry.appendChild(meta);

      // Stamped BEFORE delivery, because deliverEntry() persists this entry's
      // innerHTML into the tier's chat log. The id is what lets a failed send
      // be re-wired with a live Retry button when the chat is restored from
      // that log (switching tiers re-reads it) — the failure state itself
      // lives in failedSends, keyed by this id, and never touches the markup.
      entry.dataset.turnId = "t" + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);

      const wentLive = deliverEntry(entry, targetTier);
      if (wentLive) {
        output.scrollIntoView({ block: "end" });
        entry.scrollIntoView({ behavior: "smooth", block: "end" });
      }
      return entry;
    }

    // Screenshot images require an authenticated fetch (same as audio) since
    // the endpoint is gated — a bare <img src> can't carry the bearer token.
    // Renders as its own bubble, with the caption text (if any) above it.
    async function addImageEntry(label, imageUrl, captionText, forTier) {
      const targetTier = forTier !== undefined ? forTier : activeTier;
      const entry = document.createElement("div");
      entry.className = "entry entry-perla";
      const time = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
      entry.innerHTML =
        `<div class="entry-bubble">` +
        (captionText ? `<p></p>` : "") +
        `<div class="entry-image-wrap"><span class="empty entry-image-loading">Loading screenshot…</span></div>` +
        `</div>` +
        `<div class="entry-meta"><span class="entry-time">${time}</span></div>`;
      if (captionText) entry.querySelector("p").textContent = captionText;
      if (captionText) addCopyButton(entry, captionText);

      const wentLiveEarly = isViewingTierChat(targetTier);
      if (wentLiveEarly) {
        // Still the right tab right now — show the loading placeholder live
        // and let it pop in as the fetch resolves, same as before.
        output.appendChild(entry);
        output.scrollIntoView({ block: "end" });
        entry.scrollIntoView({ behavior: "smooth", block: "end" });
      }
      // If it's NOT the live tab, deliberately skip appending anywhere yet —
      // deliverEntry() below only ever serializes a node's CURRENT innerHTML
      // into sessionStorage, so appending the placeholder now and mutating
      // it after the fetch would freeze "Loading screenshot…" into storage
      // forever (the mutation happens on a node that's already been copied
      // out as a string). Resolving the image first means whichever branch
      // delivers this entry always delivers the final state.

      const wrap = entry.querySelector(".entry-image-wrap");
      try {
        const url = imageUrl.startsWith("http") ? imageUrl : CONFIG.ENDPOINT + imageUrl;
        const res = await fetch(url, { headers: { Authorization: "Bearer " + authToken } });
        if (!res.ok) throw new Error("image fetch failed");
        const blob = await res.blob();
        const objectUrl = URL.createObjectURL(blob);
        wrap.innerHTML = "";
        const img = document.createElement("img");
        img.className = "entry-image";
        img.src = objectUrl;
        img.alt = "Screenshot";
        img.addEventListener("click", () => openLightbox(objectUrl));
        wrap.appendChild(img);
      } catch (e) {
        wrap.innerHTML = `<span class="entry-image-error">Couldn't load the screenshot.</span>`;
      }

      if (wentLiveEarly) {
        // Entry is already live in the DOM (and may have moved tabs again
        // while the fetch was in flight) — just persist whatever tab it's
        // actually sitting in right now.
        if (isViewingTierChat(targetTier)) {
          setChatLog(targetTier, output.innerHTML);
        } else {
          // The user navigated away mid-fetch: the placeholder is still
          // live in `output` under the OLD view, not under targetTier's
          // storage. Move the resolved node's markup into targetTier's
          // stored log and remove it from the live page so it doesn't
          // linger under the wrong tab.
          entry.remove();
          backgroundScratch.innerHTML = "";
          backgroundScratch.appendChild(entry);
          setChatLog(targetTier, getChatLog(targetTier) + backgroundScratch.innerHTML);
          markTierUnread(targetTier);
        }
      } else {
        // Was never live — a blob: object URL only works for the page that
        // created it anyway (same caveat the reload path already handles
        // via the stale-blob cleanup in initAppState), so a background
        // delivery that resolved to a real image still gets its markup
        // saved, and will show the same "no longer available" fallback as
        // any other blob URL would once the user actually switches to it
        // and the objectUrl is inspected. This matches existing behavior
        // rather than inventing a new persistence story for screenshots.
        deliverEntry(entry, targetTier);
      }
      return entry;
    }

    // Sent-file entries: a downloadable file chip (reusing the same
    // buildFileChip used for uploads), with the caption text (if any)
    // above it. Unlike addImageEntry, there's nothing to fetch/preview
    // here up front — the download itself happens on click via an
    // authenticated fetch + blob URL, same auth pattern as screenshot/
    // audio, since the endpoint requires a bearer token a bare <a href>
    // can't carry.
    function addSentFileEntry(fileInfo, captionText, forTier) {
      const targetTier = forTier !== undefined ? forTier : activeTier;
      const entry = document.createElement("div");
      entry.className = "entry entry-perla";
      const time = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

      if (captionText) {
        const bubble = document.createElement("div");
        bubble.className = "entry-bubble";
        const p = document.createElement("p");
        p.textContent = captionText;
        bubble.appendChild(p);
        entry.appendChild(bubble);
      }

      const attachments = document.createElement("div");
      attachments.className = "entry-attachments";
      const row = document.createElement("div");
      row.className = "attach-file-row";
        // View on click, download on its own control — clicking used to
        // download straight away, so there was no way to see what was sent.
        row.appendChild(buildDeliveredFileRow(fileInfo));
      attachments.appendChild(row);
      entry.appendChild(attachments);

      const meta = document.createElement("div");
      meta.className = "entry-meta";
      meta.innerHTML = `<span class="entry-time">${time}</span>`;
      entry.appendChild(meta);
      if (captionText) addCopyButton(entry, captionText);

      const wentLive = deliverEntry(entry, targetTier);
      if (wentLive) {
        output.scrollIntoView({ block: "end" });
        entry.scrollIntoView({ behavior: "smooth", block: "end" });
      }
      return entry;
    }


    // A DELIVERED file row: click opens the viewer, download is a separate
    // control on the right.
    //
    // Clicking used to download straight away, which meant there was no way to
    // look at what Perla sent before saving it. Now the row fetches the bytes
    // once and hands them to the same viewer the composer uses; the download
    // button reuses that fetch rather than pulling the file a second time.
    function buildDeliveredFileRow(fileInfo) {
      // No delivered-state class: the delivered row is styled by the plain
      // .attach-file-chip rules, and .attach-file-chip-queued is what a row
      // escapes by NOT having. A "delivered" class that no rule ever matched
      // was a hook nothing read.
      const row = buildFileChip(fileInfo.filename, null, null, null);

      // Download is its own button so the row itself can mean "view".
      const dl = document.createElement("button");
      dl.className = "attach-file-download";
      dl.setAttribute("aria-label", "Download " + (fileInfo.filename || "file"));
      dl.title = "Download";
      dl.innerHTML = '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" width="13" height="13"><path d="M11 3v11"/><polyline points="6.5 10 11 14.5 15.5 10"/><path d="M4 18h14"/></svg>';
      row.appendChild(dl);

      let cached = null;   // { text, url } so view and download share one fetch
      async function load() {
        if (cached) return cached;
        const url = fileInfo.url.startsWith("http") ? fileInfo.url : CONFIG.ENDPOINT + fileInfo.url;
        const res = await fetch(url, { headers: { Authorization: "Bearer " + authToken } });
        if (!res.ok) throw new Error("file fetch failed");
        const blob = await res.blob();
        const objectUrl = URL.createObjectURL(blob);
        // Text-ish formats decode so the viewer can show them; anything else
        // (PDF, images, binaries) is binary at this layer and the viewer
        // already has a "content wasn't saved" path for that.
        let text = null;
        if (TEXT_FILE_EXTENSIONS.has(textFileExtension(fileInfo.filename))) {
          try { text = await blob.text(); } catch (e) { text = null; }
        }
        cached = { text, url: objectUrl, filename: fileInfo.filename };
        return cached;
      }

      row.addEventListener("click", async (e) => {
        if (e.target.closest(".attach-file-download")) return;
        row.classList.add("is-loading");
        try {
          const got = await load();
          openFileViewer(got.filename, got.text);
        } catch (err) {
          notify("error", "Couldn't open " + (fileInfo.filename || "that file") + ".");
        } finally {
          row.classList.remove("is-loading");
        }
      });

      dl.addEventListener("click", async (e) => {
        e.stopPropagation();
        dl.disabled = true;
        try {
          const got = await load();
          const a = document.createElement("a");
          a.href = got.url;
          a.download = got.filename || "file";
          document.body.appendChild(a);
          a.click();
          a.remove();
        } catch (err) {
          notify("error", "Couldn't download " + (fileInfo.filename || "that file") + ".");
        } finally {
          dl.disabled = false;
        }
      });

      return row;
    }


    // ---------- Image lightbox (pan + zoom + download) ----------
    const lightbox = document.getElementById("lightbox");
    const lightboxWrap = document.getElementById("lightboxWrap");
    const lightboxInner = document.getElementById("lightboxInner");
    const lightboxImage = document.getElementById("lightboxImage");
    const lightboxClose = document.getElementById("lightboxClose");
    const lightboxZoomIn = document.getElementById("lightboxZoomIn");
    const lightboxZoomOut = document.getElementById("lightboxZoomOut");
    const lightboxZoomReset = document.getElementById("lightboxZoomReset");
    const lightboxZoomLabel = document.getElementById("lightboxZoomLabel");
    const lightboxDownload = document.getElementById("lightboxDownload");

    const LIGHTBOX_MIN_ZOOM = 0.25;
    const LIGHTBOX_MAX_ZOOM = 8;
    let lightboxFitScale = 1;
    let lightboxZoomLevel = 1;
    let lightboxPanX = 0;
    let lightboxPanY = 0;
    let lightboxPanDrag = null;   // {startX, startY, startPanX, startPanY} — middle-click OR left-drag pan
    let lightboxPinchState = null;

    function fitLightboxToScreen() {
      const wrapRect = lightboxWrap.getBoundingClientRect();
      const availW = Math.max(1, wrapRect.width - 48);
      const availH = Math.max(1, wrapRect.height - 48);
      const naturalW = lightboxImage.naturalWidth || 1;
      const naturalH = lightboxImage.naturalHeight || 1;
      lightboxFitScale = Math.min(availW / naturalW, availH / naturalH, 1);
      if (lightboxFitScale <= 0 || !isFinite(lightboxFitScale)) lightboxFitScale = 1;
      lightboxInner.style.setProperty("--fit-w", (naturalW * lightboxFitScale) + "px");
      lightboxInner.style.setProperty("--fit-h", (naturalH * lightboxFitScale) + "px");
      lightboxZoomLevel = 1;
      lightboxPanX = 0;
      lightboxPanY = 0;
      applyLightboxZoomTransform();
    }

    function applyLightboxZoomTransform() {
      lightboxInner.style.setProperty("--lightbox-zoom", String(lightboxZoomLevel));
      lightboxInner.style.setProperty("--lightbox-pan-x", lightboxPanX + "px");
      lightboxInner.style.setProperty("--lightbox-pan-y", lightboxPanY + "px");
      lightboxZoomLabel.textContent = Math.round(lightboxFitScale * lightboxZoomLevel * 100) + "%";
    }

    function clampLightboxPan() {
      const wrapRect = lightboxWrap.getBoundingClientRect();
      const w = (lightboxImage.naturalWidth || 1) * lightboxFitScale * lightboxZoomLevel;
      const h = (lightboxImage.naturalHeight || 1) * lightboxFitScale * lightboxZoomLevel;
      const maxX = Math.max(0, (w - wrapRect.width) / 2 + wrapRect.width * 0.4);
      const maxY = Math.max(0, (h - wrapRect.height) / 2 + wrapRect.height * 0.4);
      lightboxPanX = Math.max(-maxX, Math.min(maxX, lightboxPanX));
      lightboxPanY = Math.max(-maxY, Math.min(maxY, lightboxPanY));
    }

    function setLightboxZoom(newLevel, anchorClientX, anchorClientY) {
      newLevel = Math.max(LIGHTBOX_MIN_ZOOM, Math.min(LIGHTBOX_MAX_ZOOM, newLevel));
      if (newLevel === lightboxZoomLevel) return;
      if (anchorClientX !== undefined && anchorClientY !== undefined) {
        const wrapRect = lightboxWrap.getBoundingClientRect();
        const centerX = wrapRect.left + wrapRect.width / 2;
        const centerY = wrapRect.top + wrapRect.height / 2;
        const offsetX = anchorClientX - centerX - lightboxPanX;
        const offsetY = anchorClientY - centerY - lightboxPanY;
        const ratio = newLevel / lightboxZoomLevel;
        lightboxPanX -= offsetX * (ratio - 1);
        lightboxPanY -= offsetY * (ratio - 1);
      }
      lightboxZoomLevel = newLevel;
      clampLightboxPan();
      applyLightboxZoomTransform();
    }

    lightboxZoomIn.addEventListener("click", () => setLightboxZoom(lightboxZoomLevel * 1.5));
    lightboxZoomOut.addEventListener("click", () => setLightboxZoom(lightboxZoomLevel / 1.5));
    lightboxZoomReset.addEventListener("click", () => fitLightboxToScreen());

    lightboxWrap.addEventListener("wheel", (e) => {
      e.preventDefault();
      const factor = Math.exp(-e.deltaY * 0.0015);
      setLightboxZoom(lightboxZoomLevel * factor, e.clientX, e.clientY);
    }, { passive: false });

    // Pan: middle-click drag (matches the image editor) OR a plain left-
    // click drag on the image itself, since the lightbox has no competing
    // tool (pen/crop) that a left-drag would otherwise need to be reserved
    // for — unlike the editor, dragging here can just always mean "pan."
    function lightboxPanStart(e) {
      if (e.button !== undefined && e.button !== 0 && e.button !== 1) return;
      e.preventDefault();
      lightboxPanDrag = { startX: e.clientX, startY: e.clientY, startPanX: lightboxPanX, startPanY: lightboxPanY };
    }
    function lightboxPanMove(e) {
      if (!lightboxPanDrag) return;
      e.preventDefault();
      lightboxPanX = lightboxPanDrag.startPanX + (e.clientX - lightboxPanDrag.startX);
      lightboxPanY = lightboxPanDrag.startPanY + (e.clientY - lightboxPanDrag.startY);
      clampLightboxPan();
      applyLightboxZoomTransform();
    }
    function lightboxPanEnd() {
      lightboxPanDrag = null;
    }
    lightboxImage.addEventListener("mousedown", lightboxPanStart);
    window.addEventListener("mousemove", lightboxPanMove);
    window.addEventListener("mouseup", lightboxPanEnd);
    lightboxImage.addEventListener("auxclick", (e) => { if (e.button === 1) e.preventDefault(); });
    lightboxImage.addEventListener("dragstart", (e) => e.preventDefault()); // don't fight our own drag-pan with native image drag

    function lightboxTouchDist(t0, t1) {
      return Math.hypot(t1.clientX - t0.clientX, t1.clientY - t0.clientY);
    }
    function lightboxTouchMid(t0, t1) {
      return { x: (t0.clientX + t1.clientX) / 2, y: (t0.clientY + t1.clientY) / 2 };
    }
    lightboxWrap.addEventListener("touchstart", (e) => {
      if (e.touches.length === 2) {
        e.preventDefault();
        lightboxPanDrag = null;
        lightboxPinchState = {
          startDist: lightboxTouchDist(e.touches[0], e.touches[1]),
          startZoom: lightboxZoomLevel,
        };
      } else if (e.touches.length === 1) {
        const t = e.touches[0];
        lightboxPanDrag = { startX: t.clientX, startY: t.clientY, startPanX: lightboxPanX, startPanY: lightboxPanY };
      }
    }, { passive: false });
    lightboxWrap.addEventListener("touchmove", (e) => {
      if (lightboxPinchState && e.touches.length === 2) {
        e.preventDefault();
        const dist = lightboxTouchDist(e.touches[0], e.touches[1]);
        const mid = lightboxTouchMid(e.touches[0], e.touches[1]);
        setLightboxZoom(lightboxPinchState.startZoom * (dist / (lightboxPinchState.startDist || 1)), mid.x, mid.y);
      } else if (lightboxPanDrag && e.touches.length === 1) {
        e.preventDefault();
        const t = e.touches[0];
        lightboxPanX = lightboxPanDrag.startPanX + (t.clientX - lightboxPanDrag.startX);
        lightboxPanY = lightboxPanDrag.startPanY + (t.clientY - lightboxPanDrag.startY);
        clampLightboxPan();
        applyLightboxZoomTransform();
      }
    }, { passive: false });
    function lightboxEndTouch(e) {
      if (!e.touches || e.touches.length < 2) lightboxPinchState = null;
      if (!e.touches || e.touches.length < 1) lightboxPanDrag = null;
    }
    lightboxWrap.addEventListener("touchend", lightboxEndTouch);
    lightboxWrap.addEventListener("touchcancel", lightboxEndTouch);

    window.addEventListener("resize", () => {
      if (!lightbox.hidden) fitLightboxToScreen();
    });

    lightboxDownload.addEventListener("click", () => {
      const src = lightboxImage.src;
      if (!src) return;
      const a = document.createElement("a");
      a.href = src;
      a.download = "perla-image-" + Date.now() + (src.includes("image/png") || src.startsWith("blob:") ? ".png" : ".jpg");
      document.body.appendChild(a);
      a.click();
      a.remove();
    });

    function openLightbox(src) {
      lightboxImage.onload = fitLightboxToScreen;
      lightboxImage.src = src;
      lightbox.hidden = false;
    }
    function closeLightbox() {
      lightbox.hidden = true;
      lightboxImage.removeAttribute("src");
      lightboxPanDrag = null;
      lightboxPinchState = null;
    }
    lightboxClose.addEventListener("click", closeLightbox);
    lightbox.addEventListener("click", (e) => {
      if (e.target === lightbox) closeLightbox();
    });

    // ---------- File viewer (reopen an attached text/code/document file) ----------
    const fileViewer = document.getElementById("fileViewer");
    const fileViewerName = document.getElementById("fileViewerName");
    const fileViewerBody = document.getElementById("fileViewerBody");
    const fileViewerClose = document.getElementById("fileViewerClose");
    const fileViewerCopy = document.getElementById("fileViewerCopy");
    const fileViewerDownload = document.getElementById("fileViewerDownload");
    const fileViewerMdToggle = document.getElementById("fileViewerMdToggle");
    // { filename, content, isMarkdown, renderedAsMarkdown } — renderedAsMarkdown
    // is the toggle's current state, only meaningful when isMarkdown is true.
    let fileViewerCurrent = null;

    function isMarkdownFilename(filename) {
      const ext = textFileExtension(filename);
      return ext === ".md" || ext === ".markdown";
    }

    function renderFileViewerBody() {
      fileViewerBody.innerHTML = "";
      const state = fileViewerCurrent;
      if (!state || state.content == null) {
        // Attachments made before this viewer existed (or restored from an
        // old sessionStorage entry saved before content was captured) have
        // no stored text — say so rather than showing a blank panel.
        const empty = document.createElement("div");
        empty.className = "empty file-viewer-empty";
        empty.textContent = "This file's content wasn't saved with the message, so it can't be reopened.";
        fileViewerBody.appendChild(empty);
        return;
      }
      if (state.isMarkdown && state.renderedAsMarkdown) {
        const mdEl = document.createElement("div");
        mdEl.className = "prose";
        mdEl.innerHTML = renderMarkdown(state.content);
        fileViewerBody.appendChild(mdEl);
        attachCodeBlockCopyButtons(mdEl);
      } else {
        const pre = document.createElement("pre");
        pre.textContent = state.content;
        fileViewerBody.appendChild(pre);
      }
    }

    function openFileViewer(filename, content) {
      const isMd = isMarkdownFilename(filename);
      fileViewerCurrent = {
        filename, content, isMarkdown: isMd,
        // Default to the rendered view for markdown — raw source is one
        // toggle away via fileViewerMdToggle.
        renderedAsMarkdown: isMd,
      };
      fileViewerName.textContent = filename;
      fileViewerName.title = filename;
      const icon = document.querySelector("#fileViewer .file-viewer-icon");
      if (icon) icon.innerHTML = GENERIC_FILE_ICON_SVG;
      fileViewerMdToggle.hidden = !isMd || content == null;
      fileViewerMdToggle.classList.toggle("active", isMd && fileViewerCurrent.renderedAsMarkdown);
      renderFileViewerBody();
      fileViewer.hidden = false;
    }

    function closeFileViewer() {
      fileViewer.hidden = true;
      fileViewerCurrent = null;
    }

    fileViewerClose.addEventListener("click", closeFileViewer);
    fileViewer.addEventListener("click", (e) => {
      if (e.target === fileViewer) closeFileViewer();
    });

    fileViewerMdToggle.addEventListener("click", () => {
      if (!fileViewerCurrent || !fileViewerCurrent.isMarkdown) return;
      fileViewerCurrent.renderedAsMarkdown = !fileViewerCurrent.renderedAsMarkdown;
      fileViewerMdToggle.classList.toggle("active", fileViewerCurrent.renderedAsMarkdown);
      fileViewerMdToggle.title = fileViewerCurrent.renderedAsMarkdown
        ? "Showing rendered markdown — click for raw source"
        : "Showing raw source — click for rendered markdown";
      renderFileViewerBody();
    });

    fileViewerCopy.addEventListener("click", () => {
      if (!fileViewerCurrent || fileViewerCurrent.content == null) return;
      copyTextToClipboard(fileViewerCurrent.content, fileViewerCopy, COPY_ICON_SVG, CHECK_ICON_SVG);
    });

    fileViewerDownload.addEventListener("click", () => {
      if (!fileViewerCurrent || fileViewerCurrent.content == null) return;
      const blob = new Blob([fileViewerCurrent.content], { type: "text/plain" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = fileViewerCurrent.filename || "file.txt";
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    });

    // ---------- Escape ----------
    // ONE dispatcher, and one layer per press. The stack goes first because it is
    // top-down and because a sheet can be open over the lightbox; the fixed
    // overlays then unwind by z-index, which is the order the image editor
    // comment used to describe but did not enforce - the old handler checked
    // imgEditor, lightbox, fileViewer while the file-viewer modal sat at the SAME
    // rung as the editor and was handled by a second listener entirely.
    document.addEventListener("keydown", (e) => {
      if (e.key !== "Escape") return;
      if (closeTopOverlay()) {
        e.preventDefault();
        return;
      }
      if (!imgEditor.hidden) { closeImageEditor(); return; }
      if (!fileViewerModal.hidden) { closeFileViewerModal(); return; }
      if (!lightbox.hidden) { closeLightbox(); return; }
      if (!fileViewer.hidden) { closeFileViewer(); return; }
    });

    // ---------- Welcome empty state ----------
    function showWelcome(tier) {
      const active = tier !== undefined ? tier : activeTier;
      output.innerHTML = "";
      const card = document.createElement("div");
      card.className = "welcome";
      const mark = document.createElement("div");
      mark.className = "welcome-mark";
      if (!CONFIG.ENDPOINT) {
        mark.textContent = "P";
      } else {
        // Render the avatar immediately — no waiting on the async loadAvatar
        // probe, which used to leave a welcome card stuck on "P" when the
        // card was painted before the probe's onload fired. If the avatar
        // file genuinely isn't there, the img errors out and we fall back.
        const img = document.createElement("img");
        img.src = CONFIG.ENDPOINT + CONFIG.AVATAR_PATH;
        img.alt = "Perla";
        img.onerror = () => {
          if (mark.contains(img)) mark.textContent = "P";
        };
        mark.appendChild(img);
      }
      const title = document.createElement("h2");
      title.textContent = active === 2 ? "Full Mode" : "Perla";
      const sub = document.createElement("p");
      sub.textContent = active === 2
        ? "Shell, files, and everything else are in play."
        : "Ask, talk, or attach an image.";
      card.appendChild(mark);
      card.appendChild(title);
      card.appendChild(sub);
      output.appendChild(card);
      output.scrollIntoView({ block: "end" });
    }

    // ---------- Thinking indicator ----------
    function showThinking(forTier) {
      const targetTier = forTier !== undefined ? forTier : activeTier;
      if (!isViewingTierChat(targetTier)) return; // nothing to show in a view that's not on screen
      hideThinking();
      const el = document.createElement("div");
      el.className = "thinking";
      el.id = "thinkingIndicator";
      el.innerHTML = '<span class="think-dot"></span><span class="think-dot"></span><span class="think-dot"></span>';
      output.appendChild(el);
      output.scrollIntoView({ block: "end" });
      el.scrollIntoView({ behavior: "smooth", block: "end" });
    }
    function hideThinking(forTier) {
      // Only remove the indicator if we're still looking at the tier it was
      // shown for — otherwise this could delete a DIFFERENT in-flight
      // request's spinner after the user switched tiers mid-conversation.
      const targetTier = forTier !== undefined ? forTier : activeTier;
      if (!isViewingTierChat(targetTier)) return;
      const el = document.getElementById("thinkingIndicator");
      if (el) el.remove();
    }

    // ---------- Tier switching (Tier 1 / Tier 2 as separate chats) ----------
    const tier1Btn = document.getElementById("tier1Btn");
    const tier2Btn = document.getElementById("tier2Btn");
    const tier1Badge = document.getElementById("tier1Badge");
    const tier2Badge = document.getElementById("tier2Badge");

    const LOCK_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="13" height="13"><rect x="4" y="11" width="16" height="11" rx="2" ry="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>';

    // Marks `tier` as having a response waiting that the user hasn't seen —
    // set whenever addEntry/addImageEntry deliver into a tier that isn't
    // the live view, cleared the moment that tier's plain chat becomes the
    // live view again (see switchTier). Tier 2 additionally shows a lock
    // icon when not elevated, which unread always takes priority over.
    function markTierUnread(tier) {
      if (tier === 1) {
        tier1Unread = true;
        sessionStorage.setItem("perla_tier1_unread", "1");
      } else {
        tier2Unread = true;
        sessionStorage.setItem("perla_tier2_unread", "1");
      }
      renderTierBadges();
    }

    function clearTierUnread(tier) {
      if (tier === 1) {
        tier1Unread = false;
        sessionStorage.setItem("perla_tier1_unread", "0");
      } else {
        tier2Unread = false;
        sessionStorage.setItem("perla_tier2_unread", "0");
      }
    }

    function renderTierBadges() {
      tier1Badge.classList.remove("unread");
      if (activeTier !== 1 && tier1Unread) {
        tier1Badge.textContent = "new";
        tier1Badge.classList.add("unread");
      } else {
        tier1Badge.innerHTML = "";
      }

      tier2Badge.classList.remove("locked", "unread");
      if (activeTier !== 2 && tier2Unread) {
        tier2Badge.textContent = "new";
        tier2Badge.classList.add("unread");
      } else if (isElevated) {
        tier2Badge.innerHTML = "";
      } else {
        tier2Badge.innerHTML = LOCK_ICON;
        tier2Badge.classList.add("locked");
      }
    }

    function setElevated(value) {
      isElevated = value;
      sessionStorage.setItem("perla_elevated", value ? "1" : "0");
      renderTierBadges();
      updateComposerMode();
    }

    function updateTier2UnreadBadge() {
      renderTierBadges();
    }

    // ---------- Full Mode live countdown: GONE ----------
    //
    // #tierTimer was the ONLY surface of the live countdown, and it was removed
    // from the markup at the user's request along with the tier pill and the
    // status dot. So startTierTimer / tickTierTimer / stopTierTimer went with it
    // rather than being left writing into a detached node on a 500ms interval -
    // which is the alternative, and it is a worse outcome than either keeping or
    // removing them, because a timer nobody can see is indistinguishable from a
    // timer that is broken.
    //
    // WHAT SURVIVES, and it is the part that matters: the elevation still EXPIRES
    // on exactly the same schedule and still re-locks Tier 2 and still posts the
    // "Full Mode expired" notice, because none of that lived here. It lived in
    // window._elevateExpiryTimer, armed where it always was (see the elevate
    // handler and relockSession), and that is untouched.
    //
    // WHAT IS LOST, plainly, because it is a capability change and not a deletion
    // of decoration: there is no longer anything counting down. The user is told
    // Full Mode lasts 5 minutes, is told when it ends, and sees nothing in
    // between. sessionStorage "perla_elevate_until" is still written and still
    // read at load, because it is what decides whether a RELOAD lands inside or
    // outside the elevation window - see the deferred init at the foot of this
    // file, which still calls setElevated(false) when the stored window has
    // passed.

    // The tier rows should only show "active" when that tier's plain chat is
    // actually on screen — not while History/Reminders (or any future overlay)
    // is showing over it — and the nav row for the surface that IS on screen has
    // to say so through aria-current. Both halves are DERIVED from activeTier /
    // activeOverlay rather than remembered from the last click, which is what
    // keeps them honest when a surface is opened from somewhere other than its
    // own nav row. Centralized here and called from every place that changes
    // either, so no two rows are ever highlighted at once.
    function updateTierButtonHighlight() {
      tier1Btn.classList.toggle("active", activeOverlay === null && activeTier === 1);
      tier2Btn.classList.toggle("active", activeOverlay === null && activeTier === 2);
      setDestination(activeOverlay === null ? "chat" : DESTINATION_FOR_OVERLAY[activeOverlay]);
    }

    // Disables the actual input controls (not just hiding the composer's
    // container) whenever a read-only overlay like History is on screen —
    // belt-and-suspenders against a stray Enter keypress or programmatic
    // submit reaching OpenCode while the user is looking at old messages,
    // not just relying on `composer.hidden` keeping them out of tab order.
    function setComposerDisabled(disabled) {
      textInput.disabled = disabled;
      sendText.disabled = disabled || !(
        textInput.value.trim() || attachQueue.length > 0 || textFileQueue.length > 0
      );
      micBtn.disabled = disabled;
      attachBtn.disabled = disabled;
    }

    // Decides which footer — the real composer, the elevate-token bar, or
    // neither — belongs on screen right now, purely from the three bits of
    // state that determine it: activeTier, isElevated, activeOverlay.
    // Called from every place any of those three can change. History and
    // Reminders always win (composer.hidden already handles that via
    // setComposerDisabled elsewhere) — this only decides between the normal
    // composer and the elevate bar for the plain-chat case.
    function updateComposerMode() {
      // The line that used to be here -
      //   statusIndicator.hidden = activeOverlay !== null;
      // - is gone with #statusIndicator, and with it the ordering guarantee it
      // was written to carry. It sat ABOVE the `activeOverlay !== null` early
      // return on purpose, so that no future overlay could forget to hide the
      // tier pill, the countdown and the status dot. That guarantee existed to
      // protect a hiding, and there is nothing left to hide: all three of those
      // elements have been removed from the markup at the user's request, so
      // the ordering question is now vacuous rather than merely satisfied.
      //
      // It is recorded here rather than left in the HTML comment alone because
      // test_primitives.sh section 6 used to pin that line's position and its
      // exact text, and a reader comparing against that report needs to know the
      // pin went with the element rather than being quietly loosened.
      //
      // The composer's own two lines below - composer.hidden and
      // setComposerDisabled - are INSIDE the early return, which is correct and
      // unchanged: they describe the composer rather than something that has to
      // be cleared on the way past it.
      if (activeOverlay !== null) {
        // A read-only overlay (History/Reminders) wins over both — hide
        // the real composer and the elevate bar alike, and make sure the
        // composer's own controls are disabled (not just hidden) so a
        // stray keypress can't reach OpenCode while browsing old messages.
        composer.hidden = true;
        setComposerDisabled(true);
        elevateComposer.hidden = true;
        return;
      }
      const needsElevation = activeTier === 2 && !isElevated;
      composer.hidden = needsElevation;
      setComposerDisabled(needsElevation);
      elevateComposer.hidden = !needsElevation;
      if (needsElevation) {
        elevateStatus.textContent = "";
        elevateInput.focus();
      }
    }

    function switchTier(tier) {
      // Tapping a tier button always means "show me that tier's chat" —
      // whether we're currently on the other tier, viewing History/
      // Reminders, or even already on this tier but buried in an overlay.
      // Tier 2 is always viewable this way, elevated or not — reading its
      // history doesn't need the token, only SENDING does (updateComposerMode
      // below swaps in the elevate bar in place of the real composer whenever
      // that's the case).
      // Close any open overlay first (this restores the composer and clears
      // liveOutputHTML) so the code below always ends up painting the
      // requested tier's transcript into a plain, composer-visible chat view,
      // instead of leaving the overlay's read-only chrome in place.
      const wasSameTier = tier === activeTier;
      const hadOverlay = activeOverlay !== null;
      if (activeOverlay === "history") closeHistoryPanel();
      else if (activeOverlay === "reminders") closeRemindersPanel();
      else if (activeOverlay === "quick-actions") closeQuickActionsPanel();
      else if (activeOverlay === "drive") closeDrivePanel();

      if (wasSameTier && !hadOverlay) return; // nothing actually changed

      // Persist current tier's draft and transcript before swapping
      saveCurrentTierDraft();
      if (!hadOverlay) setChatLog(activeTier, output.innerHTML);

      activeTier = tier;
      // Recorded HERE, beside the assignment it mirrors and AFTER the overlay
      // closes above, and the position is load-bearing rather than cosmetic. The
      // close calls updateTierButtonHighlight, which reaches
      // setDestination("chat"), which calls switchTier(lastActiveTier) - so this
      // line decides what that nested call sees. Below the closes it still holds
      // the OLD tier, so the nested call matches `wasSameTier && !hadOverlay` and
      // returns having done nothing. Above them it would already hold the new tier,
      // the nested call would miss that early return, and one tap on Tier 2 would
      // commit and repaint twice.
      lastActiveTier = tier;
      sessionStorage.setItem("perla_active_tier", String(tier));
      // The "T" + tier pill write that used to sit here is gone with
      // #tierBadge; updateTierButtonHighlight() below is what marks the active
      // tier now, on the tier row itself.

      updateTierButtonHighlight();
      updateComposerMode();

      // Landing on a tier's own chat always clears its unread flag, whether
      // it's Tier 1 or Tier 2 — both can now receive a backgrounded reply.
      clearTierUnread(tier);
      updateTier2UnreadBadge();

      output.innerHTML = getChatLog(tier);
      // The restored markup carries only each entry's data-turn-id; the live
      // Retry closure for a still-failed send lives in failedSends, so
      // re-apply it here (and strip any that no longer have one).
      restoreFailedSendState(output);
      if (!output.innerHTML) {
        showWelcome(tier);
      }
      output.scrollIntoView({ block: "end" });

      // Restore any draft text and attachments for this tier
      restoreTierDraft(tier);
    }

    tier1Btn.addEventListener("click", () => { switchTier(1); });
    tier2Btn.addEventListener("click", () => { switchTier(2); });

    // Shared copy-to-clipboard logic (Clipboard API with a hidden-textarea
    // fallback for non-secure contexts) — used by the per-message copy
    // button (addCopyButton) and per-code-block copy buttons
    // (attachCodeBlockCopyButtons) alike, so the fallback path only needs
    // to be gotten right in one place. `btn` briefly swaps to a checkmark
    // on success; callers own their own icon markup via getIcons().
    async function copyTextToClipboard(text, btn, copyIcon, checkIcon) {
      try {
        await navigator.clipboard.writeText(text);
      } catch (e) {
        // Clipboard API can fail without a secure context/permission —
        // fall back to a hidden textarea + execCommand so copy still
        // works rather than silently doing nothing.
        try {
          const ta = document.createElement("textarea");
          ta.value = text;
          ta.style.position = "fixed";
          ta.style.opacity = "0";
          document.body.appendChild(ta);
          ta.select();
          document.execCommand("copy");
          document.body.removeChild(ta);
        } catch (e2) {
          return;
        }
      }
      btn.innerHTML = checkIcon;
      btn.classList.add("copied");
      setTimeout(() => {
        btn.innerHTML = copyIcon;
        btn.classList.remove("copied");
      }, 1500);
    }

    const COPY_ICON_SVG = '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" width="13" height="13"><rect x="8" y="8" width="11" height="11" rx="2"/><path d="M15 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h3"/></svg>';
    const CHECK_ICON_SVG = '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" width="13" height="13"><polyline points="4 12 9 17 18 6"/></svg>';

    function addCopyButton(entry, text) {
      const meta = entry.querySelector(".entry-meta");
      if (!meta) return;
      const btn = document.createElement("button");
      btn.className = "btn-icon btn-icon-20 copy-btn";
      btn.setAttribute("aria-label", "Copy message");
      btn.title = "Copy";
      btn.innerHTML = COPY_ICON_SVG;
      btn.addEventListener("click", () => {
        copyTextToClipboard(text, btn, COPY_ICON_SVG, CHECK_ICON_SVG);
      });
      meta.appendChild(btn);
    }

    // Scans a rendered-markdown container for fenced code blocks
    // (<pre><code>, as emitted by renderMarkdown) and adds a small copy
    // button to each one — used wherever markdown gets rendered (chat
    // bubbles, the file viewer's markdown mode) so code blocks are
    // copyable without hand-selecting text around the button UI. Safe to
    // call multiple times on the same container; it skips blocks that
    // already have one (data-copy-wired), so re-rendering (e.g. toggling
    // the file viewer's raw/rendered mode back and forth) never double-adds.
    function attachCodeBlockCopyButtons(container) {
      container.querySelectorAll("pre").forEach((pre) => {
        if (pre.dataset.copyWired) return;
        pre.dataset.copyWired = "1";
        const code = pre.querySelector("code");
        const text = (code || pre).textContent;
        pre.classList.add("code-block-wrap");
        // The button goes in a wrapper AROUND the pre, not inside it. The pre
        // is the horizontal scroll container, and an absolutely positioned
        // descendant of a scroller is placed against the scroller's content
        // and scrolls with it - so `right: 6px` meant 6px past the longest
        // line and the button drifted off on any code that overflowed.
        // A wrapper that does not scroll gives it a corner that stays put.
        const wrap = document.createElement("div");
        wrap.className = "code-block";
        pre.parentNode.insertBefore(wrap, pre);
        wrap.appendChild(pre);
        const btn = document.createElement("button");
        btn.className = "btn-icon btn-icon-24 btn-icon-square btn-icon-outline code-copy-btn";
        btn.setAttribute("aria-label", "Copy code");
        btn.title = "Copy code";
        btn.innerHTML = COPY_ICON_SVG;
        btn.addEventListener("click", (e) => {
          e.stopPropagation();
          copyTextToClipboard(text, btn, COPY_ICON_SVG, CHECK_ICON_SVG);
        });
        wrap.appendChild(btn);
      });
    }

    function addReplayButton(entry, audioValue) {
      const meta = entry.querySelector(".entry-meta");
      if (!meta) return;
      const btn = document.createElement("button");
      btn.className = "btn-icon btn-icon-20 replay-btn";
      btn.setAttribute("aria-label", "Play voice reply");
      btn.title = "Play";
      btn.innerHTML = '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round" width="14" height="14"><path d="M6.5 4.5v13l11-6.5-11-6.5z"/></svg>';
      btn.addEventListener("click", () => playAudio(audioValue));
      meta.appendChild(btn);
    }

    // A HOLLOW square, not a filled one: it sits beside replay/copy/retry in the
    // message's action row, and a solid block at the same optical weight read as
    // the loudest thing in the row when "stop" is a quiet, temporary affordance.
    // Stroked rather than filled, so it shares its weight with the mic's stop
    // square (.mic-stop-square), which is drawn the same way.
    // The rect spans 5.5..16.5 on both axes, centred on the viewBox's (11,11).
    const STOP_ICON_SVG = '<svg viewBox="0 0 22 22" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2"><rect x="5.5" y="5.5" width="11" height="11" rx="2"/></svg>';

    // Aborts whatever the given tier is doing (in-flight generation and/or a
    // pending question). Sending a new message interrupts too — this button
    // is for stopping without sending anything. The request that was waiting
    // on the turn receives the server's "Stopped." reply and clears itself.
    async function interruptTurn(forTier) {
      const targetTier = forTier !== undefined ? forTier : activeTier;
      try {
        const res = await fetch(CONFIG.ENDPOINT + CONFIG.INTERRUPT_PATH, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: "Bearer " + authToken,
          },
          body: JSON.stringify({ tier: targetTier }),
        });
        if (res.status === 401) {
          relockSession();
          return;
        }
        if (!res.ok) notify("error", "Couldn't stop that.");
      } catch (err) {
        notify("error", "Couldn't stop that.");
      }
    }

    // Puts a Stop button in the message's meta row (the same place as the
    // timestamp / play / copy icons) while its turn is still in flight, and
    // takes it away again once the turn lands. The entry is force-shown
    // (meta-visible) the whole time so the row is actually visible on touch
    // devices where :hover doesn't apply.
    //
    // Registered per-tier so a turn that survives a question round-trip (the
    // Stop button must stay put while the card is up) can still be cleaned up
    // when the final reply finally renders. A new message on the same tier
    // replaces the old one — that turn is being interrupted anyway.
    const stopButtonRemovers = {};

    function addStopButton(entry, forTier) {
      if (!entry) return () => { };
      const targetTier = forTier !== undefined ? forTier : activeTier;
      const meta = entry.querySelector(".entry-meta");
      if (!meta) return () => { };
      if (stopButtonRemovers[targetTier]) stopButtonRemovers[targetTier]();
      const btn = document.createElement("button");
      // No .stop-btn class: it was set here but never queried by anything, and
      // its only rule (:disabled) is the primitive's. The button itself is
      // styled by .btn-icon; only the name was dead.
      btn.className = "btn-icon btn-icon-20";
      btn.setAttribute("aria-label", "Stop generating");
      btn.title = "Stop";
      btn.innerHTML = STOP_ICON_SVG;
      btn.addEventListener("click", () => {
        btn.disabled = true;
        interruptTurn(targetTier);
      });
      meta.appendChild(btn);
      entry.classList.add("meta-visible");
      const remove = () => {
        btn.remove();
        // Don't un-show the row if a failed-send marking is now the reason
        // it's visible (markEntryFailed adds meta-visible too, and the
        // send's finally block removes the stop button afterwards).
        if (!entry.classList.contains("entry-failed")) {
          entry.classList.remove("meta-visible");
        }
        if (stopButtonRemovers[targetTier] === remove) delete stopButtonRemovers[targetTier];
      };
      stopButtonRemovers[targetTier] = remove;
      return remove;
    }

    // Called whenever a turn has actually ended (final reply rendered) so the
    // Stop button doesn't linger on a message that's already been answered.
    function clearStopButton(forTier) {
      const targetTier = forTier !== undefined ? forTier : activeTier;
      if (stopButtonRemovers[targetTier]) stopButtonRemovers[targetTier]();
    }

    // ---------- Failed-send state (Retry) ----------
    const RETRY_ICON_SVG = '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" width="13" height="13"><path d="M17.5 6.5v4h-4"/><path d="M4.5 15.5v-4h4"/><path d="M6.1 9a5.5 5.5 0 0 1 9.2-2.4l2.2 2.2"/><path d="M15.9 13a5.5 5.5 0 0 1-9.2 2.4L4.5 13.2"/></svg>';

    // A message that never made it to Perla: wax-red border, a "Not sent"
    // label, and — when re-sending the identical request could plausibly
    // succeed — a Retry button that re-sends the ORIGINAL payload
    // (attachments included) through the same send path.
    //
    // `retryable` is deliberately narrow. Network errors, timeouts and 5xx
    // are transient, so retrying the same bytes is a real fix. 400 (every
    // attachment rejected / nothing left to send) and 403 (tier not
    // elevated) are deterministic: the identical request fails identically,
    // so those get the failed styling and their notify() text but no button.
    //
    // failedSends holds the payload for every still-failed turn, keyed by the
    // entry's data-turn-id — and deliberately holds NO DOM node or closure.
    // The chat log persists as innerHTML and a tier switch re-reads it, which
    // destroys the original element; resolving the entry fresh on click is
    // what keeps Retry pointed at the bubble currently on screen.
    const failedSends = {};

    // markEntryFailed runs AFTER deliverEntry already snapshotted the entry,
    // so the red border / label / button aren't in the stored log yet.
    // Re-snapshot the tier on screen so the failure state survives a reload
    // (the Retry button itself is still stripped on restore — its payload is
    // gone with the JS heap — but the message keeps reading as "Not sent"). A
    // backgrounded tier is skipped: its log entry is an immutable string
    // appended at delivery time, and restoreFailedSendState() re-applies that
    // tier's live state from failedSends on switch-back anyway.
    function persistFailedState(tier) {
      if (isViewingTierChat(tier)) setChatLog(tier, output.innerHTML);
    }

    // Finds the bubble a turn id belongs to, wherever it currently lives.
    function findTurnEntry(turnId) {
      if (!turnId) return null;
      return output.querySelector('.entry[data-turn-id="' + CSS.escape(turnId) + '"]')
        || backgroundScratch.querySelector('.entry[data-turn-id="' + CSS.escape(turnId) + '"]');
    }

    // Re-sends a failed turn. Resolves the entry by id at click time so a
    // retry still works after a tier switch replaced the DOM.
    function retryFailedSend(turnId) {
      const rec = failedSends[turnId];
      if (!rec) return;
      const entry = findTurnEntry(turnId);
      if (!entry) return;
      if (isViewingTierChat(rec.tier)) {
        entry.scrollIntoView({ behavior: "smooth", block: "end" });
      }
      sendTextTurn(entry, rec.payload);
    }

    // `opts.turnId` marks a failure as retryable and registers the payload.
    // Pass no turnId for a deterministic failure (400/403/missing endpoint):
    // styled as failed, but no button.
    function markEntryFailed(entry, opts) {
      const o = opts || {};
      if (!entry) return;
      const meta = entry.querySelector(".entry-meta");
      const turnId = o.turnId || (entry.dataset ? entry.dataset.turnId : null);
      entry.classList.add("entry-failed");
      if (meta) {
        // Idempotent — a second failure on a retry reuses the same row.
        let label = meta.querySelector(".entry-fail-label");
        if (!label) {
          label = document.createElement("span");
          label.className = "entry-fail-label";
          label.textContent = "Not sent";
          meta.appendChild(label);
        }
        if (o.retryable && turnId) {
          // Always rebuild: a button restored from the chat log is inert
          // markup with no handler, so it must be replaced, not reused.
          const stale = meta.querySelector(".retry-btn");
          if (stale) stale.remove();
          const btn = document.createElement("button");
          btn.className = "btn-icon btn-icon-20 retry-btn";
          btn.setAttribute("aria-label", "Retry sending this message");
          btn.title = "Retry";
          btn.innerHTML = RETRY_ICON_SVG;
          btn.addEventListener("click", () => retryFailedSend(turnId));
          meta.appendChild(btn);
        }
      }
      entry.classList.add("meta-visible");
      persistFailedState(o.tier);
    }

    // Undoes markEntryFailed so a retry puts the message back into its
    // normal in-flight look before re-posting.
    function clearEntryFailed(entry) {
      if (!entry) return;
      entry.classList.remove("entry-failed");
      if (entry.dataset.turnId) delete failedSends[entry.dataset.turnId];
      const meta = entry.querySelector(".entry-meta");
      if (!meta) return;
      const label = meta.querySelector(".entry-fail-label");
      if (label) label.remove();
      const btn = meta.querySelector(".retry-btn");
      if (btn) btn.remove();
    }

    // Re-applies failure state after a chat restore (tier switch). Entries
    // whose turn is still recorded as failed get a FRESH live Retry button;
    // entries whose turn is unknown — a reloaded page, where the payload is
    // gone with the JS heap — are stripped back to plain bubbles rather than
    // left with a control that does nothing.
    function restoreFailedSendState(root) {
      const scope = root || output;
      scope.querySelectorAll(".entry[data-turn-id]").forEach((entry) => {
        const rec = failedSends[entry.dataset.turnId];
        if (!rec) {
          if (entry.classList.contains("entry-failed")) {
            entry.classList.remove("entry-failed", "meta-visible");
            const meta = entry.querySelector(".entry-meta");
            if (meta) {
              const label = meta.querySelector(".entry-fail-label");
              if (label) label.remove();
              const btn = meta.querySelector(".retry-btn");
              if (btn) btn.remove();
            }
          }
          return;
        }
        markEntryFailed(entry, { retryable: true, turnId: entry.dataset.turnId, tier: rec.tier });
      });
      // Belt and braces: any retry button with no live record behind it.
      scope.querySelectorAll(".retry-btn").forEach((btn) => {
        const entry = btn.closest(".entry");
        if (!entry || !failedSends[entry.dataset.turnId]) btn.remove();
      });
    }

    // ---------- Audio playback ----------
    const responseAudio = document.getElementById("responseAudio");

    function playAudio(value) {
      if (!value) return;
      if (value.startsWith("http") || value.startsWith("/")) {
        // Fetch with auth headers since audio GET requires authentication
        const url = value.startsWith("http") ? value : CONFIG.ENDPOINT + value;
        fetch(url, { headers: { Authorization: "Bearer " + authToken } })
          .then(r => r.blob())
          .then(blob => {
            responseAudio.src = URL.createObjectURL(blob);
            responseAudio.play().catch(() => { });
          })
          .catch(() => { });
      } else {
        responseAudio.src = "data:audio/mp3;base64," + value;
        responseAudio.play().catch(() => { });
      }
    }

    // ---------- Text send ----------
    const textInput = document.getElementById("textInput");
    const sendText = document.getElementById("sendText");
    const attachInput = document.getElementById("attachInput");
    const cameraInput = document.getElementById("cameraInput");
    const attachPreview = document.getElementById("attachPreview");
    const composer = document.querySelector(".composer");
    const elevateComposer = document.getElementById("elevateComposer");

    const MAX_IMAGES_PER_MESSAGE = 6; // keep in sync with perla-companion.py

    // Queue of pending attachments: [{ dataUrl, filename }, ...]. Populated
    // from either the file picker (attachInput, multi-select) or the
    // camera capture input (cameraInput, one photo per tap — repeated taps
    // add more), so both paths feed the same queue and preview strip.
    let attachQueue = [];

    // Per-tier drafts for retaining unsent text and attachments across view/tier switches
    const tierDrafts = {
      1: { text: "", attachQueue: [], textFileQueue: [] },
      2: { text: "", attachQueue: [], textFileQueue: [] },
    };

    function saveCurrentTierDraft() {
      tierDrafts[activeTier] = {
        text: textInput ? textInput.value : "",
        attachQueue: [...attachQueue],
        textFileQueue: [...textFileQueue],
      };
      try {
        sessionStorage.setItem("perla_draft_t" + activeTier, JSON.stringify(tierDrafts[activeTier]));
      } catch (e) { }
    }

    function restoreTierDraft(tier) {
      let draft = tierDrafts[tier];
      if (!draft || (!draft.text && draft.attachQueue.length === 0 && draft.textFileQueue.length === 0)) {
        try {
          const saved = sessionStorage.getItem("perla_draft_t" + tier);
          if (saved) draft = JSON.parse(saved);
        } catch (e) { }
      }
      draft = draft || { text: "", attachQueue: [], textFileQueue: [] };
      tierDrafts[tier] = draft;
      if (textInput) {
        textInput.value = draft.text || "";
        textInput.style.height = "auto";
        if (textInput.value) {
          textInput.style.height = Math.min(textInput.scrollHeight, 120) + "px";
        }
      }
      attachQueue = Array.isArray(draft.attachQueue) ? [...draft.attachQueue] : [];
      textFileQueue = Array.isArray(draft.textFileQueue) ? [...draft.textFileQueue] : [];
      renderAttachPreview();
      updateComposerState();
    }

    function clearCurrentTierDraft() {
      tierDrafts[activeTier] = { text: "", attachQueue: [], textFileQueue: [] };
      try {
        sessionStorage.removeItem("perla_draft_t" + activeTier);
      } catch (e) { }
    }

    function addFilesToQueue(fileList) {
      const files = Array.from(fileList || []);
      if (files.length === 0) return;

      const remaining = MAX_IMAGES_PER_MESSAGE - attachQueue.length;
      if (remaining <= 0) {
        notify("error", `You can attach up to ${MAX_IMAGES_PER_MESSAGE} images per message.`);
        return;
      }
      const accepted = files.slice(0, remaining);
      if (files.length > accepted.length) {
        notify("error", `Only added ${accepted.length} of ${files.length} images, max ${MAX_IMAGES_PER_MESSAGE} per message.`);
      }

      accepted.forEach((file) => {
        if (!file.type.startsWith("image/")) {
          notify("error", `${file.name || "That file"} isn't an image.`);
          return;
        }
        if (file.size > 10 * 1024 * 1024) {
          notify("error", `${file.name || "That image"} is too large, max 10MB.`);
          return;
        }
        const reader = new FileReader();
        reader.onload = () => {
          attachQueue.push({ dataUrl: reader.result, filename: file.name });
          renderAttachPreview();
          updateComposerState();
          saveCurrentTierDraft();
        };
        reader.onerror = () => notify("error", `Couldn't read ${file.name || "that image"}.`);
        reader.readAsDataURL(file);
      });
    }

    // ---------- Text / code file attachments ----------
    // Separate queue from attachQueue (images): these are never sent as
    // file parts to the model, just read server-side and inlined into the
    // prompt text (see decode_upload_text_files / format_text_attachments
    // in perla-companion.py). Kept as its own list + preview UI since the
    // two attachment kinds render differently (a thumbnail vs a filename
    // chip) and have separate limits.
    const textFileInput = document.getElementById("textFileInput");
    const MAX_TEXT_FILES_PER_MESSAGE = 8; // keep in sync with perla-companion.py
    const MAX_TEXT_FILE_BYTES = 512 * 1024; // keep in sync with MAX_TEXT_UPLOAD_BYTES
    const MAX_DOCUMENT_FILE_BYTES = 25 * 1024 * 1024; // keep in sync with DOCUMENT_UPLOAD_MAX_BYTES

    // Same extension allowlist as TEXT_UPLOAD_EXTENSIONS server-side. This
    // is a UX convenience so obviously-wrong files never reach the queue —
    // NOT a security boundary; the server re-validates independently and
    // is what actually decides what gets inlined.
    const TEXT_FILE_EXTENSIONS = new Set([
      ".md", ".markdown", ".txt", ".rst", ".adoc",
      ".json", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".conf", ".env",
      ".xml", ".csv", ".tsv",
      ".py", ".js", ".jsx", ".ts", ".tsx", ".nix", ".sh", ".bash", ".zsh",
      ".c", ".h", ".cpp", ".hpp", ".cc", ".cxx", ".rs", ".go", ".java",
      ".kt", ".rb", ".php", ".lua", ".pl", ".sql", ".gd", ".swift", ".cs",
      ".html", ".css", ".scss", ".vue", ".svelte",
      ".log", ".diff", ".patch", ".gitignore", ".dockerfile",
    ]);

    // Document formats routed through perla-textify.py server-side (PDF/
    // PPTX become page images; DOCX/XLSX/etc become extracted text) —
    // same UX-convenience-only allowlist as TEXT_FILE_EXTENSIONS above,
    // kept as a separate set purely so the size check below can apply the
    // right limit for the right kind of file (these are legitimately much
    // larger than a source file for the same amount of real content).
    const DOCUMENT_FILE_EXTENSIONS = new Set([
      ".pdf", ".pptx", ".docx", ".xlsx", ".ipynb", ".odt",
    ]);

    function decodeDataUrlAsText(dataUrl) {
      // Plain text/code attachments are sent as base64 data URLs (same
      // transport as images), but unlike images their content IS just the
      // original text — decode it back for the file viewer rather than
      // waiting on a round trip, since the server never echoes extracted
      // text back in its response. Document formats (PDF/DOCX/etc) are
      // NOT decodable this way — their raw bytes are binary, and the
      // actual extracted text only exists server-side — so this is only
      // meaningful for the plain-text branch (see addUserMessageEntry's
      // caller, which only calls this for TEXT_FILE_EXTENSIONS).
      try {
        const m = /^data:[^;,]*;base64,(.*)$/s.exec(dataUrl);
        if (!m) return null;
        const binary = atob(m[1]);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
        return new TextDecoder("utf-8", { fatal: false }).decode(bytes);
      } catch (e) {
        return null;
      }
    }

    function textFileExtension(filename) {
      const idx = (filename || "").lastIndexOf(".");
      return idx === -1 ? "" : filename.slice(idx).toLowerCase();
    }

    // Single generic file icon used for EVERY attached text/code/document
    // file, regardless of extension — no per-type icon set. Shared by the
    // composer preview chip and the sent-message chip so both look
    // identical apart from the optional remove button.
    const GENERIC_FILE_ICON_SVG =
      '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M12.5 2H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7.5L12.5 2z"/>' +
      '<path d="M12.5 2v5.5H18"/>' +
      '<line x1="7.5" y1="12" x2="14.5" y2="12"/>' +
      '<line x1="7.5" y1="15.5" x2="12.5" y2="15.5"/>' +
      '</svg>';

    // Builds one attached-file square pill: icon on top, truncated
    // filename below, same 64x64 footprint as an image thumbnail.
    // `onRemove` (optional) adds a remove button for the composer's
    // queued-attachment case; omitting it renders the read-only form used
    // above a sent message. `content` (optional) is the file's actual text
    // — when present, clicking the pill (composer preview OR sent message
    // alike) opens it in the file viewer; stored as a data-attribute
    // (HTML-escaped via the DOM's own attribute serialization, never
    // interpolated as markup) so it round-trips through the sessionStorage
    // innerHTML persistence the same way the rest of a message does, and
    // survives a reload without needing separate storage plumbing.
    // Cap on how much of a file's content is kept for later reopening via
    // buildFileChip's data-file-content attribute. Chat history (including
    // every attachment's full text) is persisted to sessionStorage as one
    // big innerHTML string per tier — an unbounded cap here means a
    // handful of large attachments in one session could exhaust that
    // origin's storage quota and silently break ALL chat persistence, not
    // just this feature. 100KB per file keeps a realistic source file or
    // markdown doc fully viewable while bounding the worst case.
    const FILE_VIEWER_CONTENT_CAP = 100 * 1024;

    // Attachment labelling.
    //
    // Type comes from the filename extension because that is the only thing
    // available for EVERY attachment: a queued file has the real File, but a
    // sent one carries just {filename, url} and a history replay just
    // {filename, id} — size and mime are never persisted, so deriving the type
    // locally is what keeps the label honest on old messages too.
    //
    // Size is only ever shown when it is actually known (pass null/undefined
    // otherwise) rather than guessed.
    const ATTACHMENT_TYPES = {
      png: "PNG", jpg: "JPG", jpeg: "JPG", gif: "GIF", webp: "WebP",
      svg: "SVG", avif: "AVIF", heic: "HEIC", bmp: "BMP", ico: "ICO",
      pdf: "PDF",
      txt: "Text", md: "Markdown", markdown: "Markdown", rtf: "RTF",
      csv: "CSV", tsv: "TSV", json: "JSON", yaml: "YAML", yml: "YAML",
      xml: "XML", html: "HTML", htm: "HTML", css: "CSS",
      js: "JavaScript", mjs: "JavaScript", cjs: "JavaScript",
      ts: "TypeScript", tsx: "TypeScript", jsx: "JavaScript",
      py: "Python", rb: "Ruby", rs: "Rust", go: "Go", java: "Java",
      c: "C", h: "C", cpp: "C++", hpp: "C++", cs: "C#", php: "PHP",
      sh: "Shell", bash: "Shell", zsh: "Shell", fish: "Shell",
      sql: "SQL", toml: "TOML", ini: "INI", cfg: "Config", conf: "Config",
      log: "Log", patch: "Patch", diff: "Diff", zip: "ZIP", gz: "Gzip",
      tar: "Tar", mp3: "MP3", wav: "WAV", ogg: "OGG", mp4: "MP4",
      mov: "MOV", webm: "WebM", mkv: "MKV",
    };

    function typeFromFilename(filename) {
      if (!filename) return "File";
      const dot = String(filename).lastIndexOf(".");
      // A leading dot means a dotfile, not an extension, and no dot at all
      // means no extension — both fall back to the generic label.
      if (dot <= 0 || dot === String(filename).length - 1) return "File";
      const ext = String(filename).slice(dot + 1).toLowerCase();
      return ATTACHMENT_TYPES[ext] || (ext ? ext.toUpperCase() : "File");
    }

    // Binary units, matching how the reference writes them (820 KB, 11 MB).
    // Returns "" for an unknown size so the caller can omit the whole segment
    // rather than print a wrong one.
    function formatBytes(bytes) {
      if (bytes == null || !isFinite(bytes) || bytes < 0) return "";
      if (bytes < 1024) return bytes + " B";
      const units = ["KB", "MB", "GB", "TB"];
      let v = bytes / 1024;
      let i = 0;
      while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
      // One decimal below 10, none above — 9.4 MB, 820 KB, 11 MB.
      const rounded = v < 10 ? Math.round(v * 10) / 10 : Math.round(v);
      return rounded + " " + units[i];
    }

    // The second line: "PDF", "PNG · 820 KB", "TypeScript · 12 KB".
    function attachmentMetaLine(filename, size) {
      const type = typeFromFilename(filename);
      const bytes = formatBytes(size);
      return bytes ? type + " · " + bytes : type;
    }

    // An image attachment: thumbnail on top, name and "TYPE · SIZE" beneath.
    // Shared by the composer queue and the sent-message path so a queued image
    // and the same image after sending are the same shape. `size` is the byte
    // count where known and null for sent/replayed images, which were never
    // persisted — the type still comes from the filename extension.
    function buildImageCard(item, opts) {
      const o = opts || {};
      const card = document.createElement("div");
      card.className = "attach-thumb";
      const frame = document.createElement("div");
      frame.className = "attach-thumb-frame";

      const img = document.createElement("img");
      img.src = item.dataUrl;
      img.alt = item.filename || "Attached image";
      if (o.onClick) img.addEventListener("click", o.onClick);
      frame.appendChild(img);

      if (o.onEdit) {
        const editBtn = document.createElement("button");
        editBtn.className = "attach-thumb-edit";
        editBtn.setAttribute("aria-label", "Edit image");
        editBtn.title = "Edit";
        editBtn.innerHTML = '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" width="10" height="10"><path d="M13.5 3.5l5 5L7 20l-5.5 1.5L3 16z"/></svg>';
        editBtn.addEventListener("click", (e) => { e.stopPropagation(); o.onEdit(); });
        frame.appendChild(editBtn);
      }
      if (o.onRemove) {
        const removeBtn = document.createElement("button");
        removeBtn.className = "attach-thumb-remove";
        removeBtn.setAttribute("aria-label", "Remove image");
        removeBtn.title = "Remove";
        removeBtn.textContent = "✕";
        removeBtn.addEventListener("click", (e) => { e.stopPropagation(); o.onRemove(); });
        frame.appendChild(removeBtn);
      }

      const caption = document.createElement("div");
      caption.className = "attach-thumb-caption";
      const nameEl = document.createElement("div");
      nameEl.className = "attach-thumb-name";
      nameEl.textContent = item.filename || "Image";
      nameEl.title = item.filename || "Image";
      const meta = document.createElement("div");
      meta.className = "attach-thumb-meta";
      meta.textContent = attachmentMetaLine(item.filename, item.size);
      caption.appendChild(nameEl);
      caption.appendChild(meta);

      card.appendChild(frame);
      card.appendChild(caption);
      return card;
    }

    // A queued FILE: back to the compact square chip, matching the images beside
    // it rather than the full-width row a delivered file uses. The two states
    // are deliberately different — in the composer everything is a fixed-size
    // tile you can see all of at once; once sent, files become labelled rows.
    function buildQueuedFileChip(filename, onRemove, content, size) {
      const chip = buildFileChip(filename, onRemove, content, size);
      chip.classList.add("attach-file-chip-queued");
      // The square chip centres a short name, so a long filename would be
      // unreadable; the row layout truncates properly and is used once sent.
      return chip;
    }

    // A file attachment: a full-width row, not a 64px square. Icon tile on the
    // left, name over a muted "TYPE · SIZE" line, dismiss on the right.
    // `size` is the byte count when known (queued composer items) and null for
    // sent/history attachments, where it was never persisted — the type is
    // still derived from the filename so the label is never blank.
    function buildFileChip(filename, onRemove, content, size) {
      const chip = document.createElement("div");
      chip.className = "attach-file-chip";
      if (content != null) {
        chip.dataset.fileContent = content.length > FILE_VIEWER_CONTENT_CAP
          ? content.slice(0, FILE_VIEWER_CONTENT_CAP) +
          "\n\n[... truncated for storage — reopen the original file to see the rest ...]"
          : content;
      }

      const icon = document.createElement("span");
      icon.className = "attach-file-icon";
      icon.innerHTML = GENERIC_FILE_ICON_SVG;

      // A separate spinner element. Spinning the file icon read as "this file
      // is spinning", which is meaningless; a real spinner sits alongside the
      // icon and the icon is hidden while it is showing.
      const spinner = document.createElement("span");
      spinner.className = "spinner";
      spinner.setAttribute("aria-hidden", "true");

      const text = document.createElement("span");
      text.className = "attach-file-text";
      const nameEl = document.createElement("span");
      nameEl.className = "attach-file-name";
      nameEl.textContent = filename;
      nameEl.title = filename;
      const meta = document.createElement("span");
      meta.className = "attach-file-meta";
      meta.textContent = attachmentMetaLine(filename, size);
      text.appendChild(nameEl);
      text.appendChild(meta);

      chip.appendChild(icon);
      chip.appendChild(spinner);
      chip.appendChild(text);

      // Clicking the row always opens the viewer — both a queued composer
      // attachment (so you can double-check a file before sending) and a
      // delivered sent-message row. The remove button (composer only) stops
      // propagation below so removing an item doesn't also pop the viewer open
      // on the way out.
      chip.addEventListener("click", () => {
        openFileViewer(filename, chip.dataset.fileContent ?? null);
      });
      if (onRemove) {
        const removeBtn = document.createElement("button");
        removeBtn.className = "attach-file-remove";
        removeBtn.setAttribute("aria-label", "Remove file");
        removeBtn.title = "Remove";
        removeBtn.textContent = "✕";
        removeBtn.addEventListener("click", (e) => {
          e.stopPropagation();
          onRemove();
        });
        chip.appendChild(removeBtn);
      }
      return chip;
    }

    // Queue of pending text/code attachments: [{ dataUrl, filename }, ...].
    let textFileQueue = [];

    function renderAttachPreview() {
      // Text-file chips share the same preview strip as image thumbnails
      // (attachPreview), just with a different inner shape — one flat row
      // instead of separate render targets, so the composer only ever has
      // one place to look for "what's queued to send."
      attachPreview.innerHTML = "";
      attachPreview.hidden = attachQueue.length === 0 && textFileQueue.length === 0;

      attachQueue.forEach((item, index) => {
        attachPreview.appendChild(buildImageCard(item, {
          onEdit: () => openImageEditor(index),
          onRemove: () => {
            attachQueue.splice(index, 1);
            renderAttachPreview();
            updateComposerState();
            saveCurrentTierDraft();
          },
        }));
      });

      textFileQueue.forEach((item, index) => {
        // Same decode-for-viewing as the sent-message path (see
        // addUserMessageEntry) — only plain text/code files can be
        // decoded back to real content client-side; document formats
        // (PDF/DOCX/etc) are binary at this layer and show the viewer's
        // "content wasn't saved" fallback instead.
        const ext = textFileExtension(item.filename);
        const content = TEXT_FILE_EXTENSIONS.has(ext)
          ? decodeDataUrlAsText(item.dataUrl)
          : null;
        const chip = buildQueuedFileChip(item.filename, () => {
          textFileQueue.splice(index, 1);
          renderAttachPreview();
          updateComposerState();
          saveCurrentTierDraft();
        }, content, item.size);
        attachPreview.appendChild(chip);
      });
    }

    function addTextFilesToQueue(fileList) {
      const files = Array.from(fileList || []);
      if (files.length === 0) return;

      const remaining = MAX_TEXT_FILES_PER_MESSAGE - textFileQueue.length;
      if (remaining <= 0) {
        notify("error", `You can attach up to ${MAX_TEXT_FILES_PER_MESSAGE} text/code files per message.`);
        return;
      }
      const accepted = files.slice(0, remaining);
      if (files.length > accepted.length) {
        notify("error", `Only added ${accepted.length} of ${files.length} files, max ${MAX_TEXT_FILES_PER_MESSAGE} per message.`);
      }

      accepted.forEach((file) => {
        const ext = textFileExtension(file.name);
        const isDocument = DOCUMENT_FILE_EXTENSIONS.has(ext);
        const isPlainText = TEXT_FILE_EXTENSIONS.has(ext);
        if (!isDocument && !isPlainText) {
          // Discard silently-ish: one short system note, then move on —
          // matches the requested behavior of not blocking the rest of
          // the send over one bad file. The OS file picker's `accept`
          // filter already keeps most of these out; this covers drag-drop
          // or a picker that ignores `accept`.
          notify("error", `${file.name || "That file"} isn't a supported file type, skipped.`);
          return;
        }
        // Document formats (PDF/PPTX/DOCX/XLSX/etc) are legitimately much
        // larger than a source file carrying the same amount of real
        // content — embedded fonts, images, XML overhead — so they get
        // their own, larger ceiling instead of the plain-text one.
        const maxBytes = isDocument ? MAX_DOCUMENT_FILE_BYTES : MAX_TEXT_FILE_BYTES;
        if (file.size > maxBytes) {
          const limitLabel = isDocument
            ? `${Math.round(maxBytes / (1024 * 1024))}MB`
            : `${Math.round(maxBytes / 1024)}KB`;
          notify("error", `${file.name || "That file"} is too large, max ${limitLabel}, skipped.`);
          return;
        }
        const reader = new FileReader();
        reader.onload = () => {
          textFileQueue.push({ dataUrl: reader.result, filename: file.name });
          renderAttachPreview();
          updateComposerState();
          saveCurrentTierDraft();
        };
        reader.onerror = () => notify("error", `Couldn't read ${file.name || "that file"}, skipped.`);
        // Read as a data URL (base64), same transport shape as images —
        // the server decodes+decides text-vs-binary on its own; the client
        // doesn't need to pre-decode UTF-8 itself.
        reader.readAsDataURL(file);
      });
    }

    textFileInput.addEventListener("change", () => {
      addTextFilesToQueue(textFileInput.files);
      textFileInput.value = "";
    });

    attachInput.addEventListener("change", () => {
      addFilesToQueue(attachInput.files);
      attachInput.value = "";
    });

    cameraInput.addEventListener("change", () => {
      addFilesToQueue(cameraInput.files);
      cameraInput.value = "";
    });

    // ---------- Drag-and-drop upload onto the chat ----------
    // Splits dropped files by type and routes each half to the queue
    // function that already validates it (addFilesToQueue rejects/skips
    // non-images per-file, addTextFilesToQueue rejects/skips unsupported
    // extensions per-file) — dropping a mixed batch (a screenshot plus a
    // couple of source files) queues all of it correctly rather than one
    // half getting rejected for looking like the wrong kind to the other
    // function. Scoped to the whole `.app` shell rather than just
    // `.page`/`output` so dropping near the composer also works, but only
    // takes effect when a normal chat composer is actually the thing on
    // screen (an overlay like System/History has its own drop target, or
    // no drop target at all, and dropping into a hidden composer would be
    // silently confusing).
    const chatDropTarget = document.querySelector(".app");
    let chatDragDepth = 0; // dragenter/dragleave fire on every descendant;
    // a depth counter (not a boolean) is what keeps the highlight from
    // flickering off while the pointer crosses a child element's edge.

    function chatDropActive() {
      return activeOverlay === null && !composer.hidden;
    }

    chatDropTarget.addEventListener("dragenter", (e) => {
      if (!chatDropActive() || !e.dataTransfer || !e.dataTransfer.types.includes("Files")) return;
      e.preventDefault();
      chatDragDepth++;
      chatDropTarget.classList.add("chat-dropzone-active");
    });
    chatDropTarget.addEventListener("dragover", (e) => {
      if (!chatDropActive() || !e.dataTransfer || !e.dataTransfer.types.includes("Files")) return;
      e.preventDefault();
    });
    chatDropTarget.addEventListener("dragleave", (e) => {
      if (!chatDropActive()) return;
      chatDragDepth = Math.max(0, chatDragDepth - 1);
      if (chatDragDepth === 0) chatDropTarget.classList.remove("chat-dropzone-active");
    });
    chatDropTarget.addEventListener("drop", (e) => {
      chatDragDepth = 0;
      chatDropTarget.classList.remove("chat-dropzone-active");
      if (!chatDropActive() || !e.dataTransfer || !e.dataTransfer.files || !e.dataTransfer.files.length) return;
      e.preventDefault();
      const files = Array.from(e.dataTransfer.files);
      const images = files.filter((f) => f.type.startsWith("image/"));
      const others = files.filter((f) => !f.type.startsWith("image/"));
      if (images.length) addFilesToQueue(images);
      if (others.length) addTextFilesToQueue(others);
    });

    // ---------- Paste files into chat (Ctrl+V / Cmd+V) ----------
    // Covers two distinct clipboard shapes browsers hand back on paste:
    // (1) an actual image copied from a screenshot tool or another app —
    // arrives as a File-less DataTransferItem of kind "file" with no
    // filename, so one is invented; (2) one or more real files copied
    // from the OS file manager — arrive as ordinary File objects in
    // clipboardData.files, same shape a drag-drop or file-picker
    // produces. Plain copied TEXT is deliberately left alone here — that
    // should paste into the textarea itself via the browser's own
    // default behavior, not get treated as a "file" attachment.
    textInput.addEventListener("paste", (e) => {
      if (!e.clipboardData) return;
      const files = Array.from(e.clipboardData.files || []);
      if (files.length === 0) return; // plain text paste — let the default happen
      e.preventDefault();
      const images = files.filter((f) => f.type.startsWith("image/"));
      const others = files.filter((f) => !f.type.startsWith("image/"));
      if (images.length) {
        // A raw clipboard image often has no filename (or a generic
        // "image.png") — addFilesToQueue only reads file.name for the
        // preview label, so this is cosmetic, not a correctness issue.
        addFilesToQueue(images.map((f, i) => {
          if (f.name && f.name !== "image.png") return f;
          const ext = (f.type.split("/")[1] || "png").split("+")[0];
          return new File([f], `pasted-image-${Date.now()}-${i}.${ext}`, { type: f.type });
        }));
      }
      if (others.length) addTextFilesToQueue(others);
    });

    // ---------- Attach menu (paperclip → Camera / Image) ----------
    const attachBtn = document.getElementById("attachBtn");
    const attachMenu = document.getElementById("attachMenu");
    const attachCameraBtn = document.getElementById("attachCameraBtn");
    const attachImageBtn = document.getElementById("attachImageBtn");
    const attachTextFileBtn = document.getElementById("attachTextFileBtn");

    function closeAttachMenu() {
      attachMenu.classList.remove("open");
      attachMenu.setAttribute("aria-hidden", "true");
      attachBtn.classList.remove("active");
      attachBtn.setAttribute("aria-expanded", "false");
    }

    function positionAttachMenu() {
      const btnRect = attachBtn.getBoundingClientRect();
      // Menu's own width isn't known until it's laid out; read it after
      // toggling "open" (display is already flex via .floating-menu, only
      // opacity/transform change, so offsetWidth is reliable even before
      // the transition finishes).
      const menuWidth = attachMenu.offsetWidth || 200;
      let left = btnRect.left;
      // Keep it on-screen if the button is near the right edge.
      left = Math.min(left, window.innerWidth - menuWidth - 12);
      left = Math.max(left, 12);
      attachMenu.style.left = left + "px";
      attachMenu.style.bottom = (window.innerHeight - btnRect.top + 10) + "px";
    }

    function toggleAttachMenu() {
      const opening = !attachMenu.classList.contains("open");
      if (opening) positionAttachMenu();
      attachMenu.classList.toggle("open", opening);
      attachMenu.setAttribute("aria-hidden", String(!opening));
      attachBtn.classList.toggle("active", opening);
      attachBtn.setAttribute("aria-expanded", String(opening));
    }

    attachBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      toggleAttachMenu();
    });

    attachCameraBtn.addEventListener("click", () => {
      closeAttachMenu();
      cameraInput.click();
    });

    attachImageBtn.addEventListener("click", () => {
      closeAttachMenu();
      attachInput.click();
    });

    attachTextFileBtn.addEventListener("click", () => {
      closeAttachMenu();
      textFileInput.click();
    });

    document.addEventListener("click", (e) => {
      if (
        attachMenu.classList.contains("open") &&
        !attachMenu.contains(e.target) &&
        e.target !== attachBtn &&
        !attachBtn.contains(e.target)
      ) {
        closeAttachMenu();
      }
    });

    window.addEventListener("resize", () => {
      if (attachMenu.classList.contains("open")) positionAttachMenu();
    });

    // ---------- Image editor (crop + pen) ----------
    const imgEditor = document.getElementById("imgEditor");
    const editorClose = document.getElementById("editorClose");
    const editorCanvas = document.getElementById("editorCanvas");
    const editorCtx = editorCanvas.getContext("2d");
    const editorCanvasWrap = document.getElementById("editorCanvasWrap");
    const editorCanvasInner = document.getElementById("editorCanvasInner");
    const cropBox = document.getElementById("cropBox");
    const toolCrop = document.getElementById("toolCrop");
    const toolPen = document.getElementById("toolPen");
    const toolUndo = document.getElementById("toolUndo");
    const penOptionsRow = document.getElementById("penOptionsRow");
    const cropOptionsRow = document.getElementById("cropOptionsRow");
    const penColors = document.getElementById("penColors");
    const penWidth = document.getElementById("penWidth");
    const penWidthLabel = document.getElementById("penWidthLabel");
    const applyCropBtn = document.getElementById("applyCrop");
    const editorReset = document.getElementById("editorReset");
    const editorSave = document.getElementById("editorSave");
    const zoomIn = document.getElementById("zoomIn");
    const zoomOut = document.getElementById("zoomOut");
    const zoomReset = document.getElementById("zoomReset");
    const zoomLabel = document.getElementById("zoomLabel");

    let editorQueueIndex = -1;
    let editorOriginalDataUrl = null; // original image as loaded when editor opened, for Reset
    let editorTool = "pen"; // "pen" | "crop"
    let editorPenColor = "#e94f4f";
    let editorPenWidth = 6;
    let editorUndoStack = []; // dataURLs of canvas state before each committed change
    let editorDrawing = false;
    let editorLastPoint = null;

    // Zoom/pan state. fitScale is the CSS px-per-canvas-px ratio that makes
    // the image fit inside the wrap at 100% — zoomLevel is a multiplier on
    // top of that (1 = fit, 2 = fit x2, etc). Applied as a CSS transform on
    // editorCanvasInner, which keeps getBoundingClientRect() (and therefore
    // every pointer-to-canvas coordinate calc below) correct for free —
    // nothing else needs to know about zoom.
    let editorFitScale = 1;
    let editorZoomLevel = 1;
    let editorPanX = 0;
    let editorPanY = 0;
    const MIN_ZOOM = 0.25; // allow zooming out well past "fit" for a wide view
    const MAX_ZOOM = 8;

    // Crop state (in canvas pixel coordinates, not display coordinates)
    let cropRect = null; // {x, y, w, h}
    let cropDrag = null; // {mode: "new"|"move"|handle, startX, startY, orig}
    let panDrag = null;  // {startX, startY, startPanX, startPanY} — active while middle-click panning

    function setEditorTool(tool) {
      editorTool = tool;
      toolCrop.classList.toggle("active", tool === "crop");
      toolPen.classList.toggle("active", tool === "pen");
      penOptionsRow.hidden = tool !== "pen";
      cropOptionsRow.hidden = tool !== "crop";
      if (tool !== "crop") {
        cropBox.hidden = true;
        cropRect = null;
      }
    }

    toolCrop.addEventListener("click", () => setEditorTool("crop"));
    toolPen.addEventListener("click", () => setEditorTool("pen"));

    penColors.addEventListener("click", (e) => {
      const btn = e.target.closest(".color-swatch");
      if (!btn) return;
      editorPenColor = btn.dataset.color;
      penColors.querySelectorAll(".color-swatch").forEach((s) => s.classList.remove("active"));
      btn.classList.add("active");
    });

    penWidth.addEventListener("input", () => {
      editorPenWidth = parseInt(penWidth.value, 10);
      penWidthLabel.textContent = editorPenWidth + "px";
    });

    function pushUndo() {
      editorUndoStack.push(editorCanvas.toDataURL("image/png"));
      if (editorUndoStack.length > 20) editorUndoStack.shift();
    }

    function editorUndo() {
      if (editorUndoStack.length === 0) return;
      const prev = editorUndoStack.pop();
      const img = new Image();
      img.onload = () => {
        editorCanvas.width = img.naturalWidth;
        editorCanvas.height = img.naturalHeight;
        editorCtx.drawImage(img, 0, 0);
        // Undo can revert a crop (changing pixel dimensions), so recompute
        // the fit size — otherwise --fit-w/--fit-h would still reflect the
        // old (cropped) dimensions and the image would render stretched.
        fitEditorToScreen();
      };
      img.src = prev;
    }
    toolUndo.addEventListener("click", editorUndo);

    function loadImageIntoCanvas(dataUrl) {
      return new Promise((resolve) => {
        const img = new Image();
        img.onload = () => {
          editorCanvas.width = img.naturalWidth;
          editorCanvas.height = img.naturalHeight;
          editorCtx.drawImage(img, 0, 0);
          resolve();
        };
        img.src = dataUrl;
      });
    }

    // ---- Zoom / pan ----
    // Computes the CSS size that fits the image (at its natural canvas
    // resolution) inside the wrap, sets that as the base size, then resets
    // zoom/pan to 1/0/0 (fit, centered). Called on open and on Reset.
    function fitEditorToScreen() {
      const wrapRect = editorCanvasWrap.getBoundingClientRect();
      const availW = Math.max(1, wrapRect.width - 32);   // minus wrap padding
      const availH = Math.max(1, wrapRect.height - 32);
      const naturalW = editorCanvas.width || 1;
      const naturalH = editorCanvas.height || 1;
      editorFitScale = Math.min(availW / naturalW, availH / naturalH, 1);
      // Never upscale a small image past its own pixel size at "fit" — only
      // shrink large ones. Zooming further in is still available via controls.
      if (editorFitScale <= 0 || !isFinite(editorFitScale)) editorFitScale = 1;
      editorCanvasInner.style.setProperty("--fit-w", (naturalW * editorFitScale) + "px");
      editorCanvasInner.style.setProperty("--fit-h", (naturalH * editorFitScale) + "px");
      editorZoomLevel = 1;
      editorPanX = 0;
      editorPanY = 0;
      applyZoomTransform();
    }

    function applyZoomTransform() {
      editorCanvasInner.style.setProperty("--editor-zoom", String(editorZoomLevel));
      editorCanvasInner.style.setProperty("--editor-pan-x", editorPanX + "px");
      editorCanvasInner.style.setProperty("--editor-pan-y", editorPanY + "px");
      zoomLabel.textContent = Math.round(editorFitScale * editorZoomLevel * 100) + "%";
    }

    function clampPan() {
      // Keep at least a sliver of the image reachable/on-screen rather than
      // letting it be panned away entirely.
      const wrapRect = editorCanvasWrap.getBoundingClientRect();
      const w = (editorCanvas.width * editorFitScale * editorZoomLevel);
      const h = (editorCanvas.height * editorFitScale * editorZoomLevel);
      const maxX = Math.max(0, (w - wrapRect.width) / 2 + wrapRect.width * 0.4);
      const maxY = Math.max(0, (h - wrapRect.height) / 2 + wrapRect.height * 0.4);
      editorPanX = Math.max(-maxX, Math.min(maxX, editorPanX));
      editorPanY = Math.max(-maxY, Math.min(maxY, editorPanY));
    }

    function setZoom(newLevel, anchorClientX, anchorClientY) {
      newLevel = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, newLevel));
      if (newLevel === editorZoomLevel) return;

      // Zoom toward the anchor point (cursor position, or pinch midpoint)
      // rather than the center, so the thing the user is looking at stays
      // under their fingers/cursor.
      if (anchorClientX !== undefined && anchorClientY !== undefined) {
        const wrapRect = editorCanvasWrap.getBoundingClientRect();
        const centerX = wrapRect.left + wrapRect.width / 2;
        const centerY = wrapRect.top + wrapRect.height / 2;
        const offsetX = anchorClientX - centerX - editorPanX;
        const offsetY = anchorClientY - centerY - editorPanY;
        const ratio = newLevel / editorZoomLevel;
        editorPanX -= offsetX * (ratio - 1);
        editorPanY -= offsetY * (ratio - 1);
      }

      editorZoomLevel = newLevel;
      clampPan();
      applyZoomTransform();
    }

    zoomIn.addEventListener("click", () => setZoom(editorZoomLevel * 1.5));
    zoomOut.addEventListener("click", () => setZoom(editorZoomLevel / 1.5));
    zoomReset.addEventListener("click", () => fitEditorToScreen());

    // Scroll wheel / trackpad zoom over the canvas wrap. Plain wheel zooms
    // (rather than requiring Ctrl) since the editor has no other use for
    // vertical scroll — there's nothing to scroll past the image itself.
    editorCanvasWrap.addEventListener("wheel", (e) => {
      e.preventDefault();
      const delta = -e.deltaY;
      const factor = Math.exp(delta * 0.0015);
      setZoom(editorZoomLevel * factor, e.clientX, e.clientY);
    }, { passive: false });

    // Pinch-to-zoom (two-finger touch). Tracked separately from the single-
    // finger draw/crop handlers below — a second touch point promotes the
    // gesture to a pinch and suppresses drawing for that gesture.
    let pinchState = null; // {startDist, startZoom, midX, midY}

    function touchDist(t0, t1) {
      return Math.hypot(t1.clientX - t0.clientX, t1.clientY - t0.clientY);
    }
    function touchMid(t0, t1) {
      return { x: (t0.clientX + t1.clientX) / 2, y: (t0.clientY + t1.clientY) / 2 };
    }

    editorCanvasWrap.addEventListener("touchstart", (e) => {
      if (e.touches.length === 2) {
        e.preventDefault();
        editorDrawing = false; // cancel any in-progress single-finger stroke
        cropDrag = null;
        const mid = touchMid(e.touches[0], e.touches[1]);
        pinchState = {
          startDist: touchDist(e.touches[0], e.touches[1]),
          startZoom: editorZoomLevel,
          midX: mid.x, midY: mid.y,
        };
      }
    }, { passive: false });

    editorCanvasWrap.addEventListener("touchmove", (e) => {
      if (pinchState && e.touches.length === 2) {
        e.preventDefault();
        const dist = touchDist(e.touches[0], e.touches[1]);
        const mid = touchMid(e.touches[0], e.touches[1]);
        const scaleFactor = dist / (pinchState.startDist || 1);
        setZoom(pinchState.startZoom * scaleFactor, mid.x, mid.y);
      }
    }, { passive: false });

    function endPinch(e) {
      if (pinchState && (!e.touches || e.touches.length < 2)) pinchState = null;
    }
    editorCanvasWrap.addEventListener("touchend", endPinch);
    editorCanvasWrap.addEventListener("touchcancel", endPinch);

    window.addEventListener("resize", () => {
      if (!imgEditor.hidden) {
        fitEditorToScreen();
        renderCropBox();
      }
    });

    function openImageEditor(index) {
      if (!attachQueue[index]) return;
      editorQueueIndex = index;
      editorOriginalDataUrl = attachQueue[index].dataUrl;
      editorUndoStack = [];
      cropRect = null;
      cropBox.hidden = true;
      setEditorTool("pen");
      penWidth.value = "6";
      editorPenWidth = 6;
      penWidthLabel.textContent = "6px";
      imgEditor.hidden = false;
      loadImageIntoCanvas(editorOriginalDataUrl).then(() => {
        // Wrap must be visible (imgEditor.hidden = false) before measuring
        // it for fit-to-screen sizing, hence this runs after unhiding.
        fitEditorToScreen();
      });
    }

    function closeImageEditor() {
      imgEditor.hidden = true;
      editorQueueIndex = -1;
      editorDrawing = false;
      cropDrag = null;
      pinchState = null;
    }
    editorClose.addEventListener("click", closeImageEditor);

    editorReset.addEventListener("click", () => {
      if (!editorOriginalDataUrl) return;
      editorUndoStack = [];
      cropRect = null;
      cropBox.hidden = true;
      loadImageIntoCanvas(editorOriginalDataUrl).then(() => {
        fitEditorToScreen();
      });
    });

    editorSave.addEventListener("click", () => {
      if (editorQueueIndex < 0 || !attachQueue[editorQueueIndex]) {
        closeImageEditor();
        return;
      }
      const dataUrl = editorCanvas.toDataURL("image/png");
      attachQueue[editorQueueIndex].dataUrl = dataUrl;
      renderAttachPreview();
      updateComposerState();
      saveCurrentTierDraft();
      closeImageEditor();
    });

    // ---- Coordinate mapping: display (CSS px, as rendered) -> canvas pixels ----
    function displayToCanvasPoint(clientX, clientY) {
      const rect = editorCanvas.getBoundingClientRect();
      const scaleX = editorCanvas.width / rect.width;
      const scaleY = editorCanvas.height / rect.height;
      return {
        x: (clientX - rect.left) * scaleX,
        y: (clientY - rect.top) * scaleY,
      };
    }

    function eventPoint(e) {
      if (e.touches && e.touches.length > 0) {
        return { clientX: e.touches[0].clientX, clientY: e.touches[0].clientY };
      }
      return { clientX: e.clientX, clientY: e.clientY };
    }

    // ---- Pen tool ----
    function drawSegment(from, to) {
      editorCtx.strokeStyle = editorPenColor;
      editorCtx.lineWidth = editorPenWidth;
      editorCtx.lineCap = "round";
      editorCtx.lineJoin = "round";
      editorCtx.beginPath();
      editorCtx.moveTo(from.x, from.y);
      editorCtx.lineTo(to.x, to.y);
      editorCtx.stroke();
    }

    function drawDot(pt) {
      editorCtx.fillStyle = editorPenColor;
      editorCtx.beginPath();
      editorCtx.arc(pt.x, pt.y, editorPenWidth / 2, 0, Math.PI * 2);
      editorCtx.fill();
    }

    // ---- Crop box rendering (positions cropBox in DISPLAY coordinates over the canvas) ----
    function renderCropBox() {
      if (!cropRect) {
        cropBox.hidden = true;
        return;
      }
      const rect = editorCanvas.getBoundingClientRect();
      const wrapRect = editorCanvasInner.getBoundingClientRect();
      const scaleX = rect.width / editorCanvas.width;
      const scaleY = rect.height / editorCanvas.height;
      const left = (rect.left - wrapRect.left) + cropRect.x * scaleX;
      const top = (rect.top - wrapRect.top) + cropRect.y * scaleY;
      cropBox.style.left = left + "px";
      cropBox.style.top = top + "px";
      cropBox.style.width = (cropRect.w * scaleX) + "px";
      cropBox.style.height = (cropRect.h * scaleY) + "px";
      cropBox.hidden = false;
    }

    function clampCropRect(r) {
      let { x, y, w, h } = r;
      if (w < 0) { x += w; w = -w; }
      if (h < 0) { y += h; h = -h; }
      x = Math.max(0, Math.min(x, editorCanvas.width));
      y = Math.max(0, Math.min(y, editorCanvas.height));
      w = Math.max(1, Math.min(w, editorCanvas.width - x));
      h = Math.max(1, Math.min(h, editorCanvas.height - y));
      return { x, y, w, h };
    }

    function handleAt(clientX, clientY) {
      const target = document.elementFromPoint(clientX, clientY);
      const handleEl = target && target.closest ? target.closest(".crop-handle") : null;
      return handleEl ? handleEl.dataset.handle : null;
    }

    function pointerDown(e) {
      // Middle-click (or middle-finger... i.e. button 1) always pans,
      // regardless of which tool (pen/crop) is active — this mirrors how
      // most image editors reserve the middle mouse button for panning so
      // it never has to fight with the active tool's own click behavior.
      if (e.button === 1) {
        e.preventDefault();
        panDrag = { startX: e.clientX, startY: e.clientY, startPanX: editorPanX, startPanY: editorPanY };
        return;
      }

      // Two-plus finger touches are pinch-zoom gestures, handled separately
      // on editorCanvasWrap — bail out here so a pinch-start doesn't also
      // begin a pen stroke or crop drag from its first touch point.
      if (e.touches && e.touches.length > 1) return;

      const p = eventPoint(e);
      const canvasPt = displayToCanvasPoint(p.clientX, p.clientY);

      if (editorTool === "pen") {
        e.preventDefault();
        pushUndo();
        editorDrawing = true;
        editorLastPoint = canvasPt;
        drawDot(canvasPt);
        return;
      }

      if (editorTool === "crop") {
        e.preventDefault();
        const handle = handleAt(p.clientX, p.clientY);
        if (handle && cropRect) {
          cropDrag = { mode: "handle", handle, orig: { ...cropRect } };
          return;
        }
        if (cropRect &&
          canvasPt.x >= cropRect.x && canvasPt.x <= cropRect.x + cropRect.w &&
          canvasPt.y >= cropRect.y && canvasPt.y <= cropRect.y + cropRect.h) {
          cropDrag = { mode: "move", startX: canvasPt.x, startY: canvasPt.y, orig: { ...cropRect } };
          return;
        }
        cropDrag = { mode: "new", startX: canvasPt.x, startY: canvasPt.y };
        cropRect = { x: canvasPt.x, y: canvasPt.y, w: 0, h: 0 };
        renderCropBox();
      }
    }

    function pointerMove(e) {
      if (panDrag) {
        e.preventDefault();
        editorPanX = panDrag.startPanX + (e.clientX - panDrag.startX);
        editorPanY = panDrag.startPanY + (e.clientY - panDrag.startY);
        clampPan();
        applyZoomTransform();
        return;
      }

      if (e.touches && e.touches.length > 1) return; // pinch handled separately
      const p = eventPoint(e);
      const canvasPt = displayToCanvasPoint(p.clientX, p.clientY);

      if (editorTool === "pen" && editorDrawing) {
        e.preventDefault();
        drawSegment(editorLastPoint, canvasPt);
        editorLastPoint = canvasPt;
        return;
      }

      if (editorTool === "crop" && cropDrag) {
        e.preventDefault();
        if (cropDrag.mode === "new") {
          cropRect = clampCropRect({
            x: cropDrag.startX, y: cropDrag.startY,
            w: canvasPt.x - cropDrag.startX, h: canvasPt.y - cropDrag.startY,
          });
        } else if (cropDrag.mode === "move") {
          const dx = canvasPt.x - cropDrag.startX;
          const dy = canvasPt.y - cropDrag.startY;
          const o = cropDrag.orig;
          let nx = o.x + dx, ny = o.y + dy;
          nx = Math.max(0, Math.min(nx, editorCanvas.width - o.w));
          ny = Math.max(0, Math.min(ny, editorCanvas.height - o.h));
          cropRect = { x: nx, y: ny, w: o.w, h: o.h };
        } else if (cropDrag.mode === "handle") {
          const o = cropDrag.orig;
          let { x, y, w, h } = o;
          if (cropDrag.handle === "nw") { w = o.x + o.w - canvasPt.x; h = o.y + o.h - canvasPt.y; x = canvasPt.x; y = canvasPt.y; }
          else if (cropDrag.handle === "ne") { w = canvasPt.x - o.x; h = o.y + o.h - canvasPt.y; y = canvasPt.y; }
          else if (cropDrag.handle === "sw") { w = o.x + o.w - canvasPt.x; h = canvasPt.y - o.y; x = canvasPt.x; }
          else if (cropDrag.handle === "se") { w = canvasPt.x - o.x; h = canvasPt.y - o.y; }
          cropRect = clampCropRect({ x, y, w, h });
        }
        renderCropBox();
      }
    }

    function pointerUp() {
      editorDrawing = false;
      editorLastPoint = null;
      cropDrag = null;
      panDrag = null;
    }

    editorCanvas.addEventListener("mousedown", pointerDown);
    window.addEventListener("mousemove", pointerMove);
    window.addEventListener("mouseup", pointerUp);
    // Suppress the browser's native middle-click autoscroll/context menu so
    // it doesn't fire alongside (or instead of) the pan handled above.
    editorCanvas.addEventListener("auxclick", (e) => { if (e.button === 1) e.preventDefault(); });
    editorCanvas.addEventListener("touchstart", pointerDown, { passive: false });
    window.addEventListener("touchmove", pointerMove, { passive: false });
    window.addEventListener("touchend", pointerUp);

    // Crop handles need pointerdown too, since elementFromPoint resolves to
    // the handle element itself (crop-handle has pointer-events:auto).
    cropBox.addEventListener("mousedown", (e) => { if (e.target.closest(".crop-handle")) pointerDown(e); });
    cropBox.addEventListener("touchstart", (e) => { if (e.target.closest(".crop-handle")) pointerDown(e); }, { passive: false });

    applyCropBtn.addEventListener("click", () => {
      if (!cropRect || cropRect.w < 2 || cropRect.h < 2) return;
      pushUndo();
      const { x, y, w, h } = cropRect;
      const cropped = editorCtx.getImageData(x, y, w, h);
      editorCanvas.width = w;
      editorCanvas.height = h;
      editorCtx.putImageData(cropped, 0, 0);
      cropRect = null;
      cropBox.hidden = true;
      // Pixel dimensions changed — recompute the fit size so the cropped
      // result isn't rendered at the old (larger) canvas's CSS size.
      fitEditorToScreen();
    });
    // ---------- End image editor ----------

    // Send button enablement + mic visibility follow what's being composed:
    // typing hides the voice button (voice becomes irrelevant while you're
    // writing), and the send button stays inert until there's text or at
    // least one queued image.
    function updateComposerState() {
      const hasText = !!textInput.value.trim();
      const hasImages = attachQueue.length > 0;
      const hasTextFiles = textFileQueue.length > 0;
      sendText.disabled = !(hasText || hasImages || hasTextFiles);
      if (micBtn) {
        micBtn.classList.toggle("typing-hidden", hasText && !recording);
      }
    }

    textInput.addEventListener("input", () => {
      textInput.style.height = "auto";
      textInput.style.height = Math.min(textInput.scrollHeight, 120) + "px";
      updateComposerState();
      saveCurrentTierDraft();
    });

    textInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        submitText();
      }
    });

    sendText.addEventListener("click", submitText);

    // Builds the POST /api/text payload. Kept separate from the send so a
    // retry re-sends byte-identical content — text, images and file
    // attachments exactly as the user first composed them.
    function buildTextBody(message, images, textFiles, tier) {
      const body = { message, tier };
      if (images && images.length > 0) {
        body.images = images.map((item) => item.dataUrl);
      }
      if (textFiles && textFiles.length > 0) {
        body.text_files = textFiles.map((item) => ({
          data: item.dataUrl,
          filename: item.filename,
        }));
      }
      return body;
    }

    // The one place a text turn is actually sent. Both the composer send and
    // a Retry click go through here, so a retry can never drift from the
    // original request. `userEntry` is the bubble the message already lives
    // in — on a retry we re-use that same bubble rather than stacking a
    // duplicate one.
    //
    // Owns the whole in-flight presentation: the Stop button, the thinking
    // indicator, and the failure marking. Returns a small result so callers
    // don't have to reason about which branch was taken.
    async function sendTextTurn(userEntry, payload) {
      const requestTier = payload.tier;

      // A retry starts from a clean slate: no red border, no "Not sent",
      // no stale retry button — just the message and its Stop button again.
      clearEntryFailed(userEntry);
      const removeStop = addStopButton(userEntry, requestTier);
      let keepStop = false; // a question card leaves the turn running behind it
      showThinking(requestTier);

      const onRetryableFailure = (reason) => {
        // Register just the payload (and which tier owns it). No DOM node and
        // no closure are stored: the chat log persists as innerHTML and a tier
        // switch replaces the element, so retryFailedSend() resolves the
        // bubble fresh from the id when the button is actually clicked.
        if (userEntry.dataset.turnId) {
          failedSends[userEntry.dataset.turnId] = { payload, tier: requestTier };
        }
        markEntryFailed(userEntry, {
          retryable: true,
          turnId: userEntry.dataset.turnId,
          tier: requestTier,
        });
        if (reason === "offline") {
          // The toast IS the connection report now. It used to be followed by
          // two more lines painting #statusDot red, and those are gone with the
          // dot - so this branch deliberately keeps its toast and loses nothing
          // else, which is why the block was narrowed rather than deleted.
          notify("error", "Couldn't reach Perla. Check the connection.");
        }
      };

      try {
        const res = await fetch(CONFIG.ENDPOINT + CONFIG.TEXT_PATH, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: "Bearer " + authToken,
          },
          body: JSON.stringify(payload),
        });
        const data = await res.json();
        if (!res.ok) {
          if (res.status === 401) {
            // Session expired, not a failed send — nothing to retry, the
            // lock screen takes it from here.
            relockSession();
            return { ok: false, retryable: false };
          }
          if (res.status === 400 && data.error) {
            // Every attached file was rejected and there was nothing else
            // to send (handle_text only 400s here if message/images/text
            // attachments all ended up empty) — surface why, same tone as
            // any other inline system note.
            notify("error", data.error);
          } else if (res.status === 403 && data.error) {
            notify("error", data.error);
          } else {
            throw new Error("request failed");
          }
          // 400/403 are deterministic — the identical request fails
          // identically — so mark it failed but offer no Retry.
          markEntryFailed(userEntry, { retryable: false, tier: requestTier });
          return { ok: false, retryable: false };
        }
        if (data.confirm_required) {
          // Destructive-keyword trip-wire (is_destructive server-side) —
          // stop here and render a Confirm/Reject bubble instead of
          // treating data.text as a normal reply. `data.action` is the
          // ORIGINAL message text to re-send with confirm:true if the
          // user actually wants to proceed.
          addConfirmationEntry(data.text || "About to execute a potentially destructive action.", data.action, requestTier);
          return { ok: false, pending: true };
        }
        if (data.question_required) {
          // The model paused its turn to ask a (multiple choice) question —
          // render an answer card instead of a reply; the daemon keeps the
          // turn open and returns the real reply on /api/question. The turn
          // is STILL running behind that card, so the Stop button stays put
          // (that's exactly when you want it — the question can be skipped
          // via its own button, or the whole thing stopped with this one).
          addQuestionEntry(data, requestTier);
          keepStop = true;
          return;
        }
        if (data.permission_required) {
          // A tool wants approval (typically to touch a path outside the
          // working directory). Same shape as a question: the turn stays open
          // behind the card and the real reply comes back on /api/permission,
          // so the Stop button stays too.
          addPermissionEntry(data, requestTier);
          keepStop = true;
          return;
        }
        if (data.file_warnings && data.file_warnings.length > 0) {
          // Non-fatal: some attached files were dropped, but the rest of
          // the message (other files, and/or typed text) still went
          // through — surface the reason without blocking the actual reply.
          notify("error", data.file_warnings.join(" · "));
        }
        renderReplyResult(data, requestTier);
        return { ok: true };
      } catch (e) {
        // Network error, timeout, or a non-JSON body — the message may or
        // may not have reached Perla, so it's the ambiguous case where a
        // Retry is genuinely useful.
        onRetryableFailure("offline");
        return { ok: false, retryable: true };
      } finally {
        hideThinking(requestTier);
        if (!keepStop) removeStop();
      }
    }

    // Indeterminate upload state.
    //
    // The message body is one JSON fetch with the file inlined as a data URL,
    // so there is no progress event to read and no honest percentage to show.
    // What we can show is that the attachments in the just-sent entry are still
    // in flight, which is what the reference's "Uploading: 64%" row is really
    // communicating. The typed meta is restored when the turn settles, so the
    // type·size line comes back rather than leaving "Uploading…" on a delivered
    // attachment forever.
    function setAttachmentsUploading(entry, on) {
      if (!entry) return;
      const rows = entry.querySelectorAll(".attach-file-chip");
      rows.forEach((row) => {
        const meta = row.querySelector(".attach-file-meta");
        if (!meta) return;
        if (on) {
          if (meta.dataset.idleMeta == null) meta.dataset.idleMeta = meta.textContent;
          meta.textContent = "Uploading…";
          row.classList.add("is-uploading");
        } else {
          if (meta.dataset.idleMeta != null) {
            meta.textContent = meta.dataset.idleMeta;
            delete meta.dataset.idleMeta;
          }
          row.classList.remove("is-uploading");
        }
      });
      entry.querySelectorAll(".attach-thumb").forEach((card) => {
        card.classList.toggle("is-uploading", !!on);
      });
    }

    async function submitText() {
      const message = textInput.value.trim();
      const images = attachQueue;
      const textFiles = textFileQueue;
      if (!message && images.length === 0 && textFiles.length === 0) return;

      // One combined bubble: file chips, then images, then the typed text —
      // attachments above the message content, not as separate bubbles
      // below it.
      const userEntry = addUserMessageEntry(message, images, textFiles);

      textInput.value = "";
      textInput.style.height = "auto";
      attachQueue = [];
      textFileQueue = [];
      renderAttachPreview();
      updateComposerState();
      clearCurrentTierDraft();

      if (!CONFIG.ENDPOINT) {
        notify("error", "Not linked to Perla yet, set CONFIG.ENDPOINT.");
        // Nothing was sent, so the message is as undelivered as a failed
        // one — but Retry can't help until an endpoint exists, so it's
        // marked without a button.
        markEntryFailed(userEntry, { retryable: false, tier: activeTier });
        return;
      }

      const requestTier = activeTier; // capture now — activeTier may change before the reply arrives
      // Only worth showing when there is something to upload; a text-only
      // message is not "uploading" anything.
      const hasAttachments = images.length > 0 || textFiles.length > 0;
      if (hasAttachments) setAttachmentsUploading(userEntry, true);
      try {
        await sendTextTurn(userEntry, buildTextBody(message, images, textFiles, requestTier));
      } finally {
        if (hasAttachments) setAttachmentsUploading(userEntry, false);
      }
    }

    // ---------- Voice recording → draft (WhatsApp-style) ----------
    const micBtn = document.getElementById("micBtn");
    const micTimer = document.getElementById("micTimer");
    const composerFooter = document.getElementById("composerFooter");
    const voiceDraftEl = document.getElementById("voiceDraft");
    const voiceDraftWave = document.getElementById("voiceDraftWave");
    const voiceDraftTime = document.getElementById("voiceDraftTime");
    const voiceDraftDiscard = document.getElementById("voiceDraftDiscard");
    const voiceDraftStop = document.getElementById("voiceDraftStop");
    const voiceDraftPlay = document.getElementById("voiceDraftPlay");
    const voiceDraftSend = document.getElementById("voiceDraftSend");
    const voiceDraftInterrupt = document.getElementById("voiceDraftInterrupt");

    const VOICE_ICONS = {
      play: '<svg viewBox="0 0 22 22" width="13" height="13"><polygon points="6 3 19 11 6 19" fill="currentColor" /></svg>',
      pause: '<svg viewBox="0 0 22 22" width="13" height="13"><rect x="6" y="4" width="3.4" height="14" rx="1.6" fill="currentColor" /><rect x="12.6" y="4" width="3.4" height="14" rx="1.6" fill="currentColor" /></svg>',
    };

    // Turns either the daemon's full URL ("/api/voice/<name>") or the
    // history log's bare filename ("<name>.webm") into a fetchable URL.
    function voiceApiUrl(value) {
      if (!value) return null;
      if (/^\/(api\/voice\/|api\/files\/)/.test(value)) return CONFIG.ENDPOINT + value;
      return CONFIG.ENDPOINT + "/api/voice/" + encodeURIComponent(value.split("/").pop());
    }

    let mediaRecorder = null;
    let mediaStream = null;
    let audioChunks = [];
    let recording = false;
    let recordStart = 0;
    let timerInterval = null;
    let draftState = "idle";    // idle | recording | draft | sending
    let voiceDraftBlob = null;
    let voiceDraftBars = null;
    let voiceDraftUrl = null;
    let voiceDraftAudio = null;
    let discardAfterStop = false;
    let liveWaveRaf = null;
    let activeVoiceAudio = null;
    let micAnalyserCtx = null;
    let micAnalyserNode = null;
    let micSourceNode = null;

    function formatDur(sec) {
      if (!isFinite(sec) || sec < 0) sec = 0;
      const m = Math.floor(sec / 60);
      const s = Math.floor(sec % 60);
      return m + ":" + String(s).padStart(2, "0");
    }

    // Renders `bars` (0..1 array) as the heights of child <i> elements.
    // `progress01` colors the already-played portion brass, the rest faint.
    function renderBarsInto(waveEl, bars, progress01) {
      while (waveEl.firstChild) waveEl.removeChild(waveEl.firstChild);
      if (!bars || !bars.length) return;
      const p = Math.max(0, Math.min(1, progress01 || 0));
      bars.forEach((val, i) => {
        const bar = document.createElement("i");
        bar.style.height = Math.max(8, Math.round(val * 100)) + "%";
        bar.style.background = i / bars.length <= p ? "rgba(201, 123, 141, 0.95)" : "rgba(201, 123, 141, 0.28)";
        waveEl.appendChild(bar);
      });
    }

    async function computeWaveBars(blob, n) {
      const count = n || 44;
      try {
        const buf = await blob.arrayBuffer();
        const Ctx = window.AudioContext || window.webkitAudioContext;
        if (!micAnalyserCtx) micAnalyserCtx = new Ctx();
        const decoded = await micAnalyserCtx.decodeAudioData(buf);
        const ch = decoded.getChannelData(0);
        const step = Math.max(1, Math.floor(ch.length / count));
        const bars = [];
        let overallMax = 0;
        for (let i = 0; i < count; i++) {
          let v = 0;
          const end = Math.min(ch.length, (i + 1) * step);
          for (let j = i * step; j < end; j++) {
            const a = Math.abs(ch[j]);
            if (a > v) v = a;
          }
          bars.push(v);
          if (v > overallMax) overallMax = v;
        }
        if (overallMax > 0) {
          for (let i = 0; i < bars.length; i++) {
            bars[i] = Math.max(0.08, Math.min(1, bars[i] / overallMax));
          }
        }
        return bars;
      } catch (e) {
        return Array(count).fill(0.5);
      }
    }

    function setDraftState(state) {
      draftState = state;
      composerFooter.classList.toggle("voice-drafting", state !== "idle");
      voiceDraftEl.hidden = state === "idle";
      voiceDraftEl.classList.toggle("recording", state === "recording");
      voiceDraftStop.hidden = state !== "recording";
      voiceDraftPlay.hidden = state !== "draft";
      voiceDraftSend.hidden = state !== "draft";
      voiceDraftInterrupt.hidden = state !== "sending";
      if (state !== "recording" && liveWaveRaf) {
        cancelAnimationFrame(liveWaveRaf);
        liveWaveRaf = null;
      }
      updateComposerState();
    }

    micBtn.addEventListener("click", async () => {
      if (draftState === "idle") {
        await startRecording();
      } else if (draftState === "recording") {
        stopRecording(true);
      }
    });

    async function startRecording() {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        mediaStream = stream;
        mediaRecorder = new MediaRecorder(stream);
        audioChunks = [];
        mediaRecorder.ondataavailable = (e) => audioChunks.push(e.data);
        mediaRecorder.onstop = () => {
          stream.getTracks().forEach((t) => t.stop());
          handleRecordingComplete();
        };
        mediaRecorder.start();
        recording = true;
        recordStart = Date.now();
        micBtn.classList.add("recording");
        setupLiveWave();
        setDraftState("recording");
        micTimer.textContent = "";
        timerInterval = setInterval(updateTimer, 250);
        updateTimer();
      } catch (e) {
        micTimer.textContent = "Microphone access denied";
      }
    }

    // Stops the recorder; `keep` drafts the audio in the composer so it can
    // be replayed or sent, `!keep` discards the take entirely.
    function stopRecording(keep) {
      if (!mediaRecorder || !recording) return;
      discardAfterStop = !keep;
      mediaRecorder.stop();
      recording = false;
      micBtn.classList.remove("recording");
      clearInterval(timerInterval);
      timerInterval = null;
      updateComposerState();
    }

    function updateTimer() {
      const elapsed = Math.floor((Date.now() - recordStart) / 1000);
      voiceDraftTime.textContent = formatDur(elapsed);
    }

    // Live waveform: pull time-domain samples from the mic analyser and
    // grow the draft bar's <i> elements in real time while recording.
    function setupLiveWave() {
      try {
        const Ctx = window.AudioContext || window.webkitAudioContext;
        if (!micAnalyserCtx) micAnalyserCtx = new Ctx();
        if (micAnalyserCtx.state === "suspended") micAnalyserCtx.resume().catch(() => {});
        micSourceNode = micAnalyserCtx.createMediaStreamSource(mediaStream);
        micAnalyserNode = micAnalyserCtx.createAnalyser();
        micAnalyserNode.fftSize = 128;
        micSourceNode.connect(micAnalyserNode);
      } catch (e) {
        micAnalyserNode = null;
      }
      const n = 44;
      const bars = [];
      voiceDraftWave.innerHTML = "";
      for (let i = 0; i < n; i++) {
        const bar = document.createElement("i");
        bar.style.height = "10%";
        voiceDraftWave.appendChild(bar);
        bars.push(bar);
      }
      let data = null;
      const loop = () => {
        if (draftState !== "recording") return;
        if (micAnalyserNode) {
          if (!data) data = new Uint8Array(micAnalyserNode.frequencyBinCount);
          micAnalyserNode.getByteTimeDomainData(data);
          for (let i = 0; i < n; i++) {
            const idx = Math.floor((i / n) * data.length);
            const v = Math.abs((data[idx] - 128) / 128);
            bars[i].style.height = Math.max(10, Math.round(v * 95)) + "%";
            bars[i].style.background = v > 0.22 ? "rgba(201, 123, 141, 0.95)" : "rgba(201, 123, 141, 0.35)";
          }
        }
        liveWaveRaf = requestAnimationFrame(loop);
      };
      liveWaveRaf = requestAnimationFrame(loop);
    }

    function teardownVoiceAnalyser() {
      try {
        if (micSourceNode) micSourceNode.disconnect();
        if (micAnalyserNode) micAnalyserNode.disconnect();
      } catch (e) {}
      micSourceNode = null;
      micAnalyserNode = null;
      if (liveWaveRaf) {
        cancelAnimationFrame(liveWaveRaf);
        liveWaveRaf = null;
      }
    }

    async function handleRecordingComplete() {
      const blob = new Blob(audioChunks, { type: "audio/webm" });
      audioChunks = [];
      const keep = !discardAfterStop;
      discardAfterStop = false;
      teardownVoiceAnalyser();

      if (!keep || blob.size === 0) {
        clearVoiceDraft();
        return;
      }

      // Recording drops into the message box as a draft — user listens to
      // it, then sends or discards. Nothing is auto-sent.
      voiceDraftBlob = blob;
      voiceDraftBars = null;
      voiceDraftUrl = URL.createObjectURL(blob);
      voiceDraftAudio = new Audio(voiceDraftUrl);
      voiceDraftAudio.playBtn = voiceDraftPlay;
      voiceDraftAudio.addEventListener("loadedmetadata", () => {
        if (isFinite(voiceDraftAudio.duration) && voiceDraftAudio.duration > 0) {
          voiceDraftTime.textContent = formatDur(voiceDraftAudio.duration);
        }
      });
      voiceDraftAudio.addEventListener("timeupdate", () => {
        if (voiceDraftBars && voiceDraftAudio.duration) {
          renderBarsInto(voiceDraftWave, voiceDraftBars, voiceDraftAudio.currentTime / voiceDraftAudio.duration);
        }
      });
      voiceDraftAudio.addEventListener("ended", () => {
        voiceDraftPlay.innerHTML = VOICE_ICONS.play;
      });

      setDraftState("draft");
      voiceDraftTime.textContent = formatDur(0);
      drawDraftBars();
    }

    function drawDraftBars() {
      if (!voiceDraftBlob) return;
      computeWaveBars(voiceDraftBlob, 44).then((bars) => {
        voiceDraftBars = bars;
        renderBarsInto(voiceDraftWave, bars, 0);
      }).catch(() => {});
    }

    // Plays a voice audio element, pausing any other playback (draft,
    // chat bubbles, or a TTS reply) so only one sound is audible.
    function playVoiceAudio(audio, playBtn) {
      if (!audio) return;
      if (audio.paused) {
        if (activeVoiceAudio && activeVoiceAudio !== audio) {
          activeVoiceAudio.pause();
          if (activeVoiceAudio.playBtn) activeVoiceAudio.playBtn.innerHTML = VOICE_ICONS.play;
        }
        if (responseAudio && !responseAudio.paused) responseAudio.pause();
        activeVoiceAudio = audio;
        if (playBtn) playBtn.innerHTML = VOICE_ICONS.pause;
        audio.play().catch(() => { if (playBtn) playBtn.innerHTML = VOICE_ICONS.play; });
      } else {
        audio.pause();
        if (playBtn) playBtn.innerHTML = VOICE_ICONS.play;
      }
    }

    voiceDraftPlay.addEventListener("click", () => playVoiceAudio(voiceDraftAudio, voiceDraftPlay));
    voiceDraftStop.addEventListener("click", () => stopRecording(true));
    voiceDraftDiscard.addEventListener("click", () => {
      if (draftState === "recording") {
        stopRecording(false);
      } else {
        clearVoiceDraft();
      }
    });
    voiceDraftSend.addEventListener("click", sendVoiceDraft);
    voiceDraftInterrupt.addEventListener("click", () => {
      voiceDraftInterrupt.disabled = true;
      interruptTurn(activeTier);
    });

    function clearVoiceDraft() {
      teardownVoiceAnalyser();
      clearInterval(timerInterval);
      timerInterval = null;
      recording = false;
      micBtn.classList.remove("recording");
      if (voiceDraftAudio) {
        voiceDraftAudio.pause();
        voiceDraftAudio = null;
      }
      voiceDraftBlob = null;
      voiceDraftBars = null;
      voiceDraftUrl = null;
      voiceDraftWave.innerHTML = "";
      setDraftState("idle");
      micTimer.textContent = "";
    }

    async function sendVoiceDraft() {
      if (draftState !== "draft" || !voiceDraftBlob) return;

      const requestTier = activeTier; // capture now — activeTier may change before the reply arrives
      const bars = voiceDraftBars || null;
      const fallbackUrl = voiceDraftUrl;

      setDraftState("sending");
      showThinking(requestTier);
      try {
        const form = new FormData();
        form.append("audio", voiceDraftBlob, "input.webm");
        form.append("tier", String(requestTier));

        const res = await fetch(CONFIG.ENDPOINT + CONFIG.VOICE_PATH, {
          method: "POST",
          headers: { Authorization: "Bearer " + authToken },
          body: form,
        });
        const data = await res.json();
        if (!res.ok) {
          if (res.status === 401) {
            relockSession();
            return;
          }
          if (res.status === 403 && data.error) {
            if (data.transcript) addEntry("user", "You", data.transcript, requestTier);
            notify("error", data.error);
          } else {
            throw new Error("request failed");
          }
          return;
        }

        clearVoiceDraft();

        // The user's turn renders as a voice message (audio bubble); the
        // transcript stays as a faint hint under the wave.
        let voiceEntry = null;
        if (data.transcript) {
          voiceEntry = addVoiceUserMessageEntry(data.transcript, data.voice || null, bars, requestTier, fallbackUrl);
        }
        if (data.confirm_required) {
          // Same trip-wire as text messages — the transcribed speech
          // matched a destructive keyword. Route confirm/reject through
          // the plain /api/text path (handle_voice has no confirm=true
          // parameter of its own); `action` here is the transcript text.
          addConfirmationEntry(data.text || "About to execute a potentially destructive action.", data.action, requestTier);
          return;
        }
        if (data.question_required) {
          // Same question flow as text messages — the model paused to ask
          // while processing the transcribed speech. The turn is still
          // running behind the card, so the Stop button moves onto this
          // message's meta row now that the bubble exists (the draft bar
          // it's currently in gets cleared by clearVoiceDraft above).
          if (voiceEntry) addStopButton(voiceEntry, requestTier);
          addQuestionEntry(data, requestTier);
          return;
        }
        if (data.permission_required) {
          if (voiceEntry) addStopButton(voiceEntry, requestTier);
          addPermissionEntry(data, requestTier);
          return;
        }
        renderReplyResult(data, requestTier);
      } catch (e) {
        // The toast is the whole of the report, as in sendTextTurn above.
        notify("error", "Couldn't reach Perla. Check the connection.");
        // Put the take back as a draft so the recording isn't lost.
        if (voiceDraftBlob) {
          setDraftState("draft");
          drawDraftBars();
        }
      } finally {
        hideThinking(requestTier);
        voiceDraftInterrupt.disabled = false;
      }
    }

    // Builds the playable voice widget: play button, waveform, duration.
    // `localAudio` (the just-recorded blob URL) is played directly when
    // available; otherwise the daemon's stored `audioUrl` is fetched with
    // the auth header so playback works after deploy. If nothing can be
    // fetched (e.g. the file was purged at midnight), `onUnavailable`
    // degrades the bubble to the transcript text.
    function buildVoiceWidget(opts) {
      const wrap = document.createElement("div");
      wrap.className = "voice-widget";

      const playBtn = document.createElement("button");
      playBtn.className = "voice-play";
      playBtn.setAttribute("aria-label", "Play voice message");
      playBtn.innerHTML = VOICE_ICONS.play;

      const wave = document.createElement("div");
      wave.className = "voice-wave";

      const durEl = document.createElement("span");
      durEl.className = "voice-duration";
      durEl.textContent = "0:00";

      wrap.append(playBtn, wave, durEl);

      let audioEl = null;
      let barsArr = (opts.bars && opts.bars.length) ? opts.bars : null;
      if (barsArr) {
        renderBarsInto(wave, barsArr, 0);
      } else {
        renderBarsInto(wave, Array(44).fill(0.25), 0);
      }

      function wireAudio(audio) {
        audio.playBtn = playBtn;
        audio.addEventListener("loadedmetadata", () => {
          if (isFinite(audio.duration) && audio.duration > 0) {
            durEl.textContent = formatDur(audio.duration);
          }
        });
        audio.addEventListener("timeupdate", () => {
          if (barsArr && audio.duration && barsArr.length) {
            renderBarsInto(wave, barsArr, audio.currentTime / audio.duration);
          }
        });
        audio.addEventListener("ended", () => {
          playBtn.innerHTML = VOICE_ICONS.play;
          if (barsArr && barsArr.length) renderBarsInto(wave, barsArr, 0);
        });
      }

      playBtn.addEventListener("click", () => playVoiceAudio(audioEl, playBtn));

      if (opts.localAudio) {
        audioEl = opts.localAudio;
        wireAudio(audioEl);
      } else if (opts.audioUrl) {
        fetch(opts.audioUrl, { headers: { Authorization: "Bearer " + authToken } })
          .then((res) => {
            if (!res.ok) throw new Error("voice fetch failed");
            return res.blob();
          })
          .then((blob) => {
            audioEl = new Audio(URL.createObjectURL(blob));
            wireAudio(audioEl);
            if (!barsArr) {
              computeWaveBars(blob, 44).then((b) => {
                barsArr = b;
                renderBarsInto(wave, b, 0);
              }).catch(() => {});
            }
          })
          .catch(() => {
            if (opts.onUnavailable) opts.onUnavailable();
          });
      } else if (opts.onUnavailable) {
        opts.onUnavailable();
      }

      return wrap;
    }

    // Renders the user's sent voice message as an audio bubble (instead of
    // the plain TTS text) in the live chat.
    function addVoiceUserMessageEntry(transcript, voiceUrl, bars, forTier, fallbackUrl) {
      const targetTier = forTier !== undefined ? forTier : activeTier;
      const live = isViewingTierChat(targetTier);
      if (live) {
        output.querySelectorAll(".welcome").forEach((w) => w.remove());
      }

      const entry = document.createElement("div");
      entry.className = "entry entry-user";
      const time = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

      const bubble = document.createElement("div");
      bubble.className = "entry-bubble voice-bubble";
      const fallbackToText = () => {
        bubble.classList.remove("voice-bubble");
        bubble.innerHTML = "";
        const p = document.createElement("p");
        p.textContent = transcript || "(voice message)";
        bubble.appendChild(p);
      };
      const widget = buildVoiceWidget({
        bars,
        audioUrl: voiceApiUrl(voiceUrl),
        localAudio: fallbackUrl ? new Audio(fallbackUrl) : null,
        onUnavailable: fallbackToText,
      });
      bubble.appendChild(widget);
      if (transcript) {
        const hint = document.createElement("div");
        hint.className = "voice-transcript";
        hint.textContent = transcript;
        bubble.appendChild(hint);
      }
      entry.appendChild(bubble);

      const meta = document.createElement("div");
      meta.className = "entry-meta";
      const ts = document.createElement("span");
      ts.className = "entry-time";
      ts.textContent = time;
      meta.appendChild(ts);
      entry.appendChild(meta);

      const wentLive = deliverEntry(entry, targetTier);
      if (wentLive) {
        output.scrollIntoView({ block: "end" });
        entry.scrollIntoView({ behavior: "smooth", block: "end" });
      }
      return entry;
    }

    // Same voice bubble rendered into the history panel for a past day.
    function addVoiceHistoryEntry(transcript, voicePath, timeStr) {
      const entry = document.createElement("div");
      entry.className = "entry entry-user";
      const bubble = document.createElement("div");
      bubble.className = "entry-bubble voice-bubble";
      const fallbackToText = () => {
        bubble.classList.remove("voice-bubble");
        bubble.innerHTML = "";
        const p = document.createElement("p");
        p.textContent = transcript || "(voice message)";
        bubble.appendChild(p);
      };
      const widget = buildVoiceWidget({
        bars: null,
        audioUrl: voiceApiUrl(voicePath),
        localAudio: null,
        onUnavailable: fallbackToText,
      });
      bubble.appendChild(widget);
      if (transcript) {
        const hint = document.createElement("div");
        hint.className = "voice-transcript";
        hint.textContent = transcript;
        bubble.appendChild(hint);
      }
      entry.appendChild(bubble);
      const meta = document.createElement("div");
      meta.className = "entry-meta";
      const ts = document.createElement("span");
      ts.className = "entry-time";
      ts.textContent = timeStr || "";
      meta.appendChild(ts);
      entry.appendChild(meta);
      output.appendChild(entry);
      return entry;
    }

    // ---------- History (view-only past conversations) ----------
    // The four surface rows used to be #appMenu items and keep their ids; only
    // their parent changed, so the handlers below are untouched. Looked up
    // through the sidebar rather than by id so that a row which ever moves again
    // is a one-line change here instead of four.
    const historyBtn = sidebar.querySelector('[data-destination="history"]');
    const historyPanel = document.getElementById("historyPanel");
    const historyDayBtn = document.getElementById("historyDayBtn");
    const historyDayBtnLabel = document.getElementById("historyDayBtnLabel");
    const historyDayMenu = document.getElementById("historyDayMenu");
    const historyTierFilter = document.getElementById("historyTierFilter");
    const historyStatus = document.getElementById("historyStatus");

    let daysLoaded = false;
    let historySelectedDate = "";   // "" | "YYYY-MM-DD"
    let historyEntriesCache = [];   // raw entries for the selected day, unfiltered
    let historyTierMode = "all";    // "all" | "1" | "2"
    let historyDaysCache = [];      // raw day-string list from /api/history/days

    function formatDayLabel(dateStr) {
      // dateStr is YYYY-MM-DD
      const [y, m, d] = dateStr.split("-").map(Number);
      const dt = new Date(y, m - 1, d);
      const today = new Date();
      const isToday = dt.toDateString() === today.toDateString();
      const yesterday = new Date(today);
      yesterday.setDate(today.getDate() - 1);
      const isYesterday = dt.toDateString() === yesterday.toDateString();
      const label = dt.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric", year: "numeric" });
      if (isToday) return { main: "Today", sub: label };
      if (isYesterday) return { main: "Yesterday", sub: label };
      return { main: label, sub: "" };
    }

    function closeHistoryDayMenu() {
      historyDayMenu.classList.remove("open");
      historyDayMenu.setAttribute("aria-hidden", "true");
      historyDayBtn.classList.remove("open");
      historyDayBtn.setAttribute("aria-expanded", "false");
    }

    function positionHistoryDayMenu() {
      const btnRect = historyDayBtn.getBoundingClientRect();
      const menuWidth = historyDayMenu.offsetWidth || 260;
      let left = btnRect.left;
      left = Math.min(left, window.innerWidth - menuWidth - 12);
      left = Math.max(left, 12);
      historyDayMenu.style.left = left + "px";
      historyDayMenu.style.top = (btnRect.bottom + 6) + "px";
    }

    function toggleHistoryDayMenu() {
      const opening = !historyDayMenu.classList.contains("open");
      if (opening) {
        closeAttachMenu();
        positionHistoryDayMenu();
      }
      historyDayMenu.classList.toggle("open", opening);
      historyDayMenu.setAttribute("aria-hidden", String(!opening));
      historyDayBtn.classList.toggle("open", opening);
      historyDayBtn.setAttribute("aria-expanded", String(opening));
    }

    window.addEventListener("resize", () => {
      if (historyDayMenu.classList.contains("open")) positionHistoryDayMenu();
    });

    historyDayBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      toggleHistoryDayMenu();
    });
    document.addEventListener("click", (e) => {
      if (
        historyDayMenu.classList.contains("open") &&
        !historyDayMenu.contains(e.target) &&
        e.target !== historyDayBtn &&
        !historyDayBtn.contains(e.target)
      ) {
        closeHistoryDayMenu();
      }
    });

    function renderHistoryDayMenu(days) {
      historyDayMenu.innerHTML = "";
      if (!days || days.length === 0) {
        const empty = document.createElement("div");
        empty.className = "empty history-day-menu-empty";
        empty.textContent = "No past conversations found.";
        historyDayMenu.appendChild(empty);
        return;
      }
      days.forEach((d) => {
        const { main, sub } = formatDayLabel(d);
        const opt = document.createElement("button");
        opt.className = "history-day-option" + (d === historySelectedDate ? " selected" : "");
        opt.setAttribute("role", "option");
        opt.innerHTML = `<span class="history-day-option-main">${main}</span>`
          + (sub ? `<span class="history-day-option-sub">${sub}</span>` : "");
        opt.addEventListener("click", () => {
          closeHistoryDayMenu();
          selectHistoryDay(d);
        });
        historyDayMenu.appendChild(opt);
      });
    }

    async function selectHistoryDay(date) {
      historySelectedDate = date;
      const { main } = formatDayLabel(date);
      historyDayBtnLabel.textContent = main;
      renderHistoryDayMenu(historyDaysCache);

      output.innerHTML = "";
      historyStatus.textContent = "Loading…";
      try {
        const res = await fetch(
          CONFIG.ENDPOINT + CONFIG.HISTORY_DAY_PATH + "?date=" + encodeURIComponent(date),
          { headers: { Authorization: "Bearer " + authToken } }
        );
        if (!res.ok) throw new Error("failed");
        const data = await res.json();
        historyEntriesCache = data.entries || [];
        renderFilteredHistoryEntries();
      } catch (e) {
        notify("error", "Couldn't load that day's conversation.");
        historyStatus.textContent = "";
      }
    }

    // Renders historyEntriesCache through the current tier filter —
    // separated from selectHistoryDay's fetch so switching the tier
    // filter (All/Tier 1/Tier 2) re-renders instantly from the already-
    // fetched day instead of re-fetching from the server.
    function renderFilteredHistoryEntries() {
      output.innerHTML = "";
      const filtered = historyTierMode === "all"
        ? historyEntriesCache
        : historyEntriesCache.filter((e) => String(e.tier) === historyTierMode);

      if (historyEntriesCache.length === 0) {
        notify("error", "No conversations logged that day.");
        historyStatus.textContent = "";
        return;
      }
      if (filtered.length === 0) {
        const tierLabel = historyTierMode === "1" ? "Tier 1" : "Tier 2";
        notify("error", `No ${tierLabel} conversations logged that day.`);
        historyStatus.textContent = `0 of ${historyEntriesCache.length} exchange${historyEntriesCache.length === 1 ? "" : "s"}`;
        return;
      }
      filtered.forEach((e) => renderHistoryEntry(e));
      historyStatus.textContent = filtered.length === historyEntriesCache.length
        ? `${filtered.length} exchange${filtered.length === 1 ? "" : "s"}`
        : `${filtered.length} of ${historyEntriesCache.length} exchange${historyEntriesCache.length === 1 ? "" : "s"}`;
    }

    historyTierFilter.addEventListener("click", (e) => {
      const btn = e.target.closest(".history-tier-btn");
      if (!btn) return;
      historyTierMode = btn.dataset.tier;
      historyTierFilter.querySelectorAll(".history-tier-btn").forEach((b) => {
        b.classList.toggle("active", b === btn);
      });
      if (historySelectedDate) renderFilteredHistoryEntries();
    });

    function closeHistoryPanel() {
      if (activeOverlay !== "history") return;
      activeOverlay = null;
      closeHistoryDayMenu();
      historyBtn.classList.remove("active");
      historyPanel.hidden = true;
      historySelectedDate = "";
      historyDayBtnLabel.textContent = "Select a day…";
      historyEntriesCache = [];
      historyTierMode = "all";
      historyTierFilter.querySelectorAll(".history-tier-btn").forEach((b) => {
        b.classList.toggle("active", b.dataset.tier === "all");
      });
      historyStatus.textContent = "";
      output.innerHTML = liveOutputHTML !== null ? liveOutputHTML : "";
      output.scrollIntoView({ block: "end" });
      updateTierButtonHighlight();
      updateComposerMode();
    }

    async function openHistoryPanel() {
      if (!CONFIG.ENDPOINT) {
        notify("error", "Not linked to Perla yet, set CONFIG.ENDPOINT.");
        return;
      }
      saveCurrentTierDraft();
      closeRemindersPanel();
      closeQuickActionsPanel();
      closeDrivePanel();

      activeOverlay = "history";
      historyBtn.classList.add("active");
      updateTierButtonHighlight();
      historyPanel.hidden = false;
      updateComposerMode();
      liveOutputHTML = output.innerHTML;
      output.innerHTML = "";
      notify("info", "Viewing past conversations [READ ONLY]");

      if (!daysLoaded) {
        historyStatus.textContent = "Loading days…";
        try {
          const res = await fetch(CONFIG.ENDPOINT + CONFIG.HISTORY_DAYS_PATH, {
            headers: { Authorization: "Bearer " + authToken },
          });
          if (!res.ok) throw new Error("failed");
          const data = await res.json();
          historyDaysCache = data.days || [];
          renderHistoryDayMenu(historyDaysCache);
          daysLoaded = true;
          historyStatus.textContent = historyDaysCache.length ? "" : "No past conversations found.";
        } catch (e) {
          historyStatus.textContent = "Couldn't load days.";
        }
      }
    }

    historyBtn.addEventListener("click", () => {
      if (activeOverlay === "history") {
        closeHistoryPanel();
      } else {
        openHistoryPanel();
      }
    });

    function renderHistoryEntry(e) {
      // Same visual shape as live chat: user bubble, then Perla's reply.
      // Tier 0 (direct system dispatch, no LLM) gets a subtler treatment
      // since it's a command echo rather than a conversational reply.
      const isTier0 = e.tier === 0;

      if (e.input) {
        if (e.voice) {
          addVoiceHistoryEntry(e.input, e.voice, e.time);
        } else {
          addHistoryEntry("user", "You", e.input, e.time);
        }
      }
      if (e.response) {
        const kind = isTier0 ? "perla entry-tier0" : "perla";
        addHistoryEntry(kind, "Perla", e.response, e.time);
      }
      if (e.file) {
        // History's file info only carries {filename, id} (from the log
        // line), not a ready-to-fetch URL — build the same URL shape the
        // live response would have carried so the viewer/download fetch works
        // identically for a replayed entry.
        const fileInfo = {
          filename: e.file.filename,
          url: `/api/files/${e.file.id}/${e.file.filename}`,
        };
        addHistoryFileEntry(fileInfo, e.time);
      }
    }

    function addHistoryEntry(kind, label, text, timeStr) {
      const entry = document.createElement("div");
      entry.className = "entry entry-" + kind.split(" ")[0];
      if (kind.includes("entry-tier0")) entry.classList.add("entry-tier0");
      const useMd = kind.startsWith("perla");
      entry.innerHTML =
        `<div class="entry-bubble">` + (useMd ? `<div class="prose"></div>` : `<p></p>`) + `</div>` +
        `<div class="entry-meta"><span class="entry-time">${timeStr || ""}</span></div>`;
      if (useMd) {
        const mdEl = entry.querySelector(".prose");
        mdEl.innerHTML = renderMarkdown(text);
        attachCodeBlockCopyButtons(mdEl);
      } else {
        entry.querySelector("p").textContent = text;
      }
      output.appendChild(entry);
      return entry;
    }

    function addHistoryFileEntry(fileInfo, timeStr) {
      const entry = document.createElement("div");
      entry.className = "entry entry-perla";
      entry.innerHTML = `<div class="entry-meta"><span class="entry-time">${timeStr || ""}</span></div>`;
      const attachments = document.createElement("div");
      attachments.className = "entry-attachments";
      const row = document.createElement("div");
      row.className = "attach-file-row";
      // (4) Perla's attachments go BELOW the message. This used to be
      // insertBefore(..., entry.firstChild), which put them above — the
      // mirror image of the user's own layout, and inconsistent with the
      // live send path, which already appends the bubble first.
      row.appendChild(buildDeliveredFileRow(fileInfo));
      attachments.appendChild(row);
      entry.appendChild(attachments);
      output.appendChild(entry);
      return entry;
    }

    // ---------- Reminders (view-only, status-grouped) ----------
    const remindersBtn = sidebar.querySelector('[data-destination="reminders"]');
    const remindersBar = document.getElementById("remindersBar");
    const remindersStatus = document.getElementById("remindersStatus");

    function closeRemindersPanel() {
      if (activeOverlay !== "reminders") return;
      activeOverlay = null;
      remindersBtn.classList.remove("active");
      remindersBar.hidden = true;
      remindersStatus.textContent = "";
      output.innerHTML = liveOutputHTML !== null ? liveOutputHTML : "";
      output.scrollIntoView({ block: "end" });
      updateTierButtonHighlight();
      updateComposerMode();
    }

    async function loadReminders() {
      remindersStatus.textContent = "Loading…";
      try {
        const res = await fetch(CONFIG.ENDPOINT + CONFIG.REMINDERS_PATH, {
          headers: { Authorization: "Bearer " + authToken },
        });
        if (res.status === 401) {
          relockSession();
          return;
        }
        if (!res.ok) throw new Error("failed");
        const data = await res.json();
        renderReminders(data);
        remindersStatus.textContent = "";
      } catch (e) {
        output.innerHTML = "";
        notify("error", "Couldn't load reminders.");
        remindersStatus.textContent = "";
      }
    }

    async function openRemindersPanel() {
      if (!CONFIG.ENDPOINT) {
        notify("error", "Not linked to Perla yet, set CONFIG.ENDPOINT.");
        return;
      }
      saveCurrentTierDraft();
      closeHistoryPanel();
      closeQuickActionsPanel();
      closeDrivePanel();

      activeOverlay = "reminders";
      remindersBtn.classList.add("active");
      updateTierButtonHighlight();
      remindersBar.hidden = false;
      updateComposerMode();
      liveOutputHTML = output.innerHTML;
      output.innerHTML = "";
      await loadReminders();
    }

    remindersBtn.addEventListener("click", () => {
      if (activeOverlay === "reminders") {
        closeRemindersPanel();
      } else {
        openRemindersPanel();
      }
    });

    // ---------- Reminders composer (manual add / cancel) ----------
    const reminderTextInput = document.getElementById("reminderTextInput");
    const reminderDueInput = document.getElementById("reminderDueInput");
    const reminderRepeatInput = document.getElementById("reminderRepeatInput");
    const reminderAddBtn = document.getElementById("reminderAddBtn");
    const reminderAddToggle = document.getElementById("reminderAddToggle");
    const reminderComposerMenu = document.getElementById("reminderComposerMenu");

    function toggleReminderComposer(forceOpen) {
      const willOpen = forceOpen !== undefined ? forceOpen : reminderComposerMenu.hidden;
      reminderComposerMenu.hidden = !willOpen;
      reminderAddToggle.classList.toggle("open", willOpen);
      reminderAddToggle.setAttribute("aria-expanded", String(willOpen));
      if (willOpen) reminderTextInput.focus();
    }

    reminderAddToggle.addEventListener("click", () => toggleReminderComposer());

    async function addReminder() {
      const text = reminderTextInput.value.trim();
      const due = reminderDueInput.value;
      if (!text) {
        notify("error", "Write what to remind you about.");
        return;
      }
      if (!due) {
        notify("error", "Pick a date and time for the reminder.");
        return;
      }
      reminderAddBtn.disabled = true;
      try {
        const res = await fetch(CONFIG.ENDPOINT + CONFIG.REMINDERS_PATH, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + authToken },
          body: JSON.stringify({
            action: "create",
            text: text,
            due: due,
            repeat: reminderRepeatInput.value || null,
          }),
        });
        if (res.status === 401) {
          relockSession();
          return;
        }
        const data = await res.json();
        if (res.ok && data.ok) {
          reminderTextInput.value = "";
          reminderDueInput.value = "";
          reminderRepeatInput.value = "";
          notify("success", "Reminder set");
          await loadReminders();
          toggleReminderComposer(false);
        } else {
          notify("error", data.error || "Couldn't set that reminder.");
        }
      } catch (e) {
        notify("error", "Couldn't set that reminder.");
      } finally {
        reminderAddBtn.disabled = false;
      }
    }

    reminderAddBtn.addEventListener("click", addReminder);
    reminderTextInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        addReminder();
      }
    });
    reminderDueInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        addReminder();
      }
    });

    async function cancelReminder(id) {
      try {
        const res = await fetch(CONFIG.ENDPOINT + CONFIG.REMINDERS_PATH, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + authToken },
          body: JSON.stringify({ action: "cancel", id: id }),
        });
        if (res.status === 401) {
          relockSession();
          return;
        }
        const data = await res.json();
        if (res.ok && data.ok) {
          notify("success", "Reminder removed.");
          await loadReminders();
        } else {
          notify("error", data.error || "Couldn't remove that reminder.");
        }
      } catch (e) {
        notify("error", "Couldn't remove that reminder.");
      }
    }

    // ---------- Drive (full filesystem browser rooted at $HOME) ----------
    // Unlike History/Reminders/Quick Actions (which repurpose `output` as
    // their content area), Drive needs its own grid+toolbar layout, so it
    // lives in a dedicated sibling panel (#drivePanel) that swaps places
    // with .content-wrap entirely while open — same "one overlay at a time"
    // rule as the others (closes History/Reminders/Quick Actions first),
    // and still counts as activeOverlay="drive" so tier switching and the
    // composer-mode logic treat it exactly like any other overlay. The
    // server-side denylist (sensitive dotfiles, key/credential stores —
    // see _drive_exclude_roots in perla-companion.py) is enforced entirely
    // on the backend; the client has no knowledge of what's hidden and
    // doesn't need any — an excluded path just never appears in a listing.
    const driveBtn = sidebar.querySelector('[data-destination="drive"]');
    const drivePanel = document.getElementById("drivePanel");
    const contentWrap = document.querySelector(".content-wrap");
    const driveBreadcrumbs = document.getElementById("driveBreadcrumbs");
    const driveBreadcrumbWrap = document.getElementById("driveBreadcrumbWrap");
    const driveBreadcrumbEditBtn = document.getElementById("driveBreadcrumbEditBtn");
    const drivePathEditRow = document.getElementById("drivePathEditRow");
    const drivePathEditInput = document.getElementById("drivePathEditInput");
    const driveGrid = document.getElementById("driveGrid");
    const driveStatus = document.getElementById("driveStatus");
    const driveNewFolderBtn = document.getElementById("driveNewFolderBtn");
    const driveNewFolderRow = document.getElementById("driveNewFolderRow");
    const driveNewFolderInput = document.getElementById("driveNewFolderInput");
    const driveNewFolderGo = document.getElementById("driveNewFolderGo");
    const driveNewFolderCancel = document.getElementById("driveNewFolderCancel");
    const driveUploadBtn = document.getElementById("driveUploadBtn");
    const driveUploadInput = document.getElementById("driveUploadInput");
    const driveViewToggleBtn = document.getElementById("driveViewToggleBtn");
    const driveHiddenToggleBtn = document.getElementById("driveHiddenToggleBtn");
    const drivePasteBtn = document.getElementById("drivePasteBtn");
    const driveClipboardBar = document.getElementById("driveClipboardBar");
    const driveClipboardLabel = document.getElementById("driveClipboardLabel");
    const driveClipboardCancel = document.getElementById("driveClipboardCancel");

    let driveCurrentPath = "";     // "" = root, else "Folder/Sub"
    let driveOpenMenuEl = null;    // currently-open per-item context menu, if any
    let driveEntriesCache = [];    // last-loaded entries, kept so toggling view mode
                                    // doesn't need a re-fetch

    // Cut/copy/paste clipboard — a single pending item (this UI is one-
    // at-a-time, not a multi-select), NOT persisted across a page reload
    // (sessionStorage would let a stale path survive a server restart/
    // filesystem change and paste could silently 404 or land somewhere
    // unexpected) — it only lives as long as the tab does, same lifetime
    // as e.g. an open context menu.
    let driveClipboard = null; // { path, name, mode: "copy" | "cut" }

    // View mode ("list" | "grid") and the hidden-files toggle both persist
    // across panel opens/closes within the session (and across a reload,
    // since sessionStorage survives that) — a person who switches to grid
    // view or turns on hidden files shouldn't have to redo it every time
    // they reopen System.
    let driveViewMode = sessionStorage.getItem("perla_drive_view_mode") || "list";
    let driveShowHidden = sessionStorage.getItem("perla_drive_show_hidden") === "1";

    // Extensions the composer can actually do something useful with once
    // added to chat — mirrors the server's DRIVE_ADD_TO_CHAT_EXTENSIONS
    // (TEXT_UPLOAD_EXTENSIONS ∪ DOCUMENT_UPLOAD_EXTENSIONS ∪ images). Kept
    // here purely so the "Add to chat" menu item can be hidden for files
    // that would just 400 — the server re-validates independently either way.
    const DRIVE_CHAT_EXTENSIONS = new Set([
      ...TEXT_FILE_EXTENSIONS,
      ...DOCUMENT_FILE_EXTENSIONS,
      ".png", ".jpg", ".jpeg",
    ]);

    // Extensions the in-browser file viewer (View action) can actually
    // render — plain text/code renders as <pre>, images render as <img>
    // (fetched via the authenticated download endpoint, same as any other
    // authenticated image elsewhere in this app since a bare <img src>
    // can't carry a bearer token). Document formats (PDF/DOCX/etc) aren't
    // viewable inline here — Download or Add to chat cover those instead.
    const DRIVE_VIEW_TEXT_EXTENSIONS = TEXT_FILE_EXTENSIONS;
    const DRIVE_VIEW_IMAGE_EXTENSIONS = new Set([".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"]);

    function driveSetViewMode(mode) {
      driveViewMode = mode;
      sessionStorage.setItem("perla_drive_view_mode", mode);
      driveGrid.className = mode === "grid" ? "drive-grid grid-mode" : "drive-list";
      driveViewToggleBtn.classList.toggle("active", mode === "grid");
      driveViewToggleBtn.setAttribute("aria-pressed", String(mode === "grid"));
      driveViewToggleBtn.title = mode === "grid" ? "List view" : "Grid view";
      renderDriveEntries();
    }

    function driveSetShowHidden(show) {
      driveShowHidden = show;
      sessionStorage.setItem("perla_drive_show_hidden", show ? "1" : "0");
      driveHiddenToggleBtn.classList.toggle("active", show);
      driveHiddenToggleBtn.setAttribute("aria-pressed", String(show));
      driveHiddenToggleBtn.title = show ? "Hide hidden files" : "Show hidden files";
      loadDrivePath(driveCurrentPath);
    }

    driveViewToggleBtn.addEventListener("click", () => {
      driveSetViewMode(driveViewMode === "grid" ? "list" : "grid");
    });
    driveHiddenToggleBtn.addEventListener("click", () => {
      driveSetShowHidden(!driveShowHidden);
    });

    function driveFileIcon(ext) {
      if (ext === ".png" || ext === ".jpg" || ext === ".jpeg" || ext === ".gif" || ext === ".webp") {
        return '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" width="20" height="20"><rect x="3" y="4" width="16" height="14" rx="2"/><circle cx="8" cy="9.5" r="1.6"/><path d="M3 15.5l4.5-4.5a1.5 1.5 0 0 1 2.1 0L15 16.5"/></svg>';
      }
      return GENERIC_FILE_ICON_SVG;
    }

    function driveFolderIcon() {
      return '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" width="22" height="22"><path d="M2.5 6a2 2 0 0 1 2-2h4.5l1.6 2H17.5a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/></svg>';
    }

    function driveFormatSize(bytes) {
      if (bytes == null) return "";
      if (bytes < 1024) return bytes + " B";
      if (bytes < 1024 * 1024) return Math.round(bytes / 1024) + " KB";
      return (bytes / (1024 * 1024)).toFixed(1) + " MB";
    }

    // "2026-09-09T06:07:01" -> "Sep 9, 2026" (or "Today" / "Yesterday"),
    // same relative-day convention formatDayLabel already uses for History.
    function driveFormatModified(iso) {
      if (!iso) return "";
      const dt = new Date(iso);
      if (isNaN(dt.getTime())) return "";
      const today = new Date();
      const isToday = dt.toDateString() === today.toDateString();
      const yesterday = new Date(today);
      yesterday.setDate(today.getDate() - 1);
      const isYesterday = dt.toDateString() === yesterday.toDateString();
      const timeStr = dt.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
      if (isToday) return `Today, ${timeStr}`;
      if (isYesterday) return `Yesterday, ${timeStr}`;
      return dt.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
    }

    function drivePathSegments(path) {
      return path ? path.split("/").filter(Boolean) : [];
    }

    function renderDriveBreadcrumbs(path) {
      driveBreadcrumbs.innerHTML = "";
      const rootBtn = document.createElement("button");
      rootBtn.className = "drive-crumb" + (path === "" ? " current" : "");
      rootBtn.innerHTML = '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" width="16" height="16"><rect x="2" y="4" width="18" height="14" rx="2"/><line x1="2" y1="13" x2="20" y2="13"/><circle cx="16" cy="16" r="1"/></svg><span>System</span>';
      rootBtn.disabled = path === "";
      rootBtn.addEventListener("click", () => loadDrivePath(""));
      driveBreadcrumbs.appendChild(rootBtn);

      const segments = drivePathSegments(path);
      segments.forEach((seg, i) => {
        const sep = document.createElement("span");
        sep.className = "drive-crumb-sep";
        sep.textContent = "›";
        driveBreadcrumbs.appendChild(sep);

        const isLast = i === segments.length - 1;
        const crumb = document.createElement("button");
        crumb.className = "drive-crumb" + (isLast ? " current" : "");
        crumb.textContent = seg;
        crumb.disabled = isLast;
        const targetPath = segments.slice(0, i + 1).join("/");
        crumb.addEventListener("click", () => loadDrivePath(targetPath));
        driveBreadcrumbs.appendChild(crumb);
      });
    }

    // ---------- Writable path bar ----------
    // The breadcrumb trail and the path input are two views of the same
    // "where am I" bar, never shown together — enterDrivePathEditMode
    // hides the crumbs and shows a text field pre-filled with the
    // CURRENT, already-valid path (never a rejected one, since a bad
    // submission never advances driveCurrentPath — see loadDrivePath).
    // Submitting re-resolves through the normal loadDrivePath flow, so
    // an incorrect path shows an inline error on the input itself AND
    // leaves the breadcrumb trail/grid pointed at wherever they already
    // were — a typo never leaves the UI in a broken or ambiguous state.
    function enterDrivePathEditMode() {
      drivePathEditInput.value = driveCurrentPath;
      drivePathEditRow.classList.remove("has-error");
      driveBreadcrumbs.hidden = true;
      driveBreadcrumbEditBtn.hidden = true;
      drivePathEditRow.hidden = false;
      drivePathEditInput.focus();
      drivePathEditInput.select();
    }

    function exitDrivePathEditMode() {
      drivePathEditRow.hidden = true;
      drivePathEditRow.classList.remove("has-error");
      driveBreadcrumbs.hidden = false;
      driveBreadcrumbEditBtn.hidden = false;
    }

    async function submitDrivePathEdit() {
      const typed = drivePathEditInput.value;
      // Accept a leading "~/" or "/" as harmless equivalents of "path
      // from home" — normalized away rather than rejected, since typing
      // a leading slash out of habit (from an absolute OS path) is the
      // single most likely mistake here, and there's nothing ambiguous
      // about what the person meant by it in a $HOME-rooted browser.
      const normalized = typed.trim().replace(/^~\/?/, "").replace(/^\/+/, "");
      const before = driveCurrentPath;
      await loadDrivePath(normalized);
      if (driveCurrentPath === before && normalized !== before) {
        // loadDrivePath left driveCurrentPath unchanged, which — given
        // the two differ — means the navigation was rejected (its own
        // catch already wrote the reason into driveStatus). Keep the
        // input open with an error outline so the person can fix the
        // typo in place instead of having to reopen the edit mode.
        drivePathEditRow.classList.add("has-error");
        drivePathEditInput.focus();
        return;
      }
      exitDrivePathEditMode();
    }

    driveBreadcrumbEditBtn.addEventListener("click", enterDrivePathEditMode);
    // Clicking the breadcrumb bar's own background (not a crumb button)
    // is a second, more discoverable way in — mirrors how a lot of
    // desktop file managers let you click empty space in the path bar
    // to start typing.
    driveBreadcrumbWrap.addEventListener("click", (e) => {
      if (e.target === driveBreadcrumbWrap || e.target === driveBreadcrumbs) {
        enterDrivePathEditMode();
      }
    });
    drivePathEditInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        submitDrivePathEdit();
      } else if (e.key === "Escape") {
        e.preventDefault();
        exitDrivePathEditMode();
      }
    });
    drivePathEditInput.addEventListener("blur", () => {
      // A blur while still showing an error means the person clicked
      // away without fixing it — quietly revert to the breadcrumb trail
      // rather than leaving an errored input stranded with no way to
      // dismiss it short of retyping the exact same broken path.
      setTimeout(() => {
        if (!drivePathEditRow.hidden) exitDrivePathEditMode();
      }, 150);
    });

    function closeDriveItemMenu() {
      if (driveOpenMenuEl) {
        driveOpenMenuEl.remove();
        driveOpenMenuEl = null;
      }
    }

    function openDriveItemMenu(anchorBtn, entry, entryPath) {
      closeDriveItemMenu();
      const menu = document.createElement("div");
      menu.className = "drive-item-menu";

      const ext = textFileExtension(entry.name);
      const canAddToChat = !entry.is_dir && DRIVE_CHAT_EXTENSIONS.has(ext);
      const canView = !entry.is_dir && (DRIVE_VIEW_TEXT_EXTENSIONS.has(ext) || DRIVE_VIEW_IMAGE_EXTENSIONS.has(ext));

      if (canView) {
        const view = document.createElement("button");
        view.innerHTML = '<span class="drive-item-menu-icon"><svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M1 11s3.9-7 10-7 10 7 10 7-3.9 7-10 7-10-7-10-7z"/><circle cx="11" cy="11" r="2.6"/></svg></span><span>View</span>';
        view.addEventListener("click", () => { closeDriveItemMenu(); driveViewFile(entryPath, entry.name); });
        menu.appendChild(view);
      }

      if (!entry.is_dir) {
        const dl = document.createElement("button");
        dl.innerHTML = '<span class="drive-item-menu-icon"><svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M11 3v12"/><polyline points="6 10 11 15 16 10"/><path d="M4 18h14"/></svg></span><span>Download</span>';
        dl.addEventListener("click", () => { closeDriveItemMenu(); driveDownload(entryPath, entry.name); });
        menu.appendChild(dl);
      }

      const copyBtn = document.createElement("button");
      copyBtn.innerHTML = '<span class="drive-item-menu-icon"><svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="8" y="8" width="11" height="11" rx="2"/><path d="M15 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h3"/></svg></span><span>Copy</span>';
      copyBtn.addEventListener("click", () => { closeDriveItemMenu(); driveSetClipboard(entryPath, entry.name, "copy"); });
      menu.appendChild(copyBtn);

      const cutBtn = document.createElement("button");
      cutBtn.innerHTML = '<span class="drive-item-menu-icon"><svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><circle cx="6" cy="6" r="2.5"/><circle cx="6" cy="16" r="2.5"/><line x1="19" y1="4" x2="8.5" y2="14.5"/><line x1="19" y1="18" x2="8.5" y2="7.5"/></svg></span><span>Cut</span>';
      cutBtn.addEventListener("click", () => { closeDriveItemMenu(); driveSetClipboard(entryPath, entry.name, "cut"); });
      menu.appendChild(cutBtn);

      if (canAddToChat) {
        const add = document.createElement("button");
        add.innerHTML = '<span class="drive-item-menu-icon"><svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4v14"/><path d="M4 11h14"/></svg></span><span>Add to chat</span>';
        add.addEventListener("click", () => { closeDriveItemMenu(); driveAddToChat(entryPath, entry.name); });
        menu.appendChild(add);
      }

      const del = document.createElement("button");
      del.className = "danger";
      del.innerHTML = '<span class="drive-item-menu-icon"><svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 19 6"/><path d="M8 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2m2 0v13a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V6h10z"/></svg></span><span>Delete</span>';
      del.addEventListener("click", () => { closeDriveItemMenu(); driveDeleteEntry(entryPath, entry.name); });
      menu.appendChild(del);

      document.body.appendChild(menu);
      const rect = anchorBtn.getBoundingClientRect();
      const menuWidth = menu.offsetWidth || 170;
      let left = Math.min(rect.left, window.innerWidth - menuWidth - 12);
      left = Math.max(left, 12);
      menu.style.left = left + "px";
      menu.style.top = (rect.bottom + 4) + "px";

      anchorBtn.classList.add("open");
      driveOpenMenuEl = menu;
    }

    document.addEventListener("click", (e) => {
      if (!driveOpenMenuEl) return;
      if (driveOpenMenuEl.contains(e.target) || e.target.closest(".drive-item-menu-btn")) return;
      document.querySelectorAll(".drive-item-menu-btn.open").forEach((b) => b.classList.remove("open"));
      closeDriveItemMenu();
    });

    function buildDriveItemCard(entry) {
      const entryPath = driveCurrentPath ? driveCurrentPath + "/" + entry.name : entry.name;
      const isCutSource = driveClipboard && driveClipboard.mode === "cut" && driveClipboard.path === entryPath;
      const card = document.createElement("div");
      card.className = "surface-raised drive-item"
        + (entry.is_dir ? " is-folder" : "")
        + (entry.is_hidden ? " is-hidden" : "")
        + (isCutSource ? " is-cut" : "");

      const icon = document.createElement("div");
      icon.className = "drive-item-icon";
      icon.innerHTML = entry.is_dir ? driveFolderIcon() : driveFileIcon(textFileExtension(entry.name));
      card.appendChild(icon);

      const name = document.createElement("div");
      name.className = "drive-item-name";
      name.textContent = entry.name;
      name.title = entry.name;
      card.appendChild(name);

      // Size + modified date. In list mode these sit as two right-aligned
      // columns before the menu button; in grid mode (see the
      // .grid-mode .drive-item-meta-col CSS override) the same markup
      // stacks vertically under the name instead.
      const metaCol = document.createElement("div");
      metaCol.className = "drive-item-meta-col";
      if (!entry.is_dir) {
        const size = document.createElement("div");
        size.className = "drive-item-meta";
        size.textContent = driveFormatSize(entry.size);
        metaCol.appendChild(size);
      }
      if (entry.modified) {
        const modified = document.createElement("div");
        modified.className = "drive-item-modified";
        modified.textContent = driveFormatModified(entry.modified);
        modified.title = entry.modified;
        metaCol.appendChild(modified);
      }
      if (metaCol.children.length) card.appendChild(metaCol);

      const menuBtn = document.createElement("button");
      menuBtn.className = "btn-icon btn-icon-28 btn-icon-square drive-item-menu-btn";
      menuBtn.setAttribute("aria-label", "More actions");
      menuBtn.title = "Actions";
      menuBtn.innerHTML = '<svg viewBox="0 0 22 22" fill="currentColor" width="14" height="14"><circle cx="11" cy="5" r="1.6"/><circle cx="11" cy="11" r="1.6"/><circle cx="11" cy="17" r="1.6"/></svg>';
      menuBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        if (driveOpenMenuEl && menuBtn.classList.contains("open")) {
          menuBtn.classList.remove("open");
          closeDriveItemMenu();
          return;
        }
        document.querySelectorAll(".drive-item-menu-btn.open").forEach((b) => b.classList.remove("open"));
        openDriveItemMenu(menuBtn, entry, entryPath);
      });
      card.appendChild(menuBtn);

      card.addEventListener("click", (e) => {
        if (e.target.closest(".drive-item-menu-btn")) return;
        if (entry.is_dir) {
          loadDrivePath(entryPath);
        } else {
          const ext = textFileExtension(entry.name);
          if (DRIVE_VIEW_TEXT_EXTENSIONS.has(ext) || DRIVE_VIEW_IMAGE_EXTENSIONS.has(ext)) {
            driveViewFile(entryPath, entry.name);
          } else {
            openDriveItemMenu(menuBtn, entry, entryPath);
          }
        }
      });

      return card;
    }

    function renderDriveEntries() {
      driveGrid.className = driveViewMode === "grid" ? "drive-grid grid-mode" : "drive-list";
      driveGrid.innerHTML = "";
      if (driveEntriesCache.length === 0) {
        const empty = document.createElement("div");
        empty.className = "empty drive-empty";
        empty.textContent = "This folder is empty.";
        driveGrid.appendChild(empty);
        return;
      }
      driveEntriesCache.forEach((entry) => driveGrid.appendChild(buildDriveItemCard(entry)));
    }

    async function loadDrivePath(path) {
      closeDriveItemMenu();
      const targetPath = (path || "").trim();
      driveNewFolderRow.hidden = true;
      driveStatus.textContent = "Loading…";
      try {
        const url = CONFIG.ENDPOINT + CONFIG.DRIVE_LIST_PATH
          + "?path=" + encodeURIComponent(targetPath)
          + "&hidden=" + (driveShowHidden ? "1" : "0");
        const res = await fetch(url, { headers: { Authorization: "Bearer " + authToken } });
        if (res.status === 401) { relockSession(); return; }
        const data = await res.json();
        if (!res.ok || !data.ok) throw new Error(data.error || "failed");
        // Only commit the navigation once the server has actually
        // confirmed the path exists and is listable — this is what keeps
        // a bad path typed into the path bar (or a stale breadcrumb) from
        // leaving the UI pointed at a folder that doesn't actually match
        // what's on screen. driveCurrentPath and the breadcrumb trail
        // both derive from data.path (the server's own normalized
        // rendering of the resolved path) rather than the raw input, so
        // trailing slashes / "." segments / etc always display clean.
        driveCurrentPath = data.path || "";
        renderDriveBreadcrumbs(driveCurrentPath);
        driveGrid.innerHTML = "";
        driveStatus.textContent = "";
        driveEntriesCache = data.entries;
        renderDriveEntries();
      } catch (e) {
        driveStatus.textContent = "Couldn't open that folder: " + (e.message || "unknown error");
      }
    }

    function closeDrivePanel() {
      if (activeOverlay !== "drive") return;
      activeOverlay = null;
      closeDriveItemMenu();
      if (typeof closeFileViewerModal === "function") closeFileViewerModal();
      driveBtn.classList.remove("active");
      drivePanel.hidden = true;
      contentWrap.hidden = false;
      updateTierButtonHighlight();
      updateComposerMode();
    }

    function openDrivePanel() {
      if (!CONFIG.ENDPOINT) {
        notify("error", "Not linked to Perla yet, set CONFIG.ENDPOINT.");
        return;
      }
      // Persist whatever's currently sitting in the composer (typed text,
      // queued images/files) before switching to a view that hides it —
      // the in-memory attachQueue/textFileQueue survive regardless (only
      // the composer's visibility toggles), but writing them to
      // sessionStorage here means a reload while System is open doesn't
      // lose an in-progress draft.
      saveCurrentTierDraft();
      closeHistoryPanel();
      closeRemindersPanel();
      closeQuickActionsPanel();

      activeOverlay = "drive";
      driveBtn.classList.add("active");
      updateTierButtonHighlight();
      contentWrap.hidden = true;
      drivePanel.hidden = false;
      updateComposerMode();

      // Apply persisted toggle states to the buttons' visual state (the
      // click handlers themselves aren't invoked here, since that would
      // also re-fetch/re-render twice back to back — loadDrivePath below
      // already does the one fetch that matters, using these same values).
      driveViewToggleBtn.classList.toggle("active", driveViewMode === "grid");
      driveViewToggleBtn.setAttribute("aria-pressed", String(driveViewMode === "grid"));
      driveViewToggleBtn.title = driveViewMode === "grid" ? "List view" : "Grid view";
      driveHiddenToggleBtn.classList.toggle("active", driveShowHidden);
      driveHiddenToggleBtn.setAttribute("aria-pressed", String(driveShowHidden));
      driveHiddenToggleBtn.title = driveShowHidden ? "Hide hidden files" : "Show hidden files";

      // Reflect whatever's on the clipboard (paste bar + button enabled
      // state) — the clipboard itself isn't cleared by closing/reopening
      // System within the same session, only by an explicit Cancel, a
      // successful paste, or a page reload.
      driveClipboardBar.hidden = !driveClipboard;
      drivePasteBtn.disabled = !driveClipboard;
      if (driveClipboard) {
        const verb = driveClipboard.mode === "cut" ? "Cut" : "Copy";
        driveClipboardLabel.innerHTML = `${verb}: <strong>${driveClipboard.name}</strong> — choose a folder and press Paste`;
        drivePasteBtn.title = `Paste "${driveClipboard.name}" here`;
      }

      loadDrivePath(driveCurrentPath);
    }

    driveBtn.addEventListener("click", () => {
      if (activeOverlay === "drive") {
        closeDrivePanel();
      } else {
        openDrivePanel();
      }
    });

    driveNewFolderBtn.addEventListener("click", () => {
      driveNewFolderRow.hidden = !driveNewFolderRow.hidden;
      if (!driveNewFolderRow.hidden) {
        driveNewFolderInput.value = "";
        driveNewFolderInput.focus();
      }
    });
    driveNewFolderCancel.addEventListener("click", () => { driveNewFolderRow.hidden = true; });
    driveNewFolderInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") driveNewFolderGo.click();
      if (e.key === "Escape") driveNewFolderRow.hidden = true;
    });
    driveNewFolderGo.addEventListener("click", async () => {
      const name = driveNewFolderInput.value.trim();
      if (!name) return;
      driveStatus.textContent = "Creating folder…";
      try {
        const res = await fetch(CONFIG.ENDPOINT + CONFIG.DRIVE_MKDIR_PATH, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + authToken },
          body: JSON.stringify({ path: driveCurrentPath, name }),
        });
        if (res.status === 401) { relockSession(); return; }
        const data = await res.json();
        if (!res.ok || !data.ok) throw new Error(data.error || "failed");
        driveNewFolderRow.hidden = true;
        await loadDrivePath(driveCurrentPath);
      } catch (e) {
        driveStatus.textContent = "Couldn't create folder: " + (e.message || "unknown error");
      }
    });

    driveUploadBtn.addEventListener("click", () => driveUploadInput.click());
    driveUploadInput.addEventListener("change", () => {
      driveUploadFiles(driveUploadInput.files);
      driveUploadInput.value = "";
    });

    function readFileAsDataUrl(file) {
      return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(new Error("couldn't read " + (file.name || "file")));
        reader.readAsDataURL(file);
      });
    }

    async function driveUploadFiles(fileList) {
      const files = Array.from(fileList || []);
      if (files.length === 0) return;
      driveStatus.textContent = `Uploading ${files.length} file${files.length === 1 ? "" : "s"}…`;
      try {
        const payload = [];
        for (const file of files) {
          const dataUrl = await readFileAsDataUrl(file);
          payload.push({ data: dataUrl, filename: file.name });
        }
        const res = await fetch(CONFIG.ENDPOINT + CONFIG.DRIVE_UPLOAD_PATH, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + authToken },
          body: JSON.stringify({ path: driveCurrentPath, files: payload }),
        });
        if (res.status === 401) { relockSession(); return; }
        const data = await res.json();
        if (!data.ok && (!data.saved || data.saved.length === 0)) {
          throw new Error((data.errors && data.errors.join("; ")) || "upload failed");
        }
        driveStatus.textContent = data.errors ? "Some files were skipped: " + data.errors.join("; ") : "";
        await loadDrivePath(driveCurrentPath);
      } catch (e) {
        driveStatus.textContent = "Upload failed: " + (e.message || "unknown error");
      }
    }

    // Drag-and-drop upload onto the grid — a very Drive-like affordance,
    // additive to the explicit upload button (which remains the only path
    // on touch devices with no drag source).
    ["dragenter", "dragover"].forEach((evt) => {
      driveGrid.addEventListener(evt, (e) => {
        e.preventDefault();
        driveGrid.classList.add("drive-dropzone-active");
      });
    });
    ["dragleave", "drop"].forEach((evt) => {
      driveGrid.addEventListener(evt, (e) => {
        e.preventDefault();
        driveGrid.classList.remove("drive-dropzone-active");
      });
    });
    driveGrid.addEventListener("drop", (e) => {
      if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length) {
        driveUploadFiles(e.dataTransfer.files);
      }
    });

    // Paste-to-upload: a file copied from the OS file manager (or a raw
    // clipboard image from a screenshot tool) pasted while System is the
    // active view uploads it into the current folder — the same
    // destination a drag-drop onto the grid would use. Attached to
    // `document` (not driveGrid) since a plain <div> grid isn't a paste
    // target on its own; gated on activeOverlay so pasting elsewhere in
    // the app (the chat composer has its own, separate paste handler)
    // is never intercepted here.
    document.addEventListener("paste", (e) => {
      if (activeOverlay !== "drive" || !e.clipboardData) return;
      const files = Array.from(e.clipboardData.files || []);
      if (files.length === 0) return;
      e.preventDefault();
      driveUploadFiles(files);
    });

    async function driveDownload(entryPath, filename) {
      try {
        const url = CONFIG.ENDPOINT + CONFIG.DRIVE_DOWNLOAD_PATH + "?path=" + encodeURIComponent(entryPath);
        const res = await fetch(url, { headers: { Authorization: "Bearer " + authToken } });
        if (res.status === 401) { relockSession(); return; }
        if (!res.ok) throw new Error("download failed");
        const blob = await res.blob();
        const objectUrl = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = objectUrl;
        a.download = filename || "file";
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(objectUrl), 10000);
      } catch (e) {
        driveStatus.textContent = "Couldn't download " + (filename || "that file") + ".";
      }
    }

    // ---------- Cut / Copy / Paste ----------
    function driveRenderClipboardBar() {
      if (!driveClipboard) {
        driveClipboardBar.hidden = true;
        drivePasteBtn.disabled = true;
        drivePasteBtn.title = "Paste";
        renderDriveEntries(); // clears any leftover .is-cut dimming
        return;
      }
      const verb = driveClipboard.mode === "cut" ? "Cut" : "Copy";
      driveClipboardLabel.innerHTML = `${verb}: <strong>${driveClipboard.name}</strong> — choose a folder and press Paste`;
      driveClipboardBar.hidden = false;
      drivePasteBtn.disabled = false;
      drivePasteBtn.title = `Paste "${driveClipboard.name}" here`;
      renderDriveEntries(); // re-applies .is-cut dimming if the source item is in view
    }

    function driveSetClipboard(entryPath, name, mode) {
      driveClipboard = { path: entryPath, name, mode };
      driveStatus.textContent = "";
      driveRenderClipboardBar();
    }

    function driveClearClipboard() {
      driveClipboard = null;
      driveRenderClipboardBar();
    }

    driveClipboardCancel.addEventListener("click", driveClearClipboard);

    async function drivePasteHere() {
      if (!driveClipboard) return;
      const { path: srcPath, name, mode } = driveClipboard;
      const endpoint = mode === "cut" ? CONFIG.DRIVE_MOVE_PATH : CONFIG.DRIVE_COPY_PATH;
      driveStatus.textContent = `${mode === "cut" ? "Moving" : "Copying"} "${name}"…`;
      try {
        const res = await fetch(CONFIG.ENDPOINT + endpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + authToken },
          body: JSON.stringify({ path: srcPath, dest: driveCurrentPath }),
        });
        if (res.status === 401) { relockSession(); return; }
        const data = await res.json();
        if (!res.ok || !data.ok) throw new Error(data.error || "failed");
        driveStatus.textContent = `"${name}" ${mode === "cut" ? "moved" : "copied"} here.`;
        driveClipboard = null;
        driveClipboardBar.hidden = true;
        drivePasteBtn.disabled = true;
        await loadDrivePath(driveCurrentPath);
      } catch (e) {
        driveStatus.textContent = `Couldn't ${mode === "cut" ? "move" : "copy"}: ` + (e.message || "unknown error");
      }
    }

    drivePasteBtn.addEventListener("click", drivePasteHere);

    async function driveDeleteEntry(entryPath, name) {
      driveStatus.textContent = "Moving to Trash…";
      try {
        const res = await fetch(CONFIG.ENDPOINT + CONFIG.DRIVE_DELETE_PATH, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + authToken },
          body: JSON.stringify({ path: entryPath }),
        });
        if (res.status === 401) { relockSession(); return; }
        const data = await res.json();
        if (!res.ok || !data.ok) throw new Error(data.error || "failed");
        await loadDrivePath(driveCurrentPath);
        // Delete is a move-to-trash now, and the toast's Undo restores the
        // exact trash entry — no destructive confirm needed up front.
        const trashName = (data.trash && data.trash.trash_name) || "";
        const undo = trashName ? [{ label: "Undo", onClick: () => driveRestoreEntry(trashName, name) }] : null;
        notify("info", `Moved "${name}" to Trash`, "It's recoverable from the OS Trash.", true, undo);
      } catch (e) {
        driveStatus.textContent = "Couldn't delete: " + (e.message || "unknown error");
      }
    }

    async function driveRestoreEntry(trashName, name) {
      driveStatus.textContent = "Restoring…";
      try {
        const res = await fetch(CONFIG.ENDPOINT + CONFIG.DRIVE_RESTORE_PATH, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + authToken },
          body: JSON.stringify({ trash_name: trashName }),
        });
        if (res.status === 401) { relockSession(); return; }
        const data = await res.json();
        if (!res.ok || !data.ok) throw new Error(data.error || "failed");
        await loadDrivePath(driveCurrentPath);
        driveStatus.textContent = `Restored "${name}".`;
      } catch (e) {
        driveStatus.textContent = "Couldn't restore: " + (e.message || "unknown error");
      }
    }

    // "Add to chat" hands the file to whichever tier's chat is currently
    // active (same tier-targeting pattern submitText/handleRecordingComplete
    // use) — the server reads the file straight off disk and feeds it
    // through the exact same image/text-attachment pipelines a normal
    // upload uses, so the reply lands in that tier's transcript exactly
    // like any other message with an attachment would.
    // "Add to chat" queues the file into the composer's own attach/text-
    // file queue (same queues the paperclip/file-picker paths use) rather
    // than sending it immediately — the person reviews it, can type
    // accompanying text, and sends (or removes it) themselves, exactly
    // like any other attachment. This never touches the OpenCode/model
    // round-trip; it's purely "fetch the bytes, hand them to the composer."
    async function driveAddToChat(entryPath, filename) {
      const ext = textFileExtension(filename);
      const isImage = DRIVE_VIEW_IMAGE_EXTENSIONS.has(ext) && (ext === ".png" || ext === ".jpg" || ext === ".jpeg");
      const isDocument = DOCUMENT_FILE_EXTENSIONS.has(ext);
      const isPlainText = TEXT_FILE_EXTENSIONS.has(ext);

      if (!isImage && !isDocument && !isPlainText) {
        driveStatus.textContent = `'${filename}' isn't a supported type for chat.`;
        return;
      }

      // Enforce the same per-message caps the local file pickers already
      // enforce, so "Add to chat" can't silently blow past them.
      if (isImage && attachQueue.length >= MAX_IMAGES_PER_MESSAGE) {
        driveStatus.textContent = `You can attach up to ${MAX_IMAGES_PER_MESSAGE} images per message.`;
        return;
      }
      if ((isDocument || isPlainText) && textFileQueue.length >= MAX_TEXT_FILES_PER_MESSAGE) {
        driveStatus.textContent = `You can attach up to ${MAX_TEXT_FILES_PER_MESSAGE} text/code files per message.`;
        return;
      }

      driveStatus.textContent = `Adding "${filename}"…`;
      try {
        const url = CONFIG.ENDPOINT + CONFIG.DRIVE_DOWNLOAD_PATH + "?path=" + encodeURIComponent(entryPath);
        const res = await fetch(url, { headers: { Authorization: "Bearer " + authToken } });
        if (res.status === 401) { relockSession(); return; }
        if (!res.ok) throw new Error("couldn't fetch file");
        const blob = await res.blob();

        if (!isImage) {
          const maxBytes = isDocument ? MAX_DOCUMENT_FILE_BYTES : MAX_TEXT_FILE_BYTES;
          if (blob.size > maxBytes) {
            const limitLabel = isDocument
              ? `${Math.round(maxBytes / (1024 * 1024))}MB`
              : `${Math.round(maxBytes / 1024)}KB`;
            driveStatus.textContent = `'${filename}' is too large, max ${limitLabel}.`;
            return;
          }
        } else if (blob.size > 10 * 1024 * 1024) {
          driveStatus.textContent = `'${filename}' is too large, max 10MB.`;
          return;
        }

        const dataUrl = await new Promise((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => resolve(reader.result);
          reader.onerror = () => reject(new Error("couldn't read file"));
          reader.readAsDataURL(blob);
        });

        if (isImage) {
          attachQueue.push({ dataUrl, filename });
        } else {
          textFileQueue.push({ dataUrl, filename });
        }
        renderAttachPreview();
        updateComposerState();
        saveCurrentTierDraft();
        driveStatus.textContent = `"${filename}" added to the message box — review and send when ready.`;
      } catch (e) {
        driveStatus.textContent = "Couldn't add to chat: " + (e.message || "unknown error");
      }
    }

    // ---------- File viewer modal (System's "View" action) ----------
    // Text/code files fetch their content via /api/drive/view (JSON,
    // server-truncated past 2MB) and render as <pre>; images are fetched
    // as a blob through the authenticated download endpoint (same
    // pattern addImageEntry/buildDeliveredFileRow already use, since a bare
    // <img src> can't carry a bearer token) and render as <img>. Neither
    // path touches the download-triggering DRIVE_DOWNLOAD_PATH flow used
    // by the toolbar's own Download button — viewing and downloading are
    // separate actions that happen to share a GET endpoint for bytes.
    const fileViewerModal = document.getElementById("fileViewerModal");
    const fileViewerModalIcon = document.getElementById("fileViewerModalIcon");
    const fileViewerModalName = document.getElementById("fileViewerModalName");
    const fileViewerModalBody = document.getElementById("fileViewerModalBody");
    const fileViewerModalClose = document.getElementById("fileViewerModalClose");
    const fileViewerModalDownload = document.getElementById("fileViewerModalDownload");
    let fileViewerCurrentPath = null;
    let fileViewerObjectUrl = null;

    function closeFileViewerModal() {
      fileViewerModal.hidden = true;
      fileViewerModalBody.innerHTML = "";
      fileViewerCurrentPath = null;
      if (fileViewerObjectUrl) {
        URL.revokeObjectURL(fileViewerObjectUrl);
        fileViewerObjectUrl = null;
      }
    }

    fileViewerModalClose.addEventListener("click", closeFileViewerModal);
    fileViewerModal.addEventListener("click", (e) => {
      if (e.target === fileViewerModal) closeFileViewerModal();
    });
    fileViewerModalDownload.addEventListener("click", () => {
      if (!fileViewerCurrentPath) return;
      const name = fileViewerModalName.textContent || "file";
      driveDownload(fileViewerCurrentPath, name);
    });

    async function driveViewFile(entryPath, filename) {
      fileViewerCurrentPath = entryPath;
      fileViewerModalName.textContent = filename;
      fileViewerModalName.title = filename;
      fileViewerModalIcon.innerHTML = GENERIC_FILE_ICON_SVG;
      fileViewerModalBody.innerHTML = '<div class="empty file-viewer-modal-loading">Loading…</div>';
      fileViewerModal.hidden = false;

      const ext = textFileExtension(filename);
      try {
        if (DRIVE_VIEW_IMAGE_EXTENSIONS.has(ext)) {
          const url = CONFIG.ENDPOINT + CONFIG.DRIVE_DOWNLOAD_PATH + "?path=" + encodeURIComponent(entryPath);
          const res = await fetch(url, { headers: { Authorization: "Bearer " + authToken } });
          if (res.status === 401) { relockSession(); return; }
          if (!res.ok) throw new Error("couldn't load image");
          const blob = await res.blob();
          if (fileViewerObjectUrl) URL.revokeObjectURL(fileViewerObjectUrl);
          fileViewerObjectUrl = URL.createObjectURL(blob);
          fileViewerModalBody.innerHTML = "";
          const img = document.createElement("img");
          img.src = fileViewerObjectUrl;
          img.alt = filename;
          fileViewerModalBody.appendChild(img);
          return;
        }

        const url = CONFIG.ENDPOINT + CONFIG.DRIVE_VIEW_PATH + "?path=" + encodeURIComponent(entryPath);
        const res = await fetch(url, { headers: { Authorization: "Bearer " + authToken } });
        if (res.status === 401) { relockSession(); return; }
        const data = await res.json();
        if (!res.ok || !data.ok) throw new Error(data.error || "couldn't view this file");
        fileViewerModalBody.innerHTML = "";
        const pre = document.createElement("pre");
        pre.textContent = data.content;
        fileViewerModalBody.appendChild(pre);
      } catch (e) {
        fileViewerModalBody.innerHTML = '<div class="empty file-viewer-modal-empty"></div>';
        fileViewerModalBody.querySelector(".file-viewer-modal-empty").textContent =
          "Couldn't view this file: " + (e.message || "unknown error");
      }
    }

    // ---------- Global notifications ----------
    // App-scope notices (formerly inline .entry-system chat messages) that
    // float above every panel, sharing the Quick Actions feedback-card look.
    // findGlobalNotifications is looked up per call (never cached in a
    // top-level const) so this works even when called during early script
    // init, before DOM refs are gathered below.
    function findGlobalNotifications() {
      return document.getElementById("globalNotifications");
    }

    function dismissNotification(card) {
      if (!card || !card.parentNode) return;
      card.classList.add("closing");
      setTimeout(() => {
        if (card.parentNode) card.remove();
      }, 250);
    }

    function notify(type, title, meta = "", autoDismiss = true, actions = null) {
      const container = findGlobalNotifications();
      if (!container) {
        console.warn("[notify]", type, title, meta);
        return null;
      }

      const card = document.createElement("div");
      card.className = "toast" + (type === "info" ? "" : " " + type);

      const iconSpan = document.createElement("span");
      iconSpan.className = "toast-icon";
      if (type === "loading") {
        iconSpan.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" width="16" height="16"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg>';
      } else if (type === "success") {
        iconSpan.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" width="16" height="16"><polyline points="20 6 9 17 4 12"/></svg>';
      } else if (type === "error") {
        iconSpan.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" width="16" height="16"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>';
      } else {
        iconSpan.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" width="16" height="16"><circle cx="12" cy="12" r="10"/><line x1="12" y1="12" x2="12" y2="16"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>';
      }
      card.appendChild(iconSpan);

      const contentDiv = document.createElement("div");
      contentDiv.className = "toast-content";

      const titleDiv = document.createElement("div");
      titleDiv.className = "toast-title";
      titleDiv.textContent = title || "";
      contentDiv.appendChild(titleDiv);

      if (meta) {
        const metaDiv = document.createElement("div");
        metaDiv.className = "toast-meta";
        metaDiv.textContent = meta;
        contentDiv.appendChild(metaDiv);
      }
      card.appendChild(contentDiv);

      // Optional action buttons (e.g. Drive's "Undo" after a delete).
      // Each click runs its callback then dismisses the card.
      if (actions && actions.length) {
        const actionsDiv = document.createElement("div");
        actionsDiv.className = "toast-actions";
        actions.forEach((action) => {
          const btn = document.createElement("button");
          btn.className = "btn btn-xs btn-primary";
          btn.textContent = action.label;
          btn.addEventListener("click", () => {
            dismissNotification(card);
            if (action.onClick) action.onClick();
          });
          actionsDiv.appendChild(btn);
        });
        card.appendChild(actionsDiv);
      }

      const closeBtn = document.createElement("button");
      closeBtn.className = "btn-icon btn-icon-24 btn-icon-square";
      closeBtn.setAttribute("aria-label", "Dismiss");
      closeBtn.textContent = "✕";
      closeBtn.addEventListener("click", () => dismissNotification(card));
      card.appendChild(closeBtn);

      container.appendChild(card);

      if (autoDismiss && type !== "loading") {
        // Cards with actionable buttons (Undo etc.) get a longer window so
        // there's real time to act, instead of the 4.2s read-only toast.
        const delay = actions && actions.length ? 10000 : 4200;
        setTimeout(() => dismissNotification(card), delay);
      }
      return card;
    }

    // ---------- Quick Actions (deterministic, no-LLM commands) ----------
    // Each button here calls /api/quick-action directly — never through
    // OpenCode/the model. This exists because the model was unreliable
    // about actually calling its own MCP tools on casual phrasing (e.g.
    // "send me my screen" sometimes got a confabulated text description
    // instead of an actual screenshot). A fixed menu removes the model
    // from the decision entirely: tap a button, run the fixed action, done.
    const quickActionsBtn = sidebar.querySelector('[data-destination="actions"]');
    const quickActionsPanel = document.getElementById("quickActionsPanel");
    const qaResult = document.getElementById("qaResult");

    function closeQuickActionsPanel() {
      if (activeOverlay !== "quick-actions") return;
      activeOverlay = null;
      quickActionsBtn.classList.remove("active");
      quickActionsPanel.hidden = true;
      quickActionsStatus.textContent = "";
      qaResult.innerHTML = "";
      closeQaInputRow();
      // Collapse the output drawer rather than clearing it — the last
      // batch of results (a rebuild log, a restarted-service confirmation)
      // should still be there if the person reopens Quick Actions a
      // moment later, same persistence the notify() toasts already imply.
      setQaDrawerExpanded(false);
      output.innerHTML = liveOutputHTML !== null ? liveOutputHTML : "";
      output.scrollIntoView({ block: "end" });
      updateTierButtonHighlight();
      updateComposerMode();
    }

    function openQuickActionsPanel() {
      if (!CONFIG.ENDPOINT) {
        notify("error", "Not linked to Perla yet, set CONFIG.ENDPOINT.");
        return;
      }
      saveCurrentTierDraft();
      closeHistoryPanel();
      closeRemindersPanel();
      closeDrivePanel();

      activeOverlay = "quick-actions";
      quickActionsBtn.classList.add("active");
      updateTierButtonHighlight();
      quickActionsPanel.hidden = false;
      quickActionsPanel.scrollTop = 0;
      updateComposerMode();
      liveOutputHTML = output.innerHTML;
      output.innerHTML = "";
      qaResult.innerHTML = "";
      quickActionsStatus.textContent = "";
    }

    quickActionsBtn.addEventListener("click", () => {
      if (activeOverlay === "quick-actions") {
        closeQuickActionsPanel();
      } else {
        openQuickActionsPanel();
      }
    });

    const qaInputRow = document.getElementById("qaInputRow");
    const qaInputField = document.getElementById("qaInputField");
    const qaInputGo = document.getElementById("qaInputGo");
    const qaInputCancel = document.getElementById("qaInputCancel");
    let qaPendingInputAction = null; // "open_app" | "open_folder" | null
    let qaActiveInputBtn = null;

    function closeQaInputRow() {
      if (qaInputRow) qaInputRow.hidden = true;
      if (qaInputField) qaInputField.value = "";
      qaPendingInputAction = null;
      if (qaActiveInputBtn) {
        qaActiveInputBtn.classList.remove("active");
        qaActiveInputBtn = null;
      }
    }

    const QA_INPUT_PLACEHOLDERS = {
      open_app: "App name (e.g. Firefox, VLC)",
      open_folder: "Folder path (e.g. ~/Documents)",
      restart_service: "Service name (e.g. perla-companion)",
      status_service: "Service name (e.g. perla-companion)",
    };

    // Actions whose "Go" press must route through the scoped-command
    // endpoint (validated-name commands) rather than /api/quick-action
    // (the fixed system-action allowlist).
    const QA_SCOPED_INPUT_ACTIONS = new Set(["restart_service", "status_service"]);

    function openQaInputRow(action, btn) {
      if (qaActiveInputBtn && qaActiveInputBtn !== btn) {
        qaActiveInputBtn.classList.remove("active");
      }
      qaPendingInputAction = action;
      qaActiveInputBtn = btn;
      btn.classList.add("active");
      if (qaInputField) {
        qaInputField.placeholder = QA_INPUT_PLACEHOLDERS[action] || "";
        qaInputField.value = "";
      }
      if (qaInputRow) {
        qaInputRow.hidden = false;
        qaInputRow.scrollIntoView({ behavior: "smooth", block: "nearest" });
      }
      if (qaInputField) qaInputField.focus();
    }

    if (qaInputCancel) qaInputCancel.addEventListener("click", closeQaInputRow);
    if (qaInputField) {
      qaInputField.addEventListener("keydown", (e) => {
        if (e.key === "Enter") qaInputGo.click();
        if (e.key === "Escape") closeQaInputRow();
      });
    }
    if (qaInputGo) {
      qaInputGo.addEventListener("click", () => {
        const target = qaInputField.value.trim();
        const action = qaPendingInputAction;
        if (!target || !action) return;
        closeQaInputRow();
        if (QA_SCOPED_INPUT_ACTIONS.has(action)) {
          if (action === "restart_service" && !window.confirm(`Restart the service "${target}"?`)) return;
          runScopedCommand(action, target);
        } else {
          runQuickAction(action, target);
        }
      });
    }

    function renderQaText(text, isError) {
      notify(isError ? "error" : "success", text, isError ? "Action failed" : "Completed");
    }

    // ---------- Quick Actions output drawer ----------
    // Appends one entry per command run (newest first) instead of the old
    // qaResult behavior of overwriting the single card each time. Entries
    // persist until "Clear" is pressed or the drawer is torn down on panel
    // close (see closeQuickActionsPanel). Kept as a simple in-memory array
    // + full re-render on change — this list is short-lived (cleared on
    // panel close) and never large enough to need incremental DOM patching.
    const qaDrawer = document.getElementById("qaDrawer");
    const qaDrawerHeader = document.getElementById("qaDrawerHeader");
    const qaDrawerBody = document.getElementById("qaDrawerBody");
    const qaDrawerCount = document.getElementById("qaDrawerCount");
    const qaDrawerClear = document.getElementById("qaDrawerClear");
    let qaDrawerEntries = []; // { id, label, time, ok, kind: "text"|"image", output, imageUrl }
    let qaDrawerEntrySeq = 0;

    function setQaDrawerExpanded(expanded) {
      qaDrawer.classList.toggle("expanded", expanded);
    }

    qaDrawerHeader.addEventListener("click", (e) => {
      if (e.target.closest("#qaDrawerClear")) return;
      setQaDrawerExpanded(!qaDrawer.classList.contains("expanded"));
    });

    qaDrawerClear.addEventListener("click", (e) => {
      e.stopPropagation();
      qaDrawerEntries = [];
      renderQaDrawer();
    });

    function renderQaDrawer() {
      qaDrawerCount.textContent = String(qaDrawerEntries.length);
      qaDrawerCount.dataset.count = String(qaDrawerEntries.length);
      qaDrawer.hidden = false; // once opened for the session, stays available (just empty)

      if (qaDrawerEntries.length === 0) {
        qaDrawerBody.innerHTML = '<div class="empty qa-drawer-empty">No results yet — run a command to see its output here.</div>';
        return;
      }

      qaDrawerBody.innerHTML = "";
      qaDrawerEntries.forEach((entry) => {
        const card = document.createElement("div");
        card.className = "qa-drawer-entry";

        const header = document.createElement("div");
        header.className = "qa-drawer-entry-header";
        const dot = document.createElement("span");
        dot.className = "qa-drawer-entry-status " + (entry.ok ? "ok" : "fail");
        const label = document.createElement("span");
        label.className = "qa-drawer-entry-label";
        label.textContent = entry.label;
        const time = document.createElement("span");
        time.className = "qa-drawer-entry-time";
        time.textContent = entry.time;
        header.append(dot, label, time);
        card.appendChild(header);

        const body = document.createElement("div");
        body.className = "qa-drawer-entry-body" + (entry.ok ? "" : " is-error");

        if (entry.kind === "image") {
          if (entry.imageObjectUrl) {
            const img = document.createElement("img");
            img.src = entry.imageObjectUrl;
            img.alt = "Screenshot";
            img.addEventListener("click", () => openLightbox(entry.imageObjectUrl));
            body.appendChild(img);
          } else {
            const p = document.createElement("div");
            p.className = "empty qa-drawer-empty";
            p.textContent = "Loading preview…";
            body.appendChild(p);
          }
        } else {
          const pre = document.createElement("pre");
          pre.textContent = entry.output || "(no output)";
          body.appendChild(pre);
        }
        card.appendChild(body);
        qaDrawerBody.appendChild(card);
      });
    }

    // Adds one entry to the front of the drawer list and re-renders.
    // Returns the entry object so a caller (e.g. the screenshot path) can
    // mutate it later (filling in imageObjectUrl once the fetch resolves)
    // and re-render again.
    function appendQaDrawerEntry({ label, ok, kind, output, imageUrl }) {
      const entry = {
        id: ++qaDrawerEntrySeq,
        label,
        ok,
        kind: kind || "text",
        output,
        imageUrl,
        imageObjectUrl: null,
        time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
      };
      qaDrawerEntries.unshift(entry);
      // Cap history so a long session doesn't grow this unboundedly —
      // older entries are dropped silently past this point, same
      // trade-off as any bounded log view.
      if (qaDrawerEntries.length > 30) qaDrawerEntries.length = 30;
      renderQaDrawer();
      return entry;
    }

    async function renderQaImage(imageUrl, label) {
      const entry = appendQaDrawerEntry({ label: label || "Screenshot", ok: true, kind: "image", imageUrl });
      setQaDrawerExpanded(true);
      try {
        const url = imageUrl.startsWith("http") ? imageUrl : CONFIG.ENDPOINT + imageUrl;
        const res = await fetch(url, { headers: { Authorization: "Bearer " + authToken } });
        if (!res.ok) throw new Error("image fetch failed");
        const blob = await res.blob();
        entry.imageObjectUrl = URL.createObjectURL(blob);
        renderQaDrawer();
        notify("success", "Screenshot captured", "Open the Output drawer to view it");
      } catch (e) {
        entry.ok = false;
        entry.kind = "text";
        entry.output = "Couldn't load the screenshot.";
        renderQaDrawer();
        notify("error", "Failed to load screenshot preview", "Try capturing again");
      }
    }

    async function runQuickAction(action, target) {
      if (!CONFIG.ENDPOINT) {
        notify("error", "Not linked to Perla yet, set CONFIG.ENDPOINT.");
        return;
      }

      const btn = document.querySelector(`.qa-btn[data-qa="${action}"]`);
      const actionLabel = btn ? btn.querySelector(".qa-label").textContent.trim() : action;

      if (btn) btn.classList.add("is-loading");
      const qaLoadingCard = notify("loading", `Running ${actionLabel}…`, target ? `Target: ${target}` : "Contacting Perla daemon", false);

      try {
        const body = { action };
        if (target) body.target = target;
        const res = await fetch(CONFIG.ENDPOINT + CONFIG.QUICK_ACTION_PATH, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: "Bearer " + authToken,
          },
          body: JSON.stringify(body),
        });

        if (res.status === 401) {
          dismissNotification(qaLoadingCard);
          relockSession();
          return;
        }

        const data = await res.json();

        if (data.image !== undefined && data.image) {
          if (btn) {
            btn.classList.add("is-success");
            setTimeout(() => btn.classList.remove("is-success"), 1200);
          }
          dismissNotification(qaLoadingCard);
          await renderQaImage(data.image, actionLabel);
          return;
        }

        if (data.ok) {
          if (btn) {
            btn.classList.add("is-success");
            setTimeout(() => btn.classList.remove("is-success"), 1200);
          }
          dismissNotification(qaLoadingCard);
          notify("success", data.message || `${actionLabel} completed`, "Just now");
          appendQaDrawerEntry({ label: actionLabel, ok: true, kind: "text", output: data.message || "Completed." });
        } else {
          if (btn) {
            btn.classList.add("is-error");
            setTimeout(() => btn.classList.remove("is-error"), 1500);
          }
          dismissNotification(qaLoadingCard);
          notify("error", data.error || `Could not run ${actionLabel}`, "Action reported an error");
          appendQaDrawerEntry({ label: actionLabel, ok: false, kind: "text", output: data.error || "Action reported an error." });
        }
      } catch (e) {
        if (btn) {
          btn.classList.add("is-error");
          setTimeout(() => btn.classList.remove("is-error"), 1500);
        }
        dismissNotification(qaLoadingCard);
        notify("error", "Connection error", "Couldn't reach Perla companion daemon");
        appendQaDrawerEntry({ label: actionLabel, ok: false, kind: "text", output: "Connection error — couldn't reach Perla companion daemon." });
      } finally {
        if (btn) btn.classList.remove("is-loading");
      }
    }

    // Scoped commands hit /api/scoped-command, a SEPARATE endpoint from
    // /api/quick-action — every name here maps to a hardcoded argv on the
    // server (SCOPED_COMMANDS), or for "restart_service" specifically, a
    // caller-supplied name that only ever SELECTS an existing systemd
    // --user unit (validated server-side), never anything shell-injected.
    async function runScopedCommand(name, target) {
      if (!CONFIG.ENDPOINT) {
        notify("error", "Not linked to Perla yet, set CONFIG.ENDPOINT.");
        return;
      }
      const btn = document.querySelector(`.qa-btn[data-scoped="${name}"]`);
      const label = btn ? btn.querySelector(".qa-label").textContent.trim() : name;

      if (btn) btn.classList.add("is-loading");
      const loadingCard = notify("loading", `Running ${label}…`, target ? `Target: ${target}` : "This may take a moment", false);

      try {
        const body = { name };
        if (target) body.target = target;
        const res = await fetch(CONFIG.ENDPOINT + CONFIG.SCOPED_COMMAND_PATH, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + authToken },
          body: JSON.stringify(body),
        });
        if (res.status === 401) {
          dismissNotification(loadingCard);
          relockSession();
          return;
        }
        const data = await res.json();
        dismissNotification(loadingCard);

        const entryLabel = target ? `${label}: ${target}` : label;
        if (data.ok) {
          if (btn) {
            btn.classList.add("is-success");
            setTimeout(() => btn.classList.remove("is-success"), 1200);
          }
          appendQaDrawerEntry({ label: entryLabel, ok: true, kind: "text", output: data.output });
          setQaDrawerExpanded(true);
          notify("success", `${label} completed`, "Open the Output drawer to view it");
        } else {
          if (btn) {
            btn.classList.add("is-error");
            setTimeout(() => btn.classList.remove("is-error"), 1500);
          }
          appendQaDrawerEntry({ label: entryLabel, ok: false, kind: "text", output: data.error || "Command failed" });
          setQaDrawerExpanded(true);
          notify("error", data.error || `${label} failed`);
        }
      } catch (e) {
        if (btn) {
          btn.classList.add("is-error");
          setTimeout(() => btn.classList.remove("is-error"), 1500);
        }
        dismissNotification(loadingCard);
        notify("error", "Connection error", "Couldn't reach Perla companion daemon");
        appendQaDrawerEntry({ label, ok: false, kind: "text", output: "Connection error — couldn't reach Perla companion daemon." });
        setQaDrawerExpanded(true);
      } finally {
        if (btn) btn.classList.remove("is-loading");
      }
    }

    quickActionsPanel.addEventListener("click", (e) => {
      const btn = e.target.closest(".qa-btn");
      if (!btn) return;

      const scoped = btn.dataset.scoped;
      if (scoped) {
        if (scoped === "restart_service" || scoped === "status_service") {
          if (qaPendingInputAction === scoped) {
            closeQaInputRow();
          } else {
            openQaInputRow(scoped, btn);
          }
          return;
        }
        closeQaInputRow();
        const confirmMsg = btn.dataset.confirm;
        if (confirmMsg && !window.confirm(confirmMsg)) return;
        runScopedCommand(scoped);
        return;
      }

      const action = btn.dataset.qa;
      if (!action) return;

      if (action === "open_app" || action === "open_folder") {
        if (qaPendingInputAction === action) {
          closeQaInputRow();
        } else {
          openQaInputRow(action, btn);
        }
        return;
      }
      closeQaInputRow();

      const confirmMsg = btn.dataset.confirm;
      if (confirmMsg && !window.confirm(confirmMsg)) return;

      runQuickAction(action);
    });

    function formatReminderTime(iso) {
      // iso like 2026-08-26T18:00 -> "Tue, Aug 26 · 6:00 PM"; if it's today,
      // just the time.
      if (!iso) return "";
      const dt = new Date(iso);
      if (isNaN(dt.getTime())) return iso;
      const today = new Date();
      const isToday = dt.toDateString() === today.toDateString();
      const timeStr = dt.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
      if (isToday) return `Today · ${timeStr}`;
      const dateStr = dt.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
      return `${dateStr} · ${timeStr}`;
    }

    function renderReminders(data) {
      output.innerHTML = "";

      const pending = data.pending || [];
      const missed = data.missed || [];
      const delivered = data.delivered || [];

      if (pending.length === 0 && missed.length === 0 && delivered.length === 0) {
        const wrap = document.createElement("div");
        wrap.className = "empty reminder-empty";
        wrap.textContent = "No reminders set.";
        output.appendChild(wrap);
        return;
      }

      if (missed.length > 0) {
        output.appendChild(buildReminderSection(
          "missed", `Missed (${missed.length})`, missed,
          (r) => `Was due ${formatReminderTime(r.due)}, caught at ${formatReminderTime(r.delivered)}`
        ));
      }

      // Upcoming always shows, even when empty, so it's clear there's
      // nothing pending rather than looking like the section didn't load.
      const upcomingSection = buildReminderSection(
        "pending", `Upcoming (${pending.length})`, pending,
        (r) => r.overdue ? `Due ${formatReminderTime(r.due)}, waiting to fire` : `Due ${formatReminderTime(r.due)}`,
        "Nothing on the books."
      );
      output.appendChild(upcomingSection);

      if (delivered.length > 0) {
        const details = document.createElement("details");
        details.className = "reminder-collapsible reminder-section";
        const summary = document.createElement("summary");
        summary.innerHTML = `<div class="reminder-section-title">Delivered (${delivered.length})<span class="disclosure-arrow">›</span></div>`;
        details.appendChild(summary);
        const list = buildReminderList(delivered, "delivered",
          (r) => `Delivered ${formatReminderTime(r.delivered)}`
        );
        details.appendChild(list);
        output.appendChild(details);
      }
    }

    function buildReminderSection(statusClass, title, items, metaFn, emptyText) {
      const section = document.createElement("div");
      section.className = "reminder-section";
      const heading = document.createElement("div");
      heading.className = "reminder-section-title " + statusClass;
      heading.textContent = title;
      section.appendChild(heading);

      if (items.length === 0 && emptyText) {
        const empty = document.createElement("div");
        empty.className = "empty reminder-empty";
        empty.textContent = emptyText;
        section.appendChild(empty);
        return section;
      }

      section.appendChild(buildReminderList(items, statusClass, metaFn));
      return section;
    }

    function repeatLabel(token) {
      if (!token) return "";
      const t = token.toLowerCase();
      if (t === "hourly") return "repeats hourly";
      if (t === "daily") return "repeats daily";
      if (t === "weekly") return "repeats weekly";
      if (t === "monthly") return "repeats monthly";
      if (t === "yearly") return "repeats yearly";
      const m = t.match(/^every:(\d+)([hdw])$/);
      if (m) {
        const n = parseInt(m[1], 10);
        const unit = { h: "hour", d: "day", w: "week" }[m[2]];
        return `repeats every ${n} ${unit}${n > 1 ? "s" : ""}`;
      }
      return "";
    }

    function buildReminderList(items, statusClass, metaFn) {
      const list = document.createElement("div");
      list.className = "reminder-list";
      const glyphSVGs = {
        pending: '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" width="17" height="17"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>',
        missed: '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" width="17" height="17"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>',
        delivered: '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" width="17" height="17"><polyline points="20 6 9 17 4 12"/></svg>',
      };

      items.forEach((r) => {
        const isOverdue = statusClass === "pending" && r.overdue;
        const accentClass = isOverdue ? "overdue" : statusClass;
        const card = document.createElement("div");
        card.className = "reminder-card " + accentClass;

        const glyph = document.createElement("div");
        glyph.className = "reminder-glyph " + accentClass;
        glyph.innerHTML = glyphSVGs[statusClass] || "";

        const body = document.createElement("div");
        body.className = "reminder-body";
        const text = document.createElement("div");
        text.className = "reminder-text";
        text.textContent = r.text;
        body.appendChild(text);

        const cadenceLabel = repeatLabel(r.repeat);
        if (cadenceLabel) {
          const cadence = document.createElement("div");
          cadence.className = "reminder-cadence";
          cadence.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="12" height="12"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>';
          const span = document.createElement("span");
          span.textContent = cadenceLabel;
          cadence.appendChild(span);
          body.appendChild(cadence);
        }
        const meta = document.createElement("div");
        meta.className = "reminder-meta";
        meta.textContent = metaFn(r);
        body.appendChild(meta);

        card.appendChild(glyph);
        card.appendChild(body);

        if (statusClass === "pending") {
          const dismiss = document.createElement("button");
          dismiss.className = "btn-icon btn-icon-28 reminder-dismiss";
          dismiss.setAttribute("aria-label", "Remove reminder");
          dismiss.title = "Remove reminder";
          dismiss.textContent = "✕";
          dismiss.addEventListener("click", () => cancelReminder(r.id));
          card.appendChild(dismiss);
        }

        list.appendChild(card);
      });

      return list;
    }

    // ---------- Mobile keyboard handling (chat-app style) ----------
    // The on-screen keyboard shrinks the visualViewport rather than the
    // layout viewport, so with a plain 100dvh app shell the composer ends
    // up hidden behind the keyboard while the page silently scrolls under
    // it. Real chat apps instead resize the whole chat surface to fit the
    // visible area: header stays pinned at its natural position, the
    // composer sits right on top of the keyboard, and the message list is
    // the only thing that shrinks (and auto-scrolls to keep the latest
    // message in view). We do that here by driving --app-height / .app's
    // height directly from visualViewport instead of translating anything.
    (function keyboardResize() {
      const appEl = document.getElementById("app");
      if (!window.visualViewport || !appEl) return;

      let rafId = null;

      const applyViewportHeight = () => {
        const vv = window.visualViewport;

        // Ignore pinch-zoom: only care about the keyboard-driven case,
        // which is a shrink at scale ~1.
        const height = vv.scale > 1.01 ? window.innerHeight : vv.height;

        appEl.style.height = height + "px";

        // visualViewport can be offset from the top (e.g. address bar
        // collapse behavior on some browsers) — pin the app shell's top
        // to that offset so it tracks the actually-visible region rather
        // than drifting under content the user can't see.
        appEl.style.top = vv.offsetTop ? vv.offsetTop + "px" : "";

        // Keep the newest message visible once the keyboard has finished
        // animating in/out and the new height has settled.
        output.scrollIntoView({ block: "end" });
      };

      const scheduleApply = () => {
        if (rafId) cancelAnimationFrame(rafId);
        rafId = requestAnimationFrame(applyViewportHeight);
      };

      window.visualViewport.addEventListener("resize", scheduleApply);
      window.visualViewport.addEventListener("scroll", scheduleApply);

      // Also apply on focus/blur of the composer input directly — on some
      // mobile browsers the visualViewport resize event fires a beat late,
      // which shows up as a visible jump. Nudging it right on focus/blur
      // covers that gap.
      if (textInput) {
        textInput.addEventListener("focus", () => setTimeout(scheduleApply, 50));
        textInput.addEventListener("blur", () => setTimeout(scheduleApply, 50));
      }

      // Initial sizing in case the page loads with the viewport already
      // in a non-default state (e.g. rotated device).
      applyViewportHeight();
    })();

    // ---------- Session expiry / re-lock ----------
    // The daemon's session tokens are in-memory: a restart (or switch) makes
    // the stored token stale, and every authenticated call returns 401. Rather
    // than surfacing that as a generic "Couldn't reach Perla", toss the token
    // and bounce back to the gate.
    function relockSession() {
      const hadSession = !!authToken;
      sessionStorage.removeItem("perla_session_token");
      sessionStorage.removeItem("perla_elevate_until");
      sessionStorage.removeItem("perla_elevated");
      sessionStorage.removeItem("perla_tier1_unread");
      sessionStorage.removeItem("perla_tier2_unread");
      authToken = null;
      app.hidden = true;
      gate.style.display = "";
      gateError.hidden = false;
      gateError.textContent = "Session expired, enter your password.";
      gatePassword.value = "";
      gatePassword.focus();
      if (hadSession) {
        notify("error", "Session expired, enter your password.");
      }
    }

    // ---------- Clear conversation ----------
    const clearChatBtn = document.getElementById("clearChatBtn");

    clearChatBtn.addEventListener("click", () => {
      // Back out of an overlay first so the chat transcript is the thing
      // on screen — otherwise the wipe would silently apply to the chat
      // hidden underneath the history/reminders view.
      if (activeOverlay === "history") {
        closeHistoryPanel();
      } else if (activeOverlay === "reminders") {
        closeRemindersPanel();
      } else if (activeOverlay === "quick-actions") {
        closeQuickActionsPanel();
      } else if (activeOverlay === "drive") {
        closeDrivePanel();
      }
      if (!output.querySelector(".entry")) return;
      if (!window.confirm("Clear this conversation?")) return;
      output.innerHTML = "";
      setChatLog(activeTier, "");
      showWelcome(activeTier);
      notify("success", "Conversation cleared");
    });

    // ---------- Check session ----------
    // Cheap, side-effect-free: pings a lightweight authenticated endpoint and
    // reports whether the current token is still good. A dead token gets the
    // normal 401 -> relockSession() bounce, same as any other authenticated
    // call in this app; a live token just posts a confirmation into the chat.
    // Deliberately does NOT restart anything on its own — that's a separate,
    // deliberate action (Restart service, below), not something this check
    // should trigger as a side effect.
    const checkSessionBtn = document.getElementById("checkSessionBtn");

    checkSessionBtn.addEventListener("click", async () => {
      if (!CONFIG.ENDPOINT) {
        notify("error", "Not linked to Perla yet, set CONFIG.ENDPOINT.");
        return;
      }
      if (!authToken) {
        notify("error", "No active session to check.");
        return;
      }
      try {
        const res = await fetch(CONFIG.ENDPOINT + "/api/session/check", {
          headers: { Authorization: "Bearer " + authToken },
        });
        if (res.status === 401) {
          relockSession();
          return;
        }
        if (!res.ok) {
          notify("error", "Session check failed, unexpected response.");
          return;
        }
        notify("success", "Session is active.");
      } catch (err) {
        notify("error", "Couldn't reach Perla to check the session.");
      }
    });

    // ---------- Restart service ----------
    // Unconditional: this always restarts perla-companion when clicked, with
    // no "is it actually broken?" logic of its own — that's what Check
    // session is for, as a separate step the user takes deliberately before
    // (or instead of) reaching for this. Disruptive by nature (drops the
    // current connection while the daemon restarts), so it confirms first.
    const restartServiceBtn = document.getElementById("restartServiceBtn");

    restartServiceBtn.addEventListener("click", async () => {
      if (!CONFIG.ENDPOINT) {
        notify("error", "Not linked to Perla yet, set CONFIG.ENDPOINT.");
        return;
      }
      if (!authToken) {
        notify("error", "No active session, can't restart.");
        return;
      }
      if (!window.confirm("Restart the Perla service? You'll be briefly disconnected.")) return;
      const restartingCard = notify("loading", "Restarting the Perla service", "This may take a few seconds.", false);
      try {
        const res = await fetch(CONFIG.ENDPOINT + "/api/internal/restart", {
          method: "POST",
          headers: { Authorization: "Bearer " + authToken },
        });
        if (res.status === 401) {
          dismissNotification(restartingCard);
          relockSession();
          return;
        }
        if (!res.ok) {
          dismissNotification(restartingCard);
          notify("error", "Restart request failed", "Unexpected response.");
          return;
        }
        dismissNotification(restartingCard);
        notify("success", "Restart requested", "The Perla service is coming back up.");
      } catch (err) {
        // A network error here is actually the EXPECTED outcome once the
        // daemon has taken the connection down mid-restart, not necessarily
        // a real failure — so this is phrased as informational, not an error.
        dismissNotification(restartingCard);
        notify("info", "Restart triggered", "The connection dropped, which is expected while it comes back up.");
      }
    });

    // ---------- Deferred init ----------
    // Runs after every const/function above is declared. Handles the
    // "already had a session token" auto-unlock path from earlier in this
    // script, restoring saved tier/chat state for that case.
    updateComposerState();
    applySidebarCollapsed();
    if (authToken) {
      initAppState(false);
      // Was: resume the Full Mode countdown across a reload. With the countdown
      // gone there is nothing to resume, but the OTHER half of that block is
      // load-bearing and is kept verbatim - a reload that lands after the
      // elevation window closed must drop Tier 2 back to locked, or a stale
      // "perla_elevated" flag would leave the composer showing the real one and
      // every send failing. The first branch is therefore gone and this one is
      // not, and that asymmetry is the whole of what remains of the pair.
      const existingUntil = parseInt(sessionStorage.getItem("perla_elevate_until") || "0", 10);
      if (isElevated && existingUntil <= Date.now()) {
        sessionStorage.removeItem("perla_elevate_until");
        setElevated(false);
      }
    }