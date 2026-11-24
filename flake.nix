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

    silentSDDM = {
      url = "github:uiriansan/SilentSDDM";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cod-clients = {
      url = "github:Daaboulex/cod-clients-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # SekaiPop: a full Quickshell-based Hyprland desktop shell. Pinned to a
    # commit, not the default branch, so `nix flake update` cannot move it;
    # bump this rev by hand when you deliberately want a new version.
    # The Arch installers are unusable here (they hard-exit on a missing
    # pacman), so pkgs/sekaipop stages the config tree instead.
    # `flake = false` because the repo is not a flake -- without it nix looks
    # for a flake.nix that does not exist and the input fails to resolve.
    sekaipop = {
      url = "github:Blapples/SekaiPop/9b606805f6ca0dd855ba5d2b4a274be620fa6a58";
      flake = false;
    };

    # ChillPill-Shell: the user's fork of a Quickshell pill bar for niri.
    # Consumed as a flake so the local checkout at ~/Dev/ChillPill-Shell is
    # never touched. The lock pins the exact rev; `nix flake update chillpill`
    # moves it deliberately.
    chillpill = {
      url = "github:pearlweaver/ChillPill-Shell";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  # nixConfig = {
  #  extra-substituters = [ "https://noctalia.cachix.org" ];
  #  extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  #};

  outputs = { self, nixpkgs, home-manager, noctalia, niri-flake, nixvim, catppuccin, sops-nix, silentSDDM, cod-clients, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          niri-flake.overlays.niri
          (final: prev: {
            brave-origin = final.callPackage ./pkgs/brave-origin { };
            rose-pine-gtk-theme = final.callPackage ./pkgs/rose-pine-gtk-theme { };
            # Not in nixpkgs; check-deps.sh lists it as a Tier 1 manual install.
            google-sans-flex = final.callPackage ./pkgs/google-sans-flex { };
            # Stages SekaiPop's QML tree, Hyprland Lua tree and assets into the
            # store so home-manager can link them. Carries no binaries of its
            # own; the shell itself is quickshell, which is pinned per-output.
            sekaipop = final.callPackage ./pkgs/sekaipop { src = inputs.sekaipop; };
            # Horizon game launcher (prebuilt binary from latest downloaded tarball).
            horizon-launcher = final.callPackage ./pkgs/horizon-launcher { };
            # nixpkgs' flutter lags upstream stable; this rebuilds it from a
            # vendored data.json. See pkgs/flutter/default.nix.
            flutter = final.callPackage ./pkgs/flutter { };
            # aseprite uses fmt::format via `fmt/core.h`, which fmt >= 12.2.0
            # no longer pulls in (it includes only fmt/base.h). Pin an older fmt.
            aseprite = prev.aseprite.override { fmt = prev.fmt_11; };
            # ChillPill needs its lockscreen script installed and wrapped;
            # pkgs/chillpill adds that to the upstream flake package.
            chillpill = final.callPackage ./pkgs/chillpill {
              upstream = inputs.chillpill.packages.${system}.default;
            };
          })
        ];
      };
    in {
      # Exposed so the two new packages can be built and verified on their own
      # (`nix build .#sekaipop`, `nix build .#google-sans-flex`) without going
      # through a whole home-manager generation. The overlay attrs would
      # otherwise only be reachable from inside the home profiles.
      packages.${system} = {
        inherit (pkgs) sekaipop google-sans-flex horizon-launcher chillpill;
      };

      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
        };
        modules = [
          ./system/configuration.nix
          niri-flake.nixosModules.niri
          sops-nix.nixosModules.sops
          silentSDDM.nixosModules.default
        ];
      };

      homeConfigurations.thedreamdev = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit inputs;
          hyprlandSession = false;
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

      # SekaiPop (Quickshell desktop shell) as its own generation. The Niri /
      # Noctalia configuration above is not touched by it: `programs.niri.enable`
      # is forced off here and nothing else is shared.
      nixosConfigurations.sekaipop = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
        };
        modules = [
          ./system/configuration.nix
          niri-flake.nixosModules.niri
          sops-nix.nixosModules.sops
          silentSDDM.nixosModules.default
          ./system/modules/hyprland-session.nix

          # Strip what the shared desktop module applies to the normal `nixos`
          # config. `mkForce` is needed because desktop.nix sets both
          # unconditionally.
          ({ lib, ... }: {
            programs.niri.enable = lib.mkForce false;
            services.desktopManager.plasma6.enable = lib.mkForce false;
            # system/configs/services/services.nix hardcodes
            # XDG_CURRENT_DESKTOP=niri, but this generation runs Hyprland.
            environment.sessionVariables.XDG_CURRENT_DESKTOP = lib.mkForce "Hyprland";
          })
        ];
      };

      # SekaiPop (Quickshell desktop shell) as its own generation. The Niri /
      # Noctalia configuration above is not touched by it. Switch with:
      #   sudo nixos-rebuild switch --flake .#sekaipop
      # Switch back with:
      #   sudo nixos-rebuild switch --flake .#nixos
      homeConfigurations.thedreamdev-sekaipop = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit inputs;
          # Same role as hyprlandSession: tells modules/apps.nix to skip the Rose
          # Pine GTK/Qt files, which are Niri-session theming. SekaiPop themes
          # via matugen instead. Passed via extraSpecialArgs rather than
          # _module.args to avoid infinite recursion when read in `imports`.
          hyprlandSession = true;
        };
        modules = [
          ./home/home-sekaipop.nix
          catppuccin.homeModules.catppuccin
          nixvim.homeModules.nixvim
          sops-nix.homeManagerModules.sops
        ];
      };

      # Niri + ChillPill as its own home generation. The system side is the
      # same niri session as `nixos`, so only home-manager changes. Switch with
      #   home-manager switch --flake .#thedreamdev-chillpill
      # and back with
      #   home-manager switch --flake .#thedreamdev
      homeConfigurations.thedreamdev-chillpill = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit inputs;
          # Niri session, not Hyprland. The flag is this repo's "use the
          # static Rose Pine theme, not Noctalia's runtime-generated one"
          # switch; the ChillPill profile keeps the normal niri path.
          hyprlandSession = false;
        };
        modules = [
          ./home/home-chillpill.nix
          catppuccin.homeModules.catppuccin
          # Declares programs.noctalia.* so perla.nix's launcher entry
          # evaluates. This is NOT home/modules/noctalia.nix: enable stays
          # false, so no daemon and no template generation.
          noctalia.homeModules.default
          niri-flake.homeModules.niri
          nixvim.homeModules.nixvim
          sops-nix.homeManagerModules.sops
          inputs.chillpill.homeManagerModules.default
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
              chess
              kivy
              tkinter
            ]))
          ];
        };

        # Keeping a fallback pointer so running just `nix develop` doesn't break
        # Defaulted to cpp enviorment
        default = self.devShells.${system}.cpp;
      };
    };
}
