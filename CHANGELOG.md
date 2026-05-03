# Version 26.5.3.2

Splitted single configuration.nix file into multiple.

## **File Structure:**

nixos-config/<br/>
├── flake.nix<br/>
├── configuration.nix<br/>
├── hardware-configuration.nix<br/>
└── modules/<br/>
&emsp;&emsp;├── desktop.nix<br/>
&emsp;&emsp;├── immich.nix<br/>
&emsp;&emsp;├── audio.nix<br/>
&emsp;&emsp;├── networking.nix<br/>
&emsp;&emsp;├── users.nix<br/>
&emsp;&emsp;└── packages.nix<br/>