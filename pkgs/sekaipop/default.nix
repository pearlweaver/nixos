{ lib, stdenvNoCC, src }:

# Stages SekaiPop's configuration tree into the store. This is a staging
# derivation only -- it compiles nothing and rewrites nothing.
#
# Why not link `inputs.sekaipop` straight into ~/.config: that path is the whole
# repo, so ~/.config/quickshell/sekaipop would also contain install.sh,
# install-deps.sh, check-deps.sh, get.sh, docs/, tests/ and .git.
#
# The .qsb shaders are copied byte-identical. Upstream built them with Qt 6.12
# and nixpkgs ships 6.11.2, but Gate 0 confirmed 6.11.2 loads them: quickshell
# 0.3.2 baked welcome_dots, welcome_warp, welcome_halo, sekai_ring and
# sekai_ring_lock with zero errors. Do not add qtshadertools to this derivation
# unless a failure names a specific .qsb.
stdenvNoCC.mkDerivation {
  pname = "sekaipop-config";
  version = "1.0.0";

  inherit src;

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # sekaipop/ already contains shell.qml, assets/, shaders/, scripts/,
    # services/, modules/ and tests/. Copying it whole keeps
    # Quickshell.shellDir resolution intact -- the QML reaches assets and
    # shaders relative to the config dir.
    mkdir -p $out/share/sekaipop
    cp -a sekaipop hypr $out/share/sekaipop/

    # Upstream's own test suite; it needs a live Hyprland and asserts against
    # the Arch layout, so it has no business in the deployed config dir.
    rm -rf $out/share/sekaipop/sekaipop/tests

    # Drop the shell's binds for combos that ~/.config/hypr/custom/keybinds.lua
    # owns. hl.bind APPENDS, so without this every shared combo ends up with two
    # live entries and the key launches two things (SUPER+T opened two kitty
    # windows; SUPER+E opened both nautilus and dolphin). hl.unbind() is not a
    # usable substitute: on Hyprland 0.56 it silently no-ops on three-modifier
    # combos and sometimes removes the caller's own bind.
    #
    # Each pattern is anchored on the exact bind target, so a SekaiPop update
    # that renames or moves a line simply stops matching -- a no-op, never a
    # partial edit.
    kb=$out/share/sekaipop/hypr/hyprland/keybinds.lua

    # SUPER + D spans two lines (the dispatch, then its options).
    sed -i '/hl\.bind("SUPER + D",/,+1d' "$kb"

    # The shell's Super tap: hl.dsp.global("quickshell:searchToggleRelease")
    # fires when the Super key is pressed and released, which launches the app
    # drawer. ALT + Space and the launcher IPC are bound in custom/keybinds.lua.
    sed -i '/hl\.bind("SUPER + SUPER_L",/d; /hl\.bind("SUPER + SUPER_R",/d' "$kb"

    # The rest are single-line statements. SUPER + A and SUPER + M go through
    # the shell's `shell(...)` helper rather than hl.bind directly.
    for k in A C E M T W X; do
      sed -i "/hl\.bind(\"SUPER + $k\",/d; /shell(\"SUPER + $k\",/d" "$kb"
    done

    # Touchpad. The shell binds ONE catch-all 3-finger swipe to action = "move"
    # (drag the focused window). Hyprland keeps the FIRST gesture registered for
    # an input, so a per-direction gesture added later is shadowed -- and it
    # reports that as "Your config has errors" on every reload. Unlike binds
    # there is no hl.unbind for gestures, so the catch-all has to go here.
    # ~/.config/hypr/custom/keybinds.lua binds the four 3-finger directions
    # instead (focus left/right, next/previous workspace).
    #
    # Reads the 4 lines after each gesture's opening brace and drops the lot
    # only when it is the move-window one, so renaming the action upstream is a
    # no-op rather than a partial edit. The other gestures (3-finger pinch, the
    # 4-finger ones) are untouched.
    gl=$out/share/sekaipop/hypr/hyprland/general.lua
    sed -i '/^hl\.gesture({$/{N;N;N;N;/action = "move"/d}' "$gl"

    # The VS Code colour block is incomplete. `workbench.colorCustomizations`
    # only overrides the keys it names, so any key it omits is inherited from
    # whatever `workbench.colorTheme` is set to. Here that is NoctaliaTheme (a
    # leftover from the Niri profile), which defines its own near-black
    # (#12131a) for the chrome -- so the line-number gutter, the scrollbar, the
    # minimap, the whole terminal panel and the tab bar of an unfocused window
    # all rendered that near-black on top of our palette. Add the missing keys
    # so the whole surface follows the theme; otherwise this is a two-tone
    # mismatch that looks like a glitch.
    at=$out/share/sekaipop/sekaipop/scripts/theming/app-theme.sh
    sed -i \
      -e 's|"editorLineNumber.activeForeground": "$col_fg",|"editorLineNumber.activeForeground": "$col_fg",\n    "editorGutter.background": "$col_bg",\n    "editorGutter.foldingControlForeground": "$col_muted",\n    "minimap.background": "$col_bg",\n    "panel.background": "$col_bg", "panel.border": "$col_surface", "panelTitle.activeForeground": "$col_fg", "panelTitle.inactiveForeground": "$col_muted",\n    "tab.border": "$col_surface", "tab.unfocusedActiveBackground": "$col_bg", "tab.unfocusedActiveForeground": "$col_fg", "tab.unfocusedInactiveBackground": "$col_surface", "tab.unfocusedInactiveForeground": "$col_muted",\n    "editorGroupHeader.noTabsBackground": "$col_surface", "editorGroupHeader.tabsBorder": "$col_surface",\n    "titleBar.border": "$col_surface", "activityBar.border": "$col_surface",|' \
      -e 's|"editorLineNumber.activeForeground": "$col_fg",|"editorLineNumber.activeForeground": "$col_fg",\n    "scrollbarSlider.background": "''${col_fg}33", "scrollbarSlider.hoverBackground": "''${col_fg}55", "scrollbarSlider.activeBackground": "''${col_accent}88",|' \
      "$at"

    runHook postInstall
  '';

  meta = {
    homepage = "https://github.com/Blapples/SekaiPop";
    description = "SekaiPop Quickshell desktop shell configuration tree";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}