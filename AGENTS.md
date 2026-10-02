# AGENTS.md

Notes for AI agents working in this repo. Everything here was verified against
the tree; if something looks stale, check it rather than trusting it.

## What this is

A single-user NixOS + home-manager flake for one laptop (`hostName = "nixos"`,
user `thedreamdev`). System and home are **switched independently** — nothing in
`system/` imports `home/`, and home-manager is not wired into NixOS.

```
flake.nix                  the only top-level entry point; declares all 4 configs
system/configuration.nix   NixOS root
system/modules/            flat, single-concern feature modules
system/configs/            grouped service clusters with their own imports/
home/home.nix              home-manager root (Niri + Noctalia)
home/home-ryoku.nix        home-manager root (Hyprland + Ryoku)
home/modules/              aggregator/feature modules (perla.nix lives here)
home/configs/<app>/        per-app modules, each with a themes/ subdir
pkgs/                      custom packages (overlaid onto pkgs)
secrets/                   sops-encrypted YAML — committed
shells/                    dead code, see gotchas
configs/                   orphaned raw assets, see gotchas
```

## Build and verify

```sh
rebuild-nix         # sudo nixos-rebuild switch --flake .#nixos
rebuild-nix-ryoku   # sudo nixos-rebuild switch --flake .#ryoku
rebuild-home        # home-manager switch --flake .#thedreamdev
rebuild-home-ryoku  # home-manager switch --flake .#thedreamdev-ryoku
```

These are fish aliases in `home/configs/fish/fish.nix`. Run them from
`~/nixos-config` — several modules hardcode that absolute path.

**Almost every change is home-manager, not NixOS.** If you touch `home/`, you
need `rebuild-home`, not `rebuild-nix`. The names are misleading: `nixos` and
`ryoku` are *desktop profiles* for the same machine, not two hosts.

There is **no CI, no linters, no formatter, and no `checks` output** in this
flake. Verification is `nix flake show`, a dry-build, and — for Perla — its test
suite. Don't invent a `nix flake check` gate; it covers almost nothing.

## The two `pkgs` universes (biggest structural trap)

`flake.nix` builds a `pkgs` with custom overlays and passes it **only to the
two home-manager outputs** (`inherit pkgs`). The `nixosConfigurations` are built
via `nixpkgs.lib.nixosSystem` and never see it. Then `system/configuration.nix`
defines a *second, separate* overlay set.

Result: `brave-origin`, `rose-pine-gtk-theme`, and the `aseprite` fmt pin exist
for home only. Adding an overlay in one place does **not** make it available in
the other, and the two lists must be kept in sync by hand. `allowUnfree` is
also set in both files, and their `permittedInsecurePackages` differ.

## Nix conventions here

- 2-space indent, double-quoted strings, trailing `;`, unquoted relative import
  paths (`./modules/boot.nix`) with a leading `.` on every one.
- Blank line between the `imports` block and the settings block.
- Modules are flat `{ config, pkgs, lib, inputs, ... }: { ... }` — no `let`.
  A comment line *above* the function header is a deliberate style used in a few
  files (e.g. `home/configs/fastfetch/fastfetch.nix`).
- **Rich "why" comments are the norm, not noise.** Most non-obvious lines carry a
  comment explaining the constraint. Match it. Commented-out config
  (`minecraft.nix`, the lazymc block) is intentionally preserved — it is
  load-bearing history. Don't "clean it up".
- `ryokuSession` is a boolean passed via `extraSpecialArgs`, **not**
  `_module.args`, because reading it in `imports` would recurse infinitely.
  Consume it as `{ ryokuSession ? false, ... }:` and gate with
  `lib.optionals`. `home/modules/apps.nix` is the only aggregator that imports
  `home/configs/*` — `home.nix` never does.
- `home/configs/<app>/<app>.nix` is a thin session switcher that imports
  `themes/<session>.nix`. Add app config to the theme, not the dispatcher.
- **`.force = true` is required** on any `xdg.configFile` / `home.file` that
  manages a path a dotfile already exists at, or the build fails on collision.
- The `ryoku` NixOS output fights the shared `system/configuration.nix` with
  inline `lib.mkForce` overrides for niri/plasma6/`XDG_CURRENT_DESKTOP`. Editing
  `system/modules/desktop.nix` or `system/configs/services/services.nix` can
  break the `ryoku` generation silently. Some settings are also declared twice,
  once in each of those files.

## Secrets

sops-nix, age identity derived from `/home/thedreamdev/.ssh/id_ed25519`
(declared in `system/modules/sops.nix` on the system side, and inside
`home/modules/perla.nix` for home-manager). `age`/`sops`/`ssh-to-age` are
installed system-wide, so sops works without activating the flake.

