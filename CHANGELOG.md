# Version 26.7.3.2

## Changed the Whole Nix config File Tree Structure

- Split `home.nix` into `modules/`
- Moved per-app configs to `home/configs/<app>/<app>.nix`
- Similarily to home-manager, split `system/modules/` as well 
- Moved `system/modules/shell.nix` to `shells/shell.nix`