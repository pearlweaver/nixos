{ config, pkgs, ... }: {
  # Navidrome
  services.navidrome = {
    enable = true;
    openFirewall = false;
    settings = {
      MusicFolder = "/home/thedreamdev/Music";
      Port = 4533;
      Address = "127.0.0.1";
    };
  };
}
