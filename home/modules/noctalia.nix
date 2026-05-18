{ config, pkgs, inputs, ... }: {
  programs.noctalia-shell = {
    enable = true;
    settings = {
      bar = {
        position = "top";
        density = "compact";
        showCapsule = true;
        widgets = {
          left = [
            { id = "Launcher"; useDistroLogo = true; }
            { id = "ActiveWindow"; }
          ];
          center = [
            { id = "Workspace"; }
          ];
          right = [
            { id = "SystemMonitor"; }
            { id = "Tray"; }
            { id = "Volume"; }
            { id = "Brightness"; }
            { id = "Battery"; }
            { id = "NotificationHistory"; }
            { id = "ControlCenter"; }
            { id = "Clock"; useMonospacedFont = true; }
          ];
        };
      };

      general = {
        avatarImage = "/home/thedreamdev/.face";
        radiusRatio = 0.5;
        enableBlurBehind = true;
        enableShadows = true;
      };

      colorSchemes = {
        predefinedScheme = "Noctalia (default)";
        darkMode = true;
      };

      location = {
        name = "Karachi, Pakistan";
        use12hourFormat = false;
      };

      appLauncher = {
        terminalCommand = "kitty -e";
        position = "center";
      };
    };
  };
}
