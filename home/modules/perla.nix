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
        write = "deny";
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

  # === Companion backend (phone-facing web API) ===
  home.file.".local/bin/perla-companion" = {
    force = true;
    source = ./perla/perla-companion.py;
    executable = true;
  };

  home.file.".config/perla/perla-companion.html" = {
    force = true;
    source = ./perla/perla-companion.html;
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
  programs.noctalia.settings = {
    shell.launcher.dmenu.entry.perla = {
      command = "printf 'Quick chat\nFull mode\n'";
      label = cfg.assistant_name;
      prefix = "/perla";
      glyph = "user";
      global = true;
      exec = "perla hotkey";
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
}
