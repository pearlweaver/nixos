{
  description = "NixOS Flake Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      # NixOS config
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./system/configuration.nix ];
      };

      # Home Manager config
      homeConfigurations.thedreamdev = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home/home.nix ];
      };

      # Dev shell
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

# {
#   description = "NixOS Flake Configuration";
#
#   inputs = {
#     nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # or nixos-23.11
#     home-manager = {
#       url = "github:nix-community/home-manager";
#       inputs.nixpkgs.follows = "nixpkgs";
#     };
#   };
#
#   outputs = { self, nixpkgs, home-manager, ... }: {
#     # nixos config
#     nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
#       system = "x86_64-linux";
#       modules = [ ./configuration.nix ];
#     };
#
#     # homemanager config
#     homeConfigurations.thedreamdev = home-manager.lib.homeManagerConfiguration {
#       pkgs = nixpkgs.legacyPackages.x86_64-linux;
#       modules = [ ./home.nix ];
#     };
#   };
# }
#