`secrets/*.yaml` are committed encrypted. `.sops.yaml` has `creation_rules` for
`perla.yaml` and `perla-tokens.yaml` but **not** for `immich.yaml` — adding a key
there fails with "no matching creation rules found" unless you pass `--age`
explicitly. Never print decrypted values.

---

# Perla

Perla is a local AI companion — a voice/text assistant living on this laptop,
reachable from a hotkey, a wake word, a web UI, and a phone over Tailscale. It
is the largest and most actively-changed part of this repo, and it is
**home-manager only: every Perla change needs `rebuild-home`**.

Implementation is split in two:

- `home/modules/perla.nix` (802 lines) — the whole deployment: installed files,
  env vars, the five MCP servers, and eight systemd units.
- `home/modules/perla/` — the actual code: one Python daemon, four MCP servers,
  a fish/shell client, and the three UI source files.

Options live in `home/modules/perla/perla-config.nix` and reach the daemon purely
as `PERLA_*` environment variables. **The daemon reads no Nix config at
runtime** — it reads `os.environ`. A new setting is a Nix change, not a code
change.

## The central design idea: one brain, two sessions

`perla-companion.py` is **the only process holding conversation state.** This
replaced an older split where `perla.sh` talked to OpenCode directly and kept
its own session file, while the daemon only served the phone — which meant a
Tier 1 conversation started on your phone was a *different* session from the one
your laptop hotkey continued.

Now:

- Every surface — hotkey, wake word, web UI, phone — is a **client** of the one
  daemon's HTTP API. `perla.sh` is a thin local client: it captures mic audio,
  does hotkey/dmenu integration, and plays back audio locally, and nothing else.
- **Exactly two OpenCode sessions exist, ever:** Tier 1 and Tier 2. Never one per
  surface. A phone-started conversation and a laptop-started conversation are
  the same session.
- OpenCode session idle timeout is 10 minutes (`session_idle_timeout_minutes`);
  a single turn may run up to 900s (`turn_timeout_seconds`).

**Do not add a third session, and do not let a client cache session state.** That
is the whole architectural point, and reintroducing it is the most likely
regression you could cause.

### Request flow

```
surface (perla.sh / web UI / phone)
  → POST /api/voice | /api/text      (local: LOCAL_TOKEN, trusted on 127.0.0.1)
                                  (remote: gate-password → session token → /api/elevate)
  → process_message(message, tier, source, …)        perla-companion.py:3864
      → whisper-cli        (STT, voice only)
      → fold in file bodies / images
      → POST to opencode serve :13101 (tier 1) or :13102 (tier 2)
      → an ask() → /api/question, or a permission → /api/permission
         (the turn stays parked; the client answers and the turn resumes)
      → piper              (TTS, voice only)
      → log_request(...)   (appends to the vault's Conversations/)
      → is_memory_worthy(...) (maybe write Short-Term memory)
```

Note that **OpenCode has no document-ingestion channel.** Uploaded text files are
folded into the prompt text by `format_text_attachments`; images go as real
vision attachments. That's why the log needs `attachment_manifest_line` to strip
the file bodies back out before filing (see Conventions below).

## The tier model

| Tier | Name | Config | Port | What it is |
|---|---|---|---|---|
| 1 | voice / quick | inline `xdg.configFile."opencode/opencode-t1.json"` at `perla.nix:100` | `13101` | Restricted. Top-level `deny` on `edit`, `bash`, `webfetch`, `websearch`, `task`, `todowrite`, `lsp`, `skill`. Keeps the Obsidian MCP + the local MCPs; no superpowers. |
| 2 | "Full Mode" | `perla/opencode-t2-config.nix` → `opencode-t2.json` | `13102` | Unrestricted. Superpowers + the same local MCPs + edit/bash. |

Two details that are easy to break:

- **Tier 1's denies are top-level in the config, not per-agent.** Tier-1
  `opencode serve` sessions actually run as `agent=build`, so a deny nested
  under `agent.perla` was never consulted on a single real turn — Tier 1 was
  restricted by *instruction alone*. Both failure modes were observed live:
  1. it would write files inside the workspace, straight through the boundary
     `AGENTS.md` draws;
  2. asked to write *outside* the workspace (`/tmp`), the tool never returned
     at all — it sat at `status=running` forever, because an unanswered
     permission request has no UI to prompt in headless serve mode, so the user
     waited out the full 900s turn timeout with no reply and no error.

  An explicit top-level `deny` makes the tool error immediately, so the model
  reports the boundary in ~3s instead of hanging. A comment in `perla.nix` also
  records that a top-level *permission map* (rather than a flat deny) was tried
  and rejected — though that 403 warning was later re-tested against the
  currently deployed model and no longer applies.
- **Tier 2 is served through an isolated config dir** (`perla-t2-server` copies
  the t2 config into a scratch `XDG_CONFIG_HOME`). This is deliberate: your
  interactive `~/.config/opencode/opencode.json` must never be touched. Note the
  two server units use a **persistent** config dir, not `mktemp -d`, because
  they run under `Restart=on-failure`.

Tier 2 is what users are told to use for file editing, code, and arbitrary
commands; Tier 1's own prompt explicitly refuses those and points at it.

### The persona is a prompt, not a message

`persona.md` (18 KB) + `AGENTS.md` (12 KB) are concatenated into the Tier 1
**system prompt** at `perla.nix:143-144`. It is a system prompt rather than a
first message on purpose: a persona sent as a message can fade as the
conversation grows. Editing `persona.md` changes the daemon's persona hash,
which is how a long-lived session self-corrects (`perla-companion.py:2383`).

## ⚠️ `perla/AGENTS.md` is NOT a dev guide

`home/modules/perla/AGENTS.md` is **Perla's own runtime system prompt** — the
Tier 1 operational instructions, deployed to `~/.config/perla/AGENTS.md`. It
tells the model what Perla may and may not do. Editing it changes what the
assistant is told, not what the code does. The same applies to
`perla/persona.md` (identity/voice) and `perla/perla-agent.md` (the Tier 2 agent
definition).

If you were sent to fix Perla's behaviour, you are in the wrong file. Do not
treat their contents as project documentation.

## The safety model (this is the part to preserve)

Perla runs a model on a machine that holds SSH keys. The design is
**allowlist-shaped, never denylist-shaped**, and the comments say so repeatedly.
When adding a capability, follow the existing shape:

- **System actions are an explicit tool call, never keyword matching.** The old
  tier-0 dispatcher fired on substrings — "block" locked the screen, "commute"
  muted audio, "sleep well" suspended the machine. That is gone. `SYSTEM_ACTIONS`
  is a fixed tuple (`lock`, `shutdown`, `restart`, `suspend`, `mute`, `unmute`,
  `mute_mic`, `unmute_mic`, `play_pause`, `next_track`, `prev_track`,
  `open_app`, `open_folder`) and an action runs only when the model calls the
  tool with that exact name. `unlock` is deliberately absent.
- **Scoped commands select from a hardcoded argv table.** `run_scoped_command`
  takes a *name* that indexes `SCOPED_COMMANDS` (`disk_usage`, `memory_usage`,
  `uptime`, `tail_companion_log`, …). "No caller-supplied text ever becomes part
  of the argv." The one parameterized command, `restart_named_service`, has the
  argument *select among real units* — it is regex-validated against existing
  `systemd --user` units and never becomes a shell string.
