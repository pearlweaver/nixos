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
{ homeDirectory, model }:
builtins.toJSON {
  "$schema" = "https://opencode.ai/config.json";

  model = model;
  small_model = model;

  # Full mode: superpowers workflow skills are available here (unlike Tier 1).
  plugin = [ "superpowers@git+https://github.com/obra/superpowers.git" ];

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
      env = {
        OBSIDIAN_BASE_URL = "https://127.0.0.1:27124";
        OBSIDIAN_VERIFY_SSL = "false";
      };
    };
    view-screen = {
      type = "local";
      command = [ "${homeDirectory}/.local/bin/perla-view-screen-mcp" ];
      env = {
        PERLA_COMPANION_PORT = "8443";
      };
    };
    reminders = {
      type = "local";
      command = [ "${homeDirectory}/.local/bin/perla-reminders-mcp" ];
      env = {
        PERLA_COMPANION_PORT = "8443";
      };
    };
    system-action = {
      type = "local";
      command = [ "${homeDirectory}/.local/bin/perla-system-action-mcp" ];
      env = {
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