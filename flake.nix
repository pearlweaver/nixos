{
  description = "NixOS Flake Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
    #   inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      #inputs.nixpkgs.follows = "nixpkgs";
    };

    niri-flake = {
      url = "github:sodiboo/niri-flake";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      # removed follows to fix version mismatch
    };

  };

  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };

  outputs = { self, nixpkgs, home-manager, noctalia, niri-flake, nixvim, ... }@inputs:
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
        ];
      };

      homeConfigurations.thedreamdev = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs; };
        modules = [
          ./home/home.nix
          noctalia.homeModules.default
          niri-flake.homeModules.niri
          nixvim.homeModules.nixvim
        ];
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          raylib
          gcc
          pkg-config
          libGL
          libx11
          libxcursor
          libxi
          libxinerama
          libxrandr
        ];
        shellHook = ''
          export PKG_CONFIG_PATH="${pkgs.raylib}/lib/pkgconfig"
        '';
      };
    };
}
