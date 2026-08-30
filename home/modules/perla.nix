{ config, pkgs, lib, ... }:
let
  cfg = (import ./perla/perla-config.nix {
    homeDirectory = config.home.homeDirectory;
  }).perla;
in {
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

  home.packages = with pkgs; [
    whisper-cpp
    piper-tts
    fuzzel
    wyoming-openwakeword
    python3
    curl
    nodejs
    libnotify
    grim
  ];

  # === Wrapper script ===
  home.file.".local/bin/perla" = {
    force = true;
    source = ./perla/perla.sh;
    executable = true;
  };

  # === Persona prompt ===
  home.file.".config/perla/persona.md" = {
    force = true;
    source = ./perla/persona.md;
  };

  # === AGENTS.md for OpenCode Tier 1 ===
  home.file.".config/perla/AGENTS.md" = {
    force = true;
    source = ./perla/AGENTS.md;
  };

  # === OpenCode agent definition (provides Perla identity at position 5 — overrides default prompt) ===
  xdg.configFile."opencode/agent/perla.md" = {
    force = true;
    source = ./perla/perla-agent.md;
  };

  # === OpenCode Tier 1 config (no superpowers — Obsidian MCP only) ===
  xdg.configFile."opencode/opencode-t1.json" = {
    force = true;
    text = builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      model = cfg.opencode_model;
      instructions = [ (builtins.readFile ./perla/AGENTS.md) ];
      permission = {
        bash = "deny";
        edit = "deny";
        webfetch = "deny";
        task = "deny";
        todowrite = "deny";
        websearch = "deny";
        lsp = "deny";
        skill = "deny";
      };
      agent = {
        perla = {
          description = "${cfg.assistant_name} — personal AI assistant";
          mode = "primary";
          prompt = builtins.readFile ./perla/perla-agent.md;
          permission = {
            bash = "deny";
            edit = "deny";
            webfetch = "deny";
            task = "deny";
            todowrite = "deny";
            websearch = "deny";
            lsp = "deny";
            skill = "deny";
          };
        };
      };
      provider = {
        ollama = {
          npm = "@ai-sdk/openai-compatible";
          name = "Ollama (local)";
          options = {
            baseURL = "http://localhost:11434/v1";
          };
          models = {
            "${cfg.ollama_model}" = {
              name = "${cfg.assistant_name} (local)";
            };
          };
        };
      };
      mcp = {
        obsidian = {
          type = "local";
          command = [ "${config.home.homeDirectory}/.local/bin/perla-obsidian-mcp" ];
          env = {
            OBSIDIAN_BASE_URL = "https://127.0.0.1:27124";
            OBSIDIAN_VERIFY_SSL = "false";
          };
        };
        view-screen = {
          type = "local";
          command = [ "${config.home.homeDirectory}/.local/bin/perla-view-screen-mcp" ];
          env = {
            PERLA_COMPANION_PORT = "8443";
          };
        };
        reminders = {
          type = "local";
          command = [ "${config.home.homeDirectory}/.local/bin/perla-reminders-mcp" ];
          env = {
            PERLA_COMPANION_PORT = "8443";
          };
        };
        system-action = {
          type = "local";
          command = [ "${config.home.homeDirectory}/.local/bin/perla-system-action-mcp" ];
          env = {
            PERLA_COMPANION_PORT = "8443";
          };
        };
      };
    };
  };

  # === Sops: decrypt secrets at rebuild time ===
  sops = {
    defaultSopsFile = ../../secrets/perla.yaml;
    age.sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
    secrets."perla/obsidian_api_key" = {
      path = "${config.home.homeDirectory}/.config/perla/secrets/obsidian-api-key";
      mode = "0400";
    };
  };

  # === Sops: token secrets (separate encrypted file) ===
  sops.secrets."perla/remote_token" = {
    sopsFile = ../../secrets/perla-tokens.yaml;
    path = "${config.home.homeDirectory}/.config/perla/secrets/remote-token";
    mode = "0400";
  };
  sops.secrets."perla/elevate_token" = {
    sopsFile = ../../secrets/perla-tokens.yaml;
    path = "${config.home.homeDirectory}/.config/perla/secrets/elevate-token";
    mode = "0400";
  };
  # Fixed token so perla.sh (the local hotkey/voice client) authenticates to
  # perla-companion as a trusted local caller instead of going through the
  # phone's gate-password flow. Never leaves the machine — only ever sent to
  # 127.0.0.1. Generate with e.g. `openssl rand -hex 32` and add under
  # perla/local_token in secrets/perla-tokens.yaml, same as the entries above.
  sops.secrets."perla/local_token" = {
    sopsFile = ../../secrets/perla-tokens.yaml;
    path = "${config.home.homeDirectory}/.config/perla/secrets/local-token";
    mode = "0400";
  };

  # Reload companion daemon when secrets change (SIGHUP re-reads token files)
  home.activation.reload-perla = lib.mkAfter ''
    pkill -HUP -f perla-companion || true
  '';

  # === Perla environment file (sourced by wrapper script) ===
  home.file.".config/perla/perla.env" = {
    force = true;
    text = ''
      PERLA_NAME="${cfg.assistant_name}"
      PERLA_PERSONA="${cfg.persona_prompt}"
      PERLA_MODEL="${cfg.opencode_model}"
      PERLA_VAULT="${cfg.vault_path}"
      PERLA_VOICE="${cfg.voice_model}"
      PERLA_WHISPER_MODEL="${cfg.whisper_model}"
      PERLA_WHISPER_LANG="${cfg.whisper_lang}"
      PERLA_IDLE_MINUTES=${toString cfg.session_idle_timeout_minutes}
      PERLA_AUDIO_INPUT="${cfg.audio_input}"
    '';
  };

  # === Obsidian MCP bridge (reads API key from sops-decrypted file) ===
  home.file.".local/bin/perla-obsidian-mcp" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      SECRET="''${XDG_CONFIG_HOME:-$HOME/.config}/perla/secrets/obsidian-api-key"
      if [ -f "$SECRET" ]; then
        OBSIDIAN_API_KEY="$(cat "$SECRET")"
        export OBSIDIAN_API_KEY
      else
        echo "ERROR: Obsidian API key not found at $SECRET" >&2
        exit 1
      fi
      export OBSIDIAN_BASE_URL="https://127.0.0.1:27124"
      export OBSIDIAN_VERIFY_SSL="false"
      # PINNED to 3.2.9 (confirmed current npm "latest" as of 2026-07-18).
      # Do not revert to a bare "obsidian-mcp-server" (unversioned npx -y).
      # cyanheads/obsidian-mcp-server has shipped multiple breaking rewrites
      # over its history with different tool/output-schema shapes each time.
      # An unpinned npx -y can silently resolve to a newer version than
      # whatever OpenCode's MCP client cached/validated against, producing
      # schema-mismatch errors (-32602) on every call, as seen in production.
      # Manually verified 2026-07-18: `npx -y obsidian-mcp-server@3.2.9`
      # starts cleanly and lists all 14 tools with no schema error at
      # startup. Tool-call-level behavior should still be spot-checked
      # (e.g. via `npx @modelcontextprotocol/inspector`) after any bump.
      exec npx -y obsidian-mcp-server@3.2.9
    '';
  };

  # === view_screen MCP server (lets the model decide for itself when it
  # needs to look at the screen, e.g. "what song is playing on my
  # screen" — no fixed phrase list to keep out of date). The actual
  # capture/lock-check logic lives entirely in perla-companion.py
  # (capture_screenshot(), already used by the tier0 screenshot command);
  # this script only exposes it as a tool the model can call. ===
  home.file.".local/bin/perla-view-screen-mcp-impl.py" = {
    force = true;
    source = ./perla/perla-view-screen-mcp.py;
  };

  home.file.".local/bin/perla-view-screen-mcp" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      # Self-contained venv so this doesn't depend on a system-wide `mcp`
      # package being packaged in nixpkgs (as of writing it isn't a
      # standard nixpkgs attribute). Built once, reused after.
      # PINNED to mcp<2: the 2.x release renamed FastMCP to MCPServer and
      # changed other APIs (see the mcp 2.x import error message itself,
      # which links to its own migration guide). Do not remove the pin —
      # an unpinned install can silently jump to 2.x and break this
      # script's `from mcp.server.fastmcp import FastMCP, Image` line.
      VENV_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/perla/view-screen-mcp-venv"
      MARKER="$VENV_DIR/.mcp-1x-installed"
      if [ ! -f "$MARKER" ]; then
        rm -rf "$VENV_DIR"
        python3 -m venv "$VENV_DIR"
        "$VENV_DIR/bin/pip" install --quiet "mcp<2"
        touch "$MARKER"
      fi
      export PERLA_COMPANION_PORT="''${PERLA_COMPANION_PORT:-8443}"
      exec "$VENV_DIR/bin/python3" "$HOME/.local/bin/perla-view-screen-mcp-impl.py"
    '';
  };

  # === reminders MCP server (Lets Tier-1 Perla create/cancel/list
  # reminders through a first-class tool instead of appending to
  # Reminders.md by hand — the file lives at the vault root, outside the
  # Tier-1 writable allowlist in AGENTS.md, which caused voice/quick
  # replies to refuse or silently fake reminder writes). The schema and
  # storage logic stay entirely in perla-companion.py (_append_reminder /
  # _cancel_reminder via POST /api/reminders); this script only proxies
  # the tool calls, same thin shape as the view-screen MCP server. ===
  home.file.".local/bin/perla-reminders-mcp-impl.py" = {
    force = true;
    source = ./perla/perla-reminders-mcp.py;
  };

  home.file.".local/bin/perla-reminders-mcp" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      # Same self-contained venv pattern / mcp<2 pin as the view-screen MCP
      # wrapper — see that comment for why it can't use a system `mcp`.
      VENV_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/perla/reminders-mcp-venv"
      MARKER="$VENV_DIR/.mcp-1x-installed"
      if [ ! -f "$MARKER" ]; then
        rm -rf "$VENV_DIR"
        python3 -m venv "$VENV_DIR"
        "$VENV_DIR/bin/pip" install --quiet "mcp<2"
        touch "$MARKER"
      fi
      export PERLA_COMPANION_PORT="''${PERLA_COMPANION_PORT:-8443}"
      exec "$VENV_DIR/bin/python3" "$HOME/.local/bin/perla-reminders-mcp-impl.py"
    '';
  };

  # === system_action MCP server (Replaces the old pre-LLM //word-substring//
  # tier0 dispatcher in perla-companion.py, which fired on accidental matches
  # like "code block" -> lock screen. Now EVERY message goes to the model, and
  # system actions (lock, shutdown, restart, suspend, mute, unmute, open_app,
  # open_folder) only run when the model deliberately calls this tool. The
  # allowlist + execution live in perla-companion.py (execute_system_action
  # behind POST /api/internal/system-action); this script only proxies, same
  # thin shape as the reminders / view-screen MCP servers. ===
  home.file.".local/bin/perla-system-action-mcp-impl.py" = {
    force = true;
    source = ./perla/perla-system-action-mcp.py;
  };

  home.file.".local/bin/perla-system-action-mcp" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      # Same self-contained venv pattern / mcp<2 pin as the other MCP wrappers
      # — see the view-screen wrapper comment for why it can't use a system `mcp`.
      VENV_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/perla/system-action-mcp-venv"
      MARKER="$VENV_DIR/.mcp-1x-installed"
      if [ ! -f "$MARKER" ]; then
        rm -rf "$VENV_DIR"
        python3 -m venv "$VENV_DIR"
        "$VENV_DIR/bin/pip" install --quiet "mcp<2"
        touch "$MARKER"
      fi
      export PERLA_COMPANION_PORT="''${PERLA_COMPANION_PORT:-8443}"
      exec "$VENV_DIR/bin/python3" "$HOME/.local/bin/perla-system-action-mcp-impl.py"
    '';
  };

  # === wake word listener script ===
  home.file.".local/bin/perla-wakeword-listener" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env python3
      """Wyoming protocol listener for openWakeWord detection events."""
      import socket, struct, subprocess, time, sys

      HOST = '127.0.0.1'
      PORT = 10400

      def read_frame(sock):
          header = sock.recv(12)
          if len(header) < 12:
              return None
          payload_type, payload_size = struct.unpack('>BI', header[8:12])
          payload = b""
          while len(payload) < payload_size:
              chunk = sock.recv(payload_size - len(payload))
              if not chunk:
                  return None
              payload += chunk
          return {'type': payload_type, 'payload': payload}

      def main():
          sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
          sock.settimeout(30)
          try:
              sock.connect((HOST, PORT))
          except ConnectionRefusedError:
              time.sleep(2)
              return

          audio_start = struct.pack('>BHI', 0x01, 0x00, 0)  # audio-start
          sock.sendall(audio_start)
          print('perla-wakeword-listener: connected', flush=True)

          while True:
              frame = read_frame(sock)
              if frame is None:
                  break
              if frame['type'] == 0x05:  # detection
                  print('perla-wakeword-listener: wake word detected', flush=True)
                  subprocess.Popen(
                      ['perla', 'voice'],
                      stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL
                  )

      if __name__ == '__main__':
          while True:
              try:
                  main()
              except Exception as e:
                  print(f'perla-wakeword-listener: error {e}', flush=True)
                  time.sleep(3)
    '';
  };

  # === Companion backend — the single unified daemon ===
  # Owns OpenCode sessions (one per tier, shared by every surface), STT,
  # TTS, tier0 direct dispatch, and vault logging. perla.sh (local
  # hotkey/voice) and the phone both talk to this over HTTP — perla.sh via
  # 127.0.0.1 with local-token auth, phone via Tailscale with the
  # gate-password -> session-token flow. This is what makes a Tier 1
  # conversation started on the phone continue seamlessly from the laptop
  # hotkey: there's exactly one OpenCode session per tier, not one per
  # surface.
  home.file.".local/bin/perla-companion" = {
    force = true;
    source = ./perla/perla-companion.py;
    executable = true;
  };

  home.file.".config/perla/perla-companion.html" = {
    force = true;
    source = ./perla/perla-companion.html;
  };

  # === Profile picture (avatar shown in the companion UI: gate screen,
  # header, and favicon) ===
  home.file.".config/perla/profile.jpg" = {
    force = true;
    source = ./perla/profile.jpg;
  };

  # === T1 OpenCode server (restricted — Obsidian MCP only, no shell) ===
  home.file.".local/bin/perla-t1-server" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      # Persistent, reusable config dir — NOT mktemp -d. This runs under a
      # systemd service with Restart=on-failure, so a fresh mktemp -d here
      # leaked one full copy of ~/.config/opencode into /tmp on every
      # (re)start, with nothing ever cleaning it up.
      config_home="''${XDG_RUNTIME_DIR:-/tmp}/perla/t1-config"
      mkdir -p "$config_home/opencode"
      if [ ! -f "$config_home/.synced" ] || [ "$HOME/.config/opencode" -nt "$config_home/.synced" ]; then
        cp -r "$HOME/.config/opencode/"* "$config_home/opencode/"
        cp "$HOME/.config/opencode/opencode-t1.json" "$config_home/opencode/opencode.json"
        touch "$config_home/.synced"
      fi
      export XDG_CONFIG_HOME="$config_home"
      exec opencode serve --port 13101
    '';
  };

  systemd.user.services.perla-t1 = {
    Unit = {
      Description = "${cfg.assistant_name} Tier 1 OpenCode server";
      After = [ "pipewire.service" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "%h/.local/bin/perla-t1-server";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # === Noctalia dmenu entry ===
  # Noctalia substitutes {selection} into exec, so picking "Tier 1"/"Tier 2"
  # in the /perla launcher menu passes the tier straight to `perla voice` —
  # no second menu, no separate hotkey hop. (The old "perla hotkey" exec
  # ignored the selection and re-opened perla's own menu: the double prompt.)
  programs.noctalia.settings = {
    shell.launcher.dmenu.entry.perla = {
      command = "printf 'Tier 1\nTier 2\n'";
      label = cfg.assistant_name;
      prefix = "/perla";
      glyph = "user";
      global = true;
      exec = "perla voice \"{selection}\"";
    };
  };

  # === Wake word service ===
  systemd.user.services.perla-wakeword = {
    Unit = {
      Description = "${cfg.assistant_name} wake word detection";
      After = [ "pipewire.service" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.wyoming-openwakeword}/bin/wyoming-openwakeword --uri 'tcp://127.0.0.1:10400'";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.perla-wakeword-listener = {
    Unit = {
      Description = "${cfg.assistant_name} wake word listener";
      After = [ "perla-wakeword.service" "pipewire.service" ];
      BindsTo = [ "perla-wakeword.service" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "%h/.local/bin/perla-wakeword-listener";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # === Companion web API service ===
  systemd.user.services.perla-companion = {
    Unit = {
      Description = "${cfg.assistant_name} companion web API";
      After = [ "pipewire.service" "perla-t1.service" ];
    };
    Service = {
      Type = "simple";
      Environment = [
        "PERLA_NAME=${cfg.assistant_name}"
        "PERLA_PERSONA=${cfg.persona_prompt}"
        "PERLA_MODEL=${cfg.opencode_model}"
        "PERLA_VAULT=${cfg.vault_path}"
        "PERLA_WHISPER_MODEL=${cfg.whisper_model}"
        "PERLA_WHISPER_LANG=${cfg.whisper_lang}"
        "PERLA_AUDIO_DIR=%h/.local/share/perla-audio"
        "PERLA_COMPANION_PORT=8443"
        "PERLA_GATE_PASSWORD=${cfg.gate_password}"
      ];
      ExecStart = "%h/.local/bin/perla-companion";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # === Daily memory promotion ===
  systemd.user.services.perla-promote = {
    Unit.Description = "${cfg.assistant_name} daily memory promotion";
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.local/bin/perla text 2 'Review today''s short-term memory. Promote durable facts to long-term. Archive entries older than ${toString cfg.memory_prune_days} days.'";
    };
  };

  systemd.user.timers.perla-promote = {
    Unit.Description = "${cfg.assistant_name} daily memory promotion timer";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # === Reminder checker ===
  # Scans Reminders.md every 5 min and fires anything due — unprompted, no
  # active conversation needed. Calls perla-companion's local speak endpoint
  # for TTS plus notify-send, so it depends on the companion daemon being up
  # (not a hard dependency — if the daemon's down the checker just logs a
  # warning and the desktop notification still fires).
  home.file.".local/bin/perla-reminder-check" = {
    force = true;
    source = ./perla/perla-reminder-check.py;
    executable = true;
  };

  systemd.user.services.perla-reminder-check = {
    Unit = {
      Description = "${cfg.assistant_name} reminder check";
      After = [ "pipewire.service" "perla-companion.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.local/bin/perla-reminder-check";
    };
  };

  systemd.user.timers.perla-reminder-check = {
    Unit.Description = "${cfg.assistant_name} reminder check timer";
    Timer = {
      OnCalendar = "*:0/5"; # every 5 minutes
      Persistent = true;    # catches up on missed ticks after sleep/reboot —
                             # this is what makes "missed" reminders actually
                             # fire once the machine wakes back up
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