- **The Drive denylist has one source of truth.** `fs_read_exclude_paths` in
  `perla-config.nix` (`.ssh`, `.gnupg`, `.config/sops`, `.password-store`,
  browser profiles, and the vault's `Memory/Long-Term`) is colon-joined into
  `PERLA_FS_READ_EXCLUDE` and enforced by the Drive browser — with a hardcoded
  fallback in the daemon so it is never silently empty. Edit the Nix list, not
  the daemon copy.
- **Open apps detached** (`setsid <app> &`). Bare `&` has been observed to crash
  Noctalia immediately on launch.

## The five local MCP servers

Each runs in its **own self-contained venv pinned to `mcp<2`** (2.x renamed
`FastMCP` → `MCPServer`, which breaks the imports). Sixth server is the Obsidian
bridge, pinned to `obsidian-mcp-server@3.2.9` — do not revert it to bare
`npx -y`, which silently drifts.

| Server | Source | Tools |
|---|---|---|
| obsidian | external, `npx` | vault read/write (gives the model its memory) |
| view-screen | `perla-view-screen-mcp.py` | `view_screen` |
| file | `perla-file-mcp.py` | `send_file`, `list_files` |
| reminders | `perla-reminders-mcp.py` | `create_reminder`, `list_reminders`, `cancel_reminder` |
| system-action | `perla-system-action-mcp.py` | `system_action` |

They all reach the daemon's `/api/internal/*` routes with `PERLA_COMPANION_PORT`
(default `8443`). Only `/api/internal/restart` is exempt from auth — deliberate
and local-only, so a broken session can be recovered.

`send_file` **never reads file contents**, for any type. It copies raw bytes. The
Tier 1 prompt is explicit about this so the model never hedges on a PDF.

## The vault

`~/Documents/Obsidian/PerlaNew`, a real Obsidian vault:

```
Conversations/    one appended block per turn, written ONLY by the daemon
Memory/Short-Term/ recent facts; the model may write here
Memory/Long-Term/ curated; read-only to Tier 1, promoted by the daily job
Memory/Archive/   pruned after memory_prune_days (14)
Command Log/      Scoped-command results
Reminders.md      owned by the reminders MCP, fired by perla-reminder-check
```

**`Conversations/` has exactly one writer — the daemon.** An earlier nightly job
also wrote to it, producing a duplicate block per turn that it then read back
and complained about. Never add a second writer. The log format is fixed:
`## HH:MM — Tier N (source)`.

Uploaded file bodies are **not** filed here. `process_message` keeps
`typed_message` and passes `attachment_manifest_line(...)` to `log_request`, so
the day file records `[attached: main.cpp (18 KB) — contents not logged]` while
the model still receives the real file. `is_memory_worthy` is likewise checked
against the typed text, so a source file containing the word "remember" can't
trigger a spurious memory write.

## Runtime services (`systemd --user`)

| Unit | Role |
|---|---|
| `perla-companion` | **the daemon.** Owns both OpenCode sessions, STT, TTS, the Drive, and vault logging. Port `8443`. |
| `perla-t1` | persistent `opencode serve --port 13101` |
| `perla-wakeword` | `wyoming-openwakeword` on `tcp://127.0.0.1:10400` |
| `perla-wakeword-listener` | feeds the wake-word server, default phrase `hey_jarvis` |
| `perla-promote` (timer) | daily Tier 2 job: short-term → long-term memory |
| `perla-reminder-check` (timer) | every 5 min, fires due reminders via the daemon's speak endpoint |

There is **no `perla-t2` unit** — Tier 2 is spawned on demand by the daemon.

Perla also reaches an Obsidian MCP server at `https://127.0.0.1:27124`
(self-signed → `OBSIDIAN_VERIFY_SSL=false`).

Check state with `systemctl --user status perla-companion perla-t1`. Both use
`Restart=on-failure` with `RestartSec = 5`, and the daemon re-reads its token
files on `SIGHUP` — which is how a secrets change takes effect **without a
restart**, so `systemctl --user reload-or-restart` is usually unnecessary.

### The daemon's HTTP surface

`do_GET`: `/api/health`, `/api/avatar`, `/api/voice/*`, `/api/audio/*`,
`/api/screenshot/*`, `/api/files/*`, `/api/history/days`, `/api/history/day`,
`/api/session/check`, `/api/scoped-commands`, `/api/reminders`,
`/api/drive/{list,download,view}`.

`do_POST`: `/api/gate`, `/api/text`, `/api/voice`, `/api/elevate`,
`/api/speak-local`, `/api/question`, `/api/permission`, `/api/transcribe`,
`/api/interrupt`, `/api/quick-action`, `/api/scoped-command`,
`/api/internal/{restart,screenshot,send-file,list-files,system-action}`,
`/api/drive/{mkdir,delete,restore,copy,move,upload,add-to-chat}`.

Everything except `/api/health` and `/api/gate` passes through `check_auth()`
(Bearer token). `/api/question` and `/api/permission` are the *resume* half of
parked turns: the model asked something, the client answered, the turn continues.

## The single-file UI build (read this before touching HTML/CSS/JS)

There is no bundler. `perla.nix` assembles `perla-companion.html` +
`perla-companion.css` + `perla-companion.js` into a **single**
`~/.config/perla/perla-companion.html` at build time, using
`builtins.replaceStrings` on the markers `/* @@PERLA_CSS@@ */` (html line 18)
and `// @@PERLA_JS@@`.

Consequences an agent will trip over:

- **The marker strings must appear exactly once.** `replaceStrings` replaces
  *every* occurrence — a second `@@PERLA_CSS@@` silently duplicates the whole
  stylesheet.
- **Never put the CSS/JS bodies in inline Nix `''...''` strings.** The JS has 95
  `${}` template literals that Nix would try to interpolate. They are read with
  `builtins.readFile`; keep it that way.
- **Do not strip/trim the bodies or append a trailing newline.** The CSS begins
  with four significant spaces and the JS with a blank line, and neither file
  ends in a newline; all of that is significant to the splice, and
  `test_html_build.sh` checks byte-equality.
- **All three sources must be committed.** `builtins.readFile` on an untracked
  path inside the flake fails to evaluate.
- After any UI change: `rebuild-home`, then `bash home/modules/perla/tests/run.sh`.
  `test_html_build.sh` compares the *deployed* file against the sources, so it
  fails on a not-yet-rebuilt tree — that failure is expected pre-deploy, not a
  real defect.

## Tests

`bash home/modules/perla/tests/run.sh` runs every `tests/test_*.sh` and prints a
summary. It is the only test infrastructure in the repo and it is Perla-only.

Current: 8 suites, 302 assertions. The runner deliberately reports `0 passed`
loudly rather than looking like a pass, so a green exit code is never mistaken
for coverage.

The house style, which new tests must follow: **every assertion is
mutation-tested.** Introduce a defect in the code, confirm the suite goes red,
revert. A test that has never been observed failing is not evidence. Watch for
a stub that makes the assertion vacuous — a DOM double which performs the very
behaviour under test will pass even when the real code is deleted.

`selection_dom_test.js` drives real functions in a jsdom harness. Two things
that cost time there: `const` declared inside `eval` does not survive the call
(extract-and-rewrite helpers to `window` properties), and jsdom has no layout
engine, so it can verify structure, classes, ordering, and the CSS cascade, but
**not pixel geometry or visual appearance**. For geometry, assert on the CSS
cascade by parsing the stylesheet and resolving the last matching `width`
declaration — that is how the sent-image row was verified.

## Conventions inside Perla

- The daemon is one large `perla-companion.py`; module boundaries are `# ===`
  banner comments and long docstrings, not classes everywhere.
- `perla-textify.py` rasterizes/converts uploaded documents. It is deployed as a
  **sibling** file and loaded by explicit path — the daemon is installed as an
  extensionless `~/.local/bin/perla-companion`, so a normal import can't work.
  The import is optional: if it fails, the daemon still starts and only document
  uploads report "not available".
- `perla-textify.py`'s runtime deps (`pypdf2image`, `python-docx`, `python-pptx`,
  `openpyxl`, `poppler-utils`, …) are **not** declared in the module — they are
  commented as a known gap. If a `.pdf`/`.pptx`/`.docx` upload silently fails to
  convert, that is why.
