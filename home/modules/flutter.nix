{ pkgs, ... }: {
  home.packages = with pkgs; [
    libsecret
  ];

  home.sessionVariables = {
    PKG_CONFIG_PATH = "${pkgs.libsecret.dev}/lib/pkgconfig";
  };
}