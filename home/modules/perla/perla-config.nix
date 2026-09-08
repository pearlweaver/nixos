{ homeDirectory }: {
  perla = {
    assistant_name = "Perla";
    wake_word = "hey_jarvis";

    vault_path = "${homeDirectory}/Documents/Obsidian/PerlaNew";
    persona_prompt = "${homeDirectory}/.config/perla/persona.md";

    # Default landing spot for files Perla creates, and always a search
    # root for send_file. Kept separate from vault_path deliberately: the
    # vault has its own carefully-scoped read/write boundary
    # (fs_read_exclude_paths, Tier 1's read-only Memory/Long-Term), and
    # generated/fetched files shouldn't have to navigate that boundary or
    # get swept into Obsidian's indexing.
    files_dir = "${homeDirectory}/Perla";
    # Extra folders send_file/list_files may search, beyond files_dir
    # (which is always included). Colon-separated at the env-var layer.
    extra_search_dirs = [
      "${homeDirectory}/Downloads"
      "${homeDirectory}/Documents"
      "${homeDirectory}/Pictures"
    ];

    voice_model = "en_US-libritts_r-medium";
    whisper_model = "tiny";
    whisper_lang = "en";

    opencode_model = "opencode/mimo-v2.5-free";
    ollama_model = "qwen2.5:3b";

    session_idle_timeout_minutes = 10;
    memory_prune_days = 14;

    audio_input = "alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__hw_sofhdadsp__source";

    remote_token = "REPLACED_BY_SOPS";
    elevate_token = "REPLACED_BY_SOPS";
    gate_password = "goharumer";

    fs_read_exclude_paths = [
      ".ssh"
      ".gnupg"
      ".config/sops"
      ".config/opencode"
      ".password-store"
      ".local/share/keyrings"
      ".mozilla"
      ".env"
      ".envrc"
      "Documents/Obsidian/PerlaNew/Memory/Long-Term"
    ];
  };
}