- `perla.sh` is the local hotkey/voice client and sources the same env file the
  daemon uses, with a **client-side twin of the turn cap**. If the two disagree
  you get truncated turns — change both.
- TTS strips code blocks and drops timestamp artefacts before speaking (piper
  reciting code character-by-character is useless). Code is described, not read.
- Version commits look like `v26.10.2.4` (`v<YY>.<M>.<D>.<n>`, sometimes with a
  repeated suffix for a follow-up) and use that tag as the entire commit subject.
  `CHANGELOG.md` is tracked but deliberately **terse**: a `# Version X` heading
  plus one or two short bullets naming what changed. Do not write paragraphs
  there — a long prose entry was tried and reverted.

## Gotchas

- **`perla-textify.py` needs its deps declared in the module** if you touch
  document conversion; today they are an acknowledged gap, not an oversight you
  introduced.
- `shells/shell.nix` is **dead** — not imported, and it `builtins.fetchTarball`s
  a pinned nixpkgs instead of following the flake. The real shells are the
  `devShells` in `flake.nix` (`nix develop`, `nix develop .#python`).
- `pkgs/sf-pro-fonts/` is unreferenced by any overlay.
- `configs/` at the repo root is **not** `home/configs/`. Nearly all of it is
  orphaned (kitty.conf, init.vim, fastfetch assets) — nvim is configured through
  nixvim and kitty's theme is generated by Noctalia. Only one file is referenced,
  by absolute path. Don't go looking there.
- `programs.home-manager.enable = true;` in `home/home.nix` is not a real
  home-manager option; it has no effect. Don't propagate it.
- `system/hardware-configuration.nix` is a generated, committed,
  machine-specific artifact. Don't edit it.
- `home/home-ryoku.nix` intentionally lacks the three `.force = true` lines that
  `home/home.nix` has. That difference is deliberate.
- `perla.nix` hardcodes `/home/thedreamdev/...` in several places
  (`sops.age.sshKeyPaths`, the `audio_input` ALSA device, `fastfetch`'s asset
  path), so the config is **not relocatable**.
- Deferred known gaps (from Perla work, not yet fixed): real microphone
  testing, `always` permission persistence, stale sessions carrying old
  `Conversations/` instructions, daemon route smoke tests. Don't assume these
  are done.
- `docs/` and `.superpowers/` are gitignored local scratch. Don't force-add
  them. The old README is still the nixos-generate-config default and is
  inaccurate — this file supersedes it.
