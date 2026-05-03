# Version 26.5.3.2

- Split single configuration.nix file into multiple.
- Enabled Flatpak
- Installed Discord, Spotify, Obsidian, VSCodium and Docker
## **File Structure:**

nixos-config/
├── flake.nix
├── configuration.nix
├── hardware-configuration.nix
└── modules/
	├── audio.nix
	├── boot.nix
	├── desktop.nix
	├── locale.nix
	├── networking.nix
	├── packages.nix
	└── users.nix