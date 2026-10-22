// The SekaiPop phone as a standalone Quickshell shell on the Niri + Noctalia
// session. Noctalia keeps the bar, launcher, lock screen and session chrome;
// this process owns the phone, the notification server and the wallpaper.
//
//   qs -c sekaipop-phone
//   qs -c sekaipop-phone ipc call phone toggle|go
//
// The QML tree imported below is symlinked next to this file from pkgs.sekaipop
// (home/modules/sekaipop-phone.nix), so qs.* and Quickshell.shellDir resolve
// exactly as upstream expects.
import Quickshell
import qs.services
import qs.modules.sekai.background
import qs.modules.sekai.notificationPopup
import qs.modules.sekai.quickPanel

ShellRoot {
    // The only wallpaper on the session: Noctalia's wallpaper and its
    // mpvpaper plugin are disabled in noctalia.nix.
    Variants {
        model: Quickshell.screens
        WallpaperLayer {}
    }

    // System side of the quick tiles, media and brightness. It polls only
    // while the phone (or its Settings) is up.
    QuickSource {
        id: quickState
        active: panel.up || panel.settingsShown
        targetScreen: panel.targetScreen
    }

    // The session's notification daemon. Noctalia's is off, so this is the
    // only owner of org.freedesktop.Notifications.
    NotificationSource {
        id: notificationState
        doNotDisturb: !quickState.notificationsOn
        // Fullscreen detection is Hyprland data; do not pretend it works here.
        quietWhenFullscreen: false
        alertStyle: SettingsService.get("notify.style")
        popupsSuppressed: panel.up
    }

    NotificationPopup {
        source: notificationState
    }

    // The Apps face's catalogue. (QuickPanel's `launcher` and `picker`
    // properties are never read upstream; they are omitted.)
    AppSource {
        id: appState
    }

    QuickPanel {
        id: panel
        source: quickState
        notificationSource: notificationState
        appSource: appState
    }
}
