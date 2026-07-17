{ homeDirectory }: {
  perla = {
    assistant_name = "Perla";
    wake_word = "perla";

    vault_path = "${homeDirectory}/Documents/Obsidian/Perla";
    persona_prompt = "${homeDirectory}/.config/perla/persona.md";

    voice_model = "en_US-libritts_r-medium";
    whisper_model = "tiny";
    whisper_lang = "en";

    opencode_model = "opencode/deepseek-v4-flash-free";
    ollama_model = "qwen2.5:3b";

    session_idle_timeout_minutes = 10;
    memory_prune_days = 14;

    audio_input = "alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__hw_sofhdadsp__source";

    fs_read_exclude_paths = [
      ".ssh"
      ".gnupg"
      ".config/sops"
      ".config/opencode"
      ".password-store"
      ".local/share/keyrings"
      ".mozilla"
      ".config/google-chrome"
      ".config/chromium"
      ".env"
      ".envrc"
      "Documents/Obsidian/Perla/Memory/Long-Term"
    ];
  };
}
