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
import QtQuick
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

    // Noctalia derives its palette from the wallpaper it is told about. The
    // phone now owns the wallpaper, so hand Noctalia the same file: its layer
    // stays off, only the colours are used.
    // shortcut: video wallpapers do not update the palette; add a still
    // extraction if their colours matter.
    function syncNoctaliaWallpaper() {
        const path = WallpaperService.currentPath
        if (!NiriWorkspaces.running || !path || WallpaperService.isVideo(path))
            return
        Quickshell.execDetached(["noctalia", "msg", "wallpaper-set", path])
        // Noctalia's lock screen falls back to getWallpaperPath() only while
        // [wallpaper] is enabled in its config, which it is not here — so
        // without an explicit [lockscreen] wallpaper it paints opaque black.
        // Feed it the pick instead: the phone's lock pick when "Separate
        // Lockscreen Wallpaper" is on, else the desktop's. Same folder.
        const lockPath = WallpaperService.lockPathFor(WallpaperService.themeScreen)
        if (lockPath && !WallpaperService.isVideo(lockPath))
            Quickshell.execDetached(["noctalia", "msg", "config-set", "lockscreen.wallpaper",
                                     JSON.stringify(lockPath)])
    }

    Component.onCompleted: syncNoctaliaWallpaper()

    Connections {
        target: WallpaperService
        function onCurrentPathChanged() {
            syncNoctaliaWallpaper()
        }
        // A pick on the lockscreen tab alone must also reach Noctalia.
        function onLockCurrentPathChanged() {
            syncNoctaliaWallpaper()
        }
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
        // The Hyprland profile intentionally leaves the phone's bottom under
        // the screen edge (its peek). This is the session's only phone, so let
        // all of it show.
        peek: 0
        // No bottom-edge hot strip: it overlaps the dock and would open the
        // phone on any pointer brushing the bottom of the screen. Opening is
        // the keybind / `qs -c sekaipop-phone ipc call phone toggle` only.
        hotEdge: false
    }
}
