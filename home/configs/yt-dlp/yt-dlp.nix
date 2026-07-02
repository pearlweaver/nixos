{ config, pkgs, ... }:
let
  bgutil = pkgs.python313Packages.bgutil-ytdlp-pot-provider.overridePythonAttrs (old: {
    dependencies = builtins.filter (d: d.pname or "" != "yt-dlp") (old.dependencies or []);
  });
in
{
  programs.yt-dlp = {
    enable = true;
    package = pkgs.yt-dlp.overrideAttrs (old: {
      propagatedBuildInputs = (old.propagatedBuildInputs or []) ++ [ bgutil ];
    });
  };
}