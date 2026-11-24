{ pkgs, lib, upstream, ... }:

# The upstream flake package installs the shell and its IPC helper but not the
# lockscreen script, even though lockscreen.sh sits next to shell.qml and its
# /usr/share path does not exist on NixOS. Add it here so the flake package and
# the home-manager profile are the same derivation -- two copies would drift.
let
  qtModules = with pkgs.qt6; [ qtbase qtdeclarative qtmultimedia ];
  qtQmlPath = lib.concatMapStringsSep ":" (m: "${m}/lib/qt-6/qml") qtModules;
  qtPluginPath = lib.concatMapStringsSep ":" (m: "${m}/lib/qt-6/plugins") qtModules;
in
upstream.overrideAttrs (old: {
  installPhase = old.installPhase + ''
    install -Dm755 $src/lockscreen.sh $out/bin/chillpill-lock
    substituteInPlace $out/bin/chillpill-lock \
      --replace /usr/share/chillpill-shell $out/share/chillpill-shell
  '';
  # Same environment the upstream wrapper gives chillpill-shell: the QML
  # import/plugin paths and PillBackend are needed by Lockscreen.qml too.
  postFixup = old.postFixup + ''
    wrapProgram $out/bin/chillpill-lock \
      --set QML_IMPORT_PATH "$out/share/chillpill-shell:$out/lib/qt6/qml:${qtQmlPath}" \
      --set QT_PLUGIN_PATH "${qtPluginPath}" \
      --set LD_LIBRARY_PATH "$out/lib/qt6/qml/PillBackend" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.quickshell ]}
  '';
})
