{ config, pkgs, ... }: {
  programs.wireshark = {
    enable = true;
    # usbmon.enable = true;
    # dumpcap.enable = true;
  };
}