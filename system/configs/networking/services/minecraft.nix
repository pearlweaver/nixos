{ config, pkgs, ... }: {
  # Minecraft Server
#   services.minecraft-server = {
#     enable = true;
#     eula = true;
#     openFirewall = false;
#     declarative = true;

#     package = pkgs.minecraft-server.overrideAttrs (old: rec {
#       version = "26.2";
#       src = pkgs.fetchurl {
#         url = "https://piston-data.mojang.com/v1/objects/823e2250d24b3ddac457a60c92a6a941943fcd6a/server.jar";
#         sha256 = "sha256-zazfsliY3l5LSw5d3MJyL3cGfkZgVwnC2IbAAOu2PsU=";
#       };
#     });

#     whitelist = {
#       TheDreamDev = "1cac657f-9026-3e5c-bee0-057f52f3b15d";
#       FanumTax = "a9d014d2-73bc-3133-b14a-0c55b17f1786";
#     };

#     serverProperties = {
#       server-port = 25566;
#       gamemode = "survival";
#       motd = "Minecraft Server";
#       max-players = 10;
#       difficulty = "normal";
#       white-list = true;
#       online-mode = false;
#     };

#     jvmOpts = "-Xms1G -Xmx3G";
#   };
}
