{
  description = "NixOS Flake Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    quickshell = {
      url = "github:outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri-flake = {
      url = "github:sodiboo/niri-flake";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      # removed follows to fix version mismatch
    };

    sops-nix = {
      url = "github:mic92/sops-nix";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    helium-flake = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";

    ryoku = {
      url = "github:aethctl/Ryoku-on-NixOS";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # nixConfig = {
  #  extra-substituters = [ "https://noctalia.cachix.org" ];
  #  extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  #};

  outputs = { self, nixpkgs, home-manager, noctalia, niri-flake, nixvim, catppuccin, sops-nix, ryoku, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          niri-flake.overlays.niri
          (final: prev: {
            brave-origin = final.callPackage ./pkgs/brave-origin { };
            rose-pine-gtk-theme = final.callPackage ./pkgs/rose-pine-gtk-theme { };
            # aseprite uses fmt::format via `fmt/core.h`, which fmt >= 12.2.0
            # no longer pulls in (it includes only fmt/base.h). Pin an older fmt.
            aseprite = prev.aseprite.override { fmt = prev.fmt_11; };
          })
        ];
      };
    in {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
        };
        modules = [
          ./system/configuration.nix
          niri-flake.nixosModules.niri
          sops-nix.nixosModules.sops
        ];
      };

      homeConfigurations.thedreamdev = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit inputs;
          ryokuSession = false;
        };
        modules = [
         ./home/home.nix
          catppuccin.homeModules.catppuccin
          noctalia.homeModules.default
          niri-flake.homeModules.niri
          nixvim.homeModules.nixvim
          sops-nix.homeManagerModules.sops
        ];
      };

      # Ryoku (Hyprland desktop) separate config, boots as its own
      # generation. Your `nixos` config above is not imported here, so
      # nothing about Niri/Noctalia is touched. Switch to it with:
      #   sudo nixos-rebuild switch --flake .#ryoku
      # Switch back to your normal setup any time with:
      #   sudo nixos-rebuild switch --flake .#nixos
      nixosConfigurations.ryoku = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
        };
        modules = [
          ./system/configuration.nix
          niri-flake.nixosModules.niri
          sops-nix.nixosModules.sops
          ryoku.nixosModules.default
          # Activate the Ryoku desktop and strip the Niri/Plasma setup that
          # system/modules/desktop.nix applies to the normal `nixos` config.
          # `mkForce` is needed because desktop.nix sets both unconditionally.
          ({ lib, ... }: {
            programs.ryoku.enable = true;
            programs.niri.enable = lib.mkForce false;
            services.desktopManager.plasma6.enable = lib.mkForce false;
            # system/configs/services/services.nix hardcodes XDG_CURRENT_DESKTOP=niri,
            # but this generation runs Hyprland/Ryoku, so force the correct value.
            environment.sessionVariables.XDG_CURRENT_DESKTOP = lib.mkForce "Hyprland";
          })
        ];
      };

      homeConfigurations.thedreamdev-ryoku = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit inputs;
          # Tells modules/apps.nix to skip importing the Rose Pine GTK/Qt6
          # theme files, so Ryoku's own theming is what applies instead.
          # Passed via extraSpecialArgs rather than `_module.args` to avoid
          # an infinite recursion when the argument is read in `imports`.
          ryokuSession = true;
        };
        modules = [
          ./home/home-ryoku.nix
          catppuccin.homeModules.catppuccin
          nixvim.homeModules.nixvim
          sops-nix.homeManagerModules.sops
        ];
      };

      devShells.${system} = {
        # C++ / Raylib graphics shell mapped to .#cpp
        cpp = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            pkg-config
          ];

          buildInputs = with pkgs; [
            raylib
            libGL
            xorg.libX11
            xorg.libXcursor
            xorg.libXi
            xorg.libXinerama
            xorg.libXrandr
          ];
        };

        # Python shell mapped to .#python
        python = pkgs.mkShell {
          packages = [
            (pkgs.python3.withPackages (python-pkgs: with python-pkgs; [
              pandas
              requests
              numpy
              matplotlib
              scipy
              scikit-image
              scikit-learn
              inquirerpy
              tqdm
            ]))
          ];
        };

        # Keeping a fallback pointer so running just `nix develop` doesn't break
        # Defaulted to cpp enviorment
        default = self.devShells.${system}.cpp;
      };
    };
}
