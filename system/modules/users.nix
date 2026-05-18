{ config, pkgs, ... }: {
  users.users.thedreamdev = {
    isNormalUser = true;
    description = "Gohar";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [
      kdePackages.kate
    ];
  };
}
