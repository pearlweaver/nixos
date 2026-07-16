# Version 26.7.9.1

- Trying to add a pure black monochrome theme

# Perla Setup

## Overview
Perla is a personal AI assistant on NixOS with voice/text input, tiered security, persistent Obsidian vault memory, wake-word detection, and fast response times via a persistent OpenCode server.

## Dependencies
- **NixOS** with flakes enabled
- **Noctalia** launcher v5 (dmenu entries)
- **fuzzel** for free text input fallback
- **OpenCode** CLI (`opencode`) — [install](https://opencode.ai)
- **Obsidian** with `coddingtonbear/obsidian-local-rest-api` plugin
- **Ollama** (optional, for local models)

## Files to Copy

### Core module (`home/modules/perla/`)
| File | Purpose |
|------|---------|
| `perla.nix` | Home-manager module: deploys scripts, configs, persona, services |
| `perla-config.nix` | Single config file for all mutable values (name, model, voice, vault, API key, exclusions, timeouts) |
| `perla.sh` | Main wrapper script: Noctalia dmenu, voice capture (whisper-cpp), STT, TTS (piper), OpenCode server management |
| `persona.md` | Canonical persona/identity guidelines |
| `AGENTS.md` | Tier 1 agent instructions (memory system, boundary rules, error handling) |
| `perla-agent.md` | OpenCode agent definition (references persona.md as canonical) |

### Config files (deployed to `~/.config/opencode/`)
| File | Purpose |
|------|---------|
| `opencode.json` | Tier 2 config (superpowers plugin + Obsidian MCP + Ollama provider + model) |
| `opencode-t1.json` | Tier 1 config (Obsidian MCP only, no superpowers, top-level tool permissions denying all dangerous tools) |

### Other deployed files
| File | Destination | Purpose |
|------|-------------|---------|
| `perla.sh` | `~/.local/bin/perla` | Main entry point |
| `persona.md` | `~/.config/perla/persona.md` | Identity/personality |
| `AGENTS.md` | `~/.config/perla/AGENTS.md` | Tier 1 agent instructions |
| `perla-agent.md` | `~/.config/opencode/agent/perla.md` | OpenCode agent definition |
| `perla.env` | `~/.config/perla/perla.env` | Runtime env vars |
| `perla-obsidian-mcp` | `~/.local/bin/perla-obsidian-mcp` | Obsidian MCP bridge (reads API key from perla.env) |
| `perla-wakeword-listener` | `~/.local/bin/perla-wakeword-listener` | Wake word detection listener (currently disabled) |

## Setup Steps

### 1. Clone the flake
```bash
git clone https://github.com/yourusername/nixos-config.git ~/nixos-config
cd ~/nixos-config
```

### 2. Configure `perla-config.nix`
Edit `home/modules/perla/perla-config.nix`:
```nix
{
  perla = {
    assistant_name = "Perla";
    wake_word = "alexa";  # default model, custom requires training

    vault_path = "/home/YOUR_USER/Documents/Obsidian/Perla";
    persona_prompt = "/home/YOUR_USER/.config/perla/persona.md";

    voice_model = "en_US-libritts_r-medium";  # piper voice
    whisper_model = "tiny";
    whisper_lang = "en";

    obsidian_api_key = "YOUR_API_KEY";  # from Obsidian Local REST API plugin settings

    opencode_model = "opencode/deepseek-v4-flash-free";
    ollama_model = "qwen2.5:3b";  # only used if Ollama provider is active

    session_idle_timeout_minutes = 10;
    memory_prune_days = 14;

    audio_input = "alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__hw_sofhdadsp__source";

    fs_read_exclude_paths = [
      ".ssh" ".gnupg" ".config/sops" ".config/opencode"
      ".password-store" ".local/share/keyrings" ".mozilla"
      ".config/google-chrome" ".config/chromium" ".env" ".envrc"
      "Documents/Obsidian/Perla/Memory/Long-Term"
    ];
  };
}
```

### 3. Set up Obsidian vault
1. Open Obsidian
2. Create vault at `~/Documents/Obsidian/Perla`
3. Install `coddingtonbear/obsidian-local-rest-api` plugin via Community Plugins
4. Enable local REST API and copy the API key to `perla-config.nix`
5. Create folder structure:
   - `Conversations/`
   - `Memory/Short-Term/`
   - `Memory/Long-Term/`
   - `Command Log/`

### 4. Enable the module
Add to `home/default.nix` or your home-manager imports:
```nix
imports = [
  ./modules/perla.nix
];
```

### 5. Install required CLI tools
```bash
# Install OpenCode (https://opencode.ai/docs/install)
# Install nix packages:
home-manager switch --flake ~/nixos-config
```

This installs: `whisper-cpp`, `piper-tts`, `fuzzel`, `wyoming-openwakeword`, `python3`, `curl`, `nodejs`, `libnotify`.

### 6. Configure Niri keybind
In `home/modules/niri.nix`, add:
```nix
"Mod+Shift+Space".action.spawn = [ "/home/YOUR_USER/.local/bin/perla" "hotkey" ];
```

Remove any conflicting keybind (e.g., if `Mod+Shift+Space` is used for play-pause, move it to `Mod+Shift+P`).

### 7. Set up Noctalia launcher
In your Noctalia config, add dmenu entry:
```nix
programs.noctalia.settings = {
  shell.launcher.dmenu.entry.perla = {
    command = "printf 'Quick chat\nFull mode\n'";
    label = "Perla";
    prefix = "/perla";
    glyph = "user";
    global = true;
    exec = "perla hotkey";
  };
};
```

### 8. Pre-download Piper voice
```bash
curl -L "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/libritts_r/medium/en_US-libritts_r-medium.onnx" \
  -o ~/.local/share/piper-tts/voices/en_US-libritts_r-medium.onnx
curl -L "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/libritts_r/medium/en_US-libritts_r-medium.onnx.json" \
  -o ~/.local/share/piper-tts/voices/en_US-libritts_r-medium.onnx.json
```

### 9. Build and activate
```bash
home-manager switch --flake ~/nixos-config
```

### 10. Restart session
Log out and back in (or `source /etc/profiles/per-user/YOUR_USER/etc/profile.d/hm-session-vars.sh`) so `~/.local/bin` is in `PATH`.

## Usage

### Hotkey
Press `Mod+Shift+Space` → pick "Quick chat" (voice) or "Full mode" (voice, same) → speak after "Listening..." notification → wait for TTS response.

### Keybinds
- `Mod+Shift+Space` → Perla menu (voice input, Tier 2 with full superpowers)

### Tier 0 (instant actions, no OpenCode)
Say during a voice session:
- "Open Firefox" → launches Firefox via `systemd-run --user --scope`
- "Open terminal" → launches Kitty
- "Open code" → launches Codium
- "Lock" → locks screen
- "Mute" / "Unmute" → toggles audio
- "Screenshot" → saves to `~/Pictures/Screenshots/`
- "Suspend" / "Sleep" → system suspend

## Architecture

### Tiers
| Tier | Mode | Capabilities | Config |
|------|------|-------------|--------|
| 0 | Voice only | Fixed allowlist: open apps, lock, screenshot, mute, suspend | Shell `case` in perla.sh |
| 2 | Voice/Text | Full superpowers: shell, filesystem, Obsidian (all folders), web | `opencode.json` |

### Pipeline
```
Wake word / Hotkey
  → Noctalia dmenu (Quick chat / Full mode)
  → pw-record 5s capture
  → whisper-cpp STT
  → tier0 check (instant actions)
  → OpenCode server REST API (persistent session)
  → piper-tts TTS → pw-play audio output
  → Command Log (optional, skips casual chat)
```

### Voice model
- **Engine:** Piper TTS
- **Voice:** `en_US-libritts_r-medium` (American English, multi-speaker, ~75MB)
- **Speed:** `--length-scale 1.3` (slower/natural pace)
- **Output:** Raw 16-bit PCM @ 22050Hz mono

### OpenCode servers
- **Tier 2 (port 13102):** Uses `~/.config/opencode/opencode.json` with superpowers plugin + Obsidian MCP + `opencode/deepseek-v4-flash-free` model
- Servers are persistent — started once via `setsid -f opencode serve --port PORT`, reused across calls (saves ~15s per warm call)
- Session state stored in `/tmp/perla/`

## Troubleshooting

### "perla: command not found"
```bash
source /etc/profiles/per-user/YOUR_USER/etc/profile.d/hm-session-vars.sh
```
Or log out and back in.

### No audio output
Check `pw-play` works:
```bash
echo "test" | piper --model ~/.local/share/piper-tts/voices/en_US-libritts_r-medium.onnx --output-raw | pw-play --rate=22050 --channels=1 --format=s16 --raw -
```

### TTS sounds robotic / too fast
Adjust `--length-scale` in `perla.sh` speak() function (higher = slower).

### Server won't start
```bash
pkill -f "opencode serve" && rm -rf /tmp/perla
```
Then retry. Check logs at `/tmp/perla/server-t*.log`.

### Voice capture not working
Check microphone:
```bash
pw-cli list-objects | grep -i alsa_input
```
Update `audio_input` in `perla-config.nix` with the correct device name.
