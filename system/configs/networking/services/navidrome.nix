{ config, pkgs, ... }: {
  # Navidrome
  services.navidrome = {
    enable = true;
    openFirewall = true;
    settings = {
      MusicFolder = "/home/thedreamdev/Music";
      Port = 4533;
      Address = "0.0.0.0";
    };
  };
}
