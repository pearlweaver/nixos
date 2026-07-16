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
        };
      };
    };
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
      OBSIDIAN_API_KEY="${cfg.obsidian_api_key}"
    '';
  };

  # === Obsidian MCP bridge (reads API key from perla.env — never stored in nix store) ===
  home.file.".local/bin/perla-obsidian-mcp" = {
    force = true;
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      ENV="''${XDG_CONFIG_HOME:-$HOME/.config}/perla/perla.env"
      if [ -f "$ENV" ]; then
        . "$ENV"
      fi
      export OBSIDIAN_API_KEY
      exec npx -y obsidian-mcp-server
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
