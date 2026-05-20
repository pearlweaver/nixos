{ config, pkgs, ... }: {
  # for binaries that work on other distros. needed for unity (i think)
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc
      libz
      libGL
      libx11
      libxcursor
      libxrandr
      libxi
      icu
      mesa
      vulkan-loader
    ];
  };
  
  xdg.portal.config.niri = {
    "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ]; # or "kde"
  }; 
  
  # intel shaders stuff
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
      mesa
      vulkan-loader
      vulkan-tools
      intel-compute-runtime
    ];
  };
}
