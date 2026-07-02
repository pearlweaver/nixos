{ ... }: {
  imports = [
    ./kitty/kitty.nix
    ./git/git.nix
    ./nvim/nvim.nix
    ./yt-dlp/yt-dlp.nix
    ./prismlauncher/prismlauncher.nix
    ./fish/fish.nix
    ./fastfetch/fastfetch.nix
    ./gtk/gtk.nix
    ./qt6/qt6.nix
  ];
}
