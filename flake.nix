{
  description = "NixOS Flake Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      # inputs.nixpkgs.follows = "nixpkgs";
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

    catppuccin.url = "github:catppuccin/nix";
  };

  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };

  outputs = { self, nixpkgs, home-manager, noctalia, niri-flake, nixvim, catppuccin, sops-nix, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./system/configuration.nix
          niri-flake.nixosModules.niri
          sops-nix.nixosModules.sops
        ];
      };

      homeConfigurations.thedreamdev = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs; };
        modules = [
          ./home/home.nix
          catppuccin.homeModules.catppuccin
          noctalia.homeModules.default
          niri-flake.homeModules.niri
          nixvim.homeModules.nixvim
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
            ]))
          ];
        };

        # Keeping a fallback pointer so running just `nix develop` doesn't break
        # Defaulted to cpp enviorment
        default = self.devShells.${system}.cpp;
      };
    };
}
