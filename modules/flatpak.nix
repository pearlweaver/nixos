{ config, pkgs, ... }: {
  services.flatpak = {
    enable = true;
    remote = {
      name = "flathub";
      url = "https://flathub.org/repo/flathub.flatpakrepo";
    };
    packages = [ 
      "org.vinegarhq.Sober"
    ];
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
  };
}
