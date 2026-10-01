# Builder for the OpenCode Tier 2 config (full mode).
#
# Tier 2 is Perla's unrestricted tier: the primary agent is the stock
# opencode one (superpowers plugin included, NO blanket permission denies —
# it can ask to edit/bash/etc., "full mode"). What the tier-2 config FIXES
# is tool access: it enables the same local Perla MCP servers Tier 1 has
# (obsidian, view-screen, reminders, system-action), which a hand-managed
# ~/.config/opencode/opencode.json couldn't be trusted to keep in sync.
#
# NOTE: `model` is nominal — perla-companion.py forces the model per request
# (model_part), so opencode's default here is only what `opencode serve`
# advertises.
#
# Kept as a pure function (no pkgs/lib) so a throwaway test can evaluate it
# with a stub homeDirectory and assert the resulting JSON.
{ homeDirectory, model, filesDir }:
builtins.toJSON {
  "$schema" = "https://opencode.ai/config.json";

  model = model;
  small_model = model;

  # Full mode: superpowers workflow skills are available here (unlike Tier 1).
  plugin = [ "superpowers@git+https://github.com/obra/superpowers.git" ];

  # Tier 2 previously had NO system prompt at all — Perla's identity was only
  # ever a paste into the first user message, so it was the tier most exposed
  # to losing her voice as a conversation grew. Both halves now live here as
  # instructions, re-sent on every request:
  #   1. the shared persona (identity/personality), and
  #   2. the Full Mode file-handling rules, relocated verbatim out of
  #      perla-companion.py's paste path.
  instructions = [
    (builtins.readFile ./persona.md)
    ''
      ---

      ## File handling (Full Mode)
      When asked to create a file (a document, script, export, whatever),
      save it under ${filesDir} by default unless the user names a different
      location. After creating a file the user should receive, call the
      `send_file` tool with its filename so it actually reaches them in the
      chat — writing the file alone does not deliver it.

      When asked to send, share, or deliver a file that already exists
      ("send me X", "can I get that file", "send /path/to/thing.png"), you
      MUST call the `send_file` tool — do not just describe, comment on, or
      answer questions about the file instead of sending it, and do not
      treat the request as answered until the tool has actually run.
      `send_file` never opens or reads the file's contents (this applies to
      every file type, including PDFs and images) — it only copies the raw
      bytes for download, so there is no file type you can't send. Never
      comment on, describe, or guess at a file's contents from its name
      alone; you have not seen them. `send_file` also searches Downloads,
      Documents, and Pictures in addition to ${filesDir}; if it comes back
      with multiple or no candidates, ask the user which one they meant
      rather than guessing, and if a specific path you tried comes back with
      no matches, say plainly that the path doesn't exist or the name
      doesn't match rather than inventing a different explanation.
    ''
  ];

  provider = {
    ollama = {
      npm = "@ai-sdk/openai-compatible";
      name = "Ollama (local)";
      options = {
        baseURL = "http://localhost:11434/v1";
      };
      models = {
        "dolphin-phi" = {
          name = "Dolphin Phi 2.7B";
        };
      };
    };
  };

  mcp = {
    obsidian = {
      type = "local";
      command = [ "${homeDirectory}/.local/bin/perla-obsidian-mcp" ];
      environment = {
      # OpenCode's McpLocalConfig type spells this `environment`; a bare
      # `env` is the lsp key and is silently ignored here, so the
      # server falls back to its own defaults.
        OBSIDIAN_BASE_URL = "https://127.0.0.1:27124";
        OBSIDIAN_VERIFY_SSL = "false";
      };
    };
    view-screen = {
      type = "local";
      command = [ "${homeDirectory}/.local/bin/perla-view-screen-mcp" ];
      environment = {
      # OpenCode's McpLocalConfig type spells this `environment`; a bare
      # `env` is the lsp key and is silently ignored here, so the
      # server falls back to its own defaults.
        PERLA_COMPANION_PORT = "8443";
      };
    };
    file = {
      type = "local";
      command = [ "${homeDirectory}/.local/bin/perla-file-mcp" ];
      environment = {
      # OpenCode's McpLocalConfig type spells this `environment`; a bare
      # `env` is the lsp key and is silently ignored here, so the
      # server falls back to its own defaults.
        PERLA_COMPANION_PORT = "8443";
        PERLA_TIER = "2";
      };
    };
    reminders = {
      type = "local";
      command = [ "${homeDirectory}/.local/bin/perla-reminders-mcp" ];
      environment = {
      # OpenCode's McpLocalConfig type spells this `environment`; a bare
      # `env` is the lsp key and is silently ignored here, so the
      # server falls back to its own defaults.
        PERLA_COMPANION_PORT = "8443";
      };
    };
    system-action = {
      type = "local";
      command = [ "${homeDirectory}/.local/bin/perla-system-action-mcp" ];
      environment = {
      # OpenCode's McpLocalConfig type spells this `environment`; a bare
      # `env` is the lsp key and is silently ignored here, so the
      # server falls back to its own defaults.
        PERLA_COMPANION_PORT = "8443";
      };
    };
  };

  lsp = {
    gdscript = {
      command = [ "${homeDirectory}/.npm-global/bin/godot-lsp-stdio-bridge" ];
      extensions = [ ".gd" ".gdshader" ];
    };
  };
}