{ config, pkgs, ... }: {
  users.users.thedreamdev = {
    isNormalUser = true;
    description = "Gohar";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    shell = pkgs.fish;
    packages = with pkgs; [
      kdePackages.kate
    ];
  };
}
