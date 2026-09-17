{ pkgs, ... }: {
  home.packages = with pkgs; [
    libsecret
    temurin-bin
  ];

  home.sessionVariables = {
    PKG_CONFIG_PATH = "${pkgs.libsecret.dev}/lib/pkgconfig";
    ANDROID_HOME = "$HOME/Android/Sdk";
    ANDROID_SDK_ROOT = "$HOME/Android/Sdk";
    JAVA_HOME = "${pkgs.temurin-bin}";
  };
}