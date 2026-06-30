# Version 26.6.30.1

## Added Brave Origin

### Process:
1. Created `pkgs/brave-origin/default.nix`,  Nix package expression that:
   - Downloads `brave-origin_1.92.132_amd64.deb` from GitHub releases
   - Extracts the `.deb` and patches the ELF binary with `patchelf` for Nix store paths
   - Fixes the Brave wrapper script and `.desktop` files to point to the Nix store
   - Wraps with `wrapGAppsHook3` for GTK/GSetting integration
2. Added `brave-origin` overlay in `flake.nix` via `final.callPackage ./pkgs/brave-origin`
3. Added `brave-origin` to `home.packages` in `home/home.nix`

### To Update the browser:
In `pkgs/brave-origin/default.nix`,
1. Change version number
2. Change version URL
3. Change hash (leave empty first, run nix build and copy the correct hash from error output)

---

The reason I implemented brave origin is because I wanted to test out personally how this browser is without waiting for the nixpkgs to update. I will discard this in the future when it arrives (probably even before that). Anyways, I needed to have a chromium browser just in case some websites don't work on Firefox. 