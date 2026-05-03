# Version 26.5.3.2

Splitted single configuration.nix file into multiple.

**File Structure:**

nixos-config/
├── flake.nix
├── configuration.nix      ← just imports
├── hardware-configuration.nix
└── modules/
    ├── desktop.nix
    ├── immich.nix
    ├── audio.nix
    ├── networking.nix
    ├── users.nix
    └── packages.nix