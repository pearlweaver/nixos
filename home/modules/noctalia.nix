{ config, pkgs, inputs, ... }: {
  programs.noctalia-shell = {
    enable = true;
    settings = {
      settingsVersion = 59;

      bar = {
        barType = "floating";
        position = "top";
        density = "default";
        showCapsule = true;
        backgroundOpacity = 0.93;
        marginVertical = 4;
        marginHorizontal = 4;
        frameRadius = 12;
        outerCorners = true;
        displayMode = "always_visible";
        rightClickAction = "controlCenter";
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
        avatarImage = "/home/thedreamdev/Pictures/Random/stardust.jpg";
        dimmerOpacity = 0;
        radiusRatio = 0.5;
        animationSpeed = 1.66;
        enableShadows = false;
        enableBlurBehind = true;
        lockOnSuspend = true;
        clockStyle = "custom";
        clockFormat = "hh\nmm";
        telemetryEnabled = false;
      };

      ui = {
        fontDefault = "Monocraft";
        fontFixed = "Monocraft";
        translucentWidgets = true;
        panelsAttachedToBar = true;
      };

      location = {
        name = "Lahore, Pakistan";
        weatherEnabled = true;
        use12hourFormat = false;
        autoLocate = false;
      };

      wallpaper = {
        enabled = true;
        directory = "/home/thedreamdev/Pictures/Wallpapers";
        fillMode = "crop";
        automationEnabled = false;
        wallpaperChangeMode = "random";
        randomIntervalSec = 300;
        transitionDuration = 1500;
        panelPosition = "center";
      };

      appLauncher = {
        terminalCommand = "kitty -e";
        position = "center";
        sortByMostUsed = true;
        viewMode = "list";
        showCategories = true;
      };

      colorSchemes = {
        useWallpaperColors = false;
        predefinedScheme = "Catppuccin";
        darkMode = true;
        syncGsettings = true;
      };

      dock = {
        enabled = true;
        position = "bottom";
        displayMode = "auto_hide";
        dockType = "floating";
        dockIndicator = true;
      };

      noctaliaPerformance = {
        disableWallpaper = true;
        disableDesktopWidgets = true;
      };

      notifications = {
        enabled = true;
        location = "top_right";
        overlayLayer = true;
        lowUrgencyDuration = 3;
        normalUrgencyDuration = 8;
        criticalUrgencyDuration = 15;
        enableBatteryToast = true;
        enableKeyboardLayoutToast = true;
      };

      audio = {
        volumeStep = 5;
        volumeOverdrive = false;
      };

      brightness = {
        brightnessStep = 5;
        enforceMinimum = true;
        enableDdcSupport = false;
      };

      nightLight = {
        enabled = false;
        autoSchedule = true;
        nightTemp = "4000";
        dayTemp = "6500";
      };
    };
  };
}