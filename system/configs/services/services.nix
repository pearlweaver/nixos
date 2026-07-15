{ config, pkgs, lib, ... }: {
  imports = [
    ./printing.nix
    ./power.nix
  ];

  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.flatpak.enable = true;

  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;
    package = pkgs.ollama-cpu;
  };

  systemd.services.ollama.environment.OLLAMA_KEEP_ALIVE = "30m";

  nix.settings.experimental-features = [
    "flakes"
    "nix-command"
  ];

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
      xdg-desktop-portal-gtk
    ];
    config.niri  = {
      default = [ "gnome" ];
      "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ];
      "org.freedesktop.impl.portal.Screenshot" = [ "gnome" ];
    };
  };

  environment.sessionVariables = {
    XDG_CURRENT_DESKTOP = "niri";
  };

  # lazymc: 
  # systemd.services.minecraft-server.wantedBy = lib.mkForce [ ]; 
  
  # systemd.services.lazymc = {
  #   description = "Lazymc proxy for Minecraft server";
  #   after = [ "network.target" ];
  #   wantedBy = [ "multi-user.target" ];
    
  #   # Run the vanilla setup script before starting lazymc, this ensures your whitelist and server.properties are actually generated
  #   preStart = config.systemd.services.minecraft-server.preStart;
    
  #   serviceConfig = {
  #     ExecStart = "${pkgs.lazymc}/bin/lazymc --config /etc/lazymc.toml";
  #     Restart = "on-failure";
  #     User = "minecraft";
  #     Group = "minecraft";
  #     WorkingDirectory = "/var/lib/minecraft";
  #   };
  # };

  # environment.etc."lazymc.toml".text = ''
  #   [public]
  #   address = "0.0.0.0:25565"

  #   [server]
  #   address = "127.0.0.1:25566"
  #   directory = "/var/lib/minecraft"
    
  #   command = "${config.services.minecraft-server.package}/bin/minecraft-server ${config.services.minecraft-server.jvmOpts}"

  #   [time]
  #   sleep_after = 300
  #   minimum_online_time = 60

  #   [motd]
  #   sleeping = "💤 Server offline, join to start."
  #   starting = "🚀 Server is starting..."
  # '';
}