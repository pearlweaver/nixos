{ config, pkgs, ... }: {
  imports = [ ./themes/rose-pine.nix ];

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set fish_greeting
      clear
      fastfetch
    '';

    shellAliases = {
      ll = "ls -l";
      rebuild-nix = "cd ~/nixos-config && sudo nixos-rebuild switch --flake .#nixos";
      rebuild-home = "cd ~/nixos-config && home-manager switch --flake .#thedreamdev";
    };

    functions = {
      mp3 = { # run as 'mp3 https://youtu.be/dQw4w9WgXcQ/'
        description = "Download YouTube audio as MP3";
        body = ''
          yt-dlp --ignore-errors \
                 --extract-audio \
                 --audio-format mp3 \
                 --audio-quality 0 \
                 -o "%(title)s.%(ext)s" \
                 $argv[1]
        '';
      };

      mp3playlist = {
        description = "Download YouTube playlist as MP3";
        body = ''
          yt-dlp --ignore-errors \
                 --extract-audio \
                 --audio-format mp3 \
                 --audio-quality 0 \
                 --yes-playlist \
                 -o "%(title)s.%(ext)s" \
                 $argv[1]
        '';
      };

      spotifymp3 = {
        description = "Download Spotify music as MP3";
        body = ''
          spotdl $argv[1] \
                 --output "{title}.{output-ext}" \
                 --format mp3 \
                 --bitrate 320k \
                 --lyrics genius musixmatch
          '';
      };

      spotifyplaylist = {
        description = "Download Spotify playlist as MP3";
        body = ''
          spotdl $argv[1] \
                 --output "{title}.{output-ext}" \
                 --format mp3 \
                 --lyrics genius musixmatch \
                 --bitrate 320k
          '';
      };
    };
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;

    settings = {
      add_newline = true;

      format = ''
        $cmd_duration $directory$git_branch
          $character
      '';

      fill = {
        symbol = "-";
        style = "fg:surface1";
      };

      character = {
        success_symbol = "[ ](bold fg:mauve)";
        error_symbol = "[ ](bold fg:red)";
      };

      package = {
        disabled = true;
      };

      git_branch = {
        style = "bg:surface0";
        symbol = "󰘬";
        truncation_length = 12;
        truncation_symbol = "";
        format = " 󰜥 [](bold fg:surface0)[$symbol $branch(:$remote_branch)](fg:text bg:surface0)[ ](bold fg:surface0)";
      };

      git_commit = {
        commit_hash_length = 4;
        tag_symbol = " ";
      };

      git_state = {
        format = "[\\($state( $progress_current of $progress_total)\\)]($style) ";
        cherry_pick = "[🍒 PICKING](bold red)";
      };

      git_status = {
        conflicted = " 🏳 ";
        ahead = " 🏎💨 ";
        behind = " 😰 ";
        diverged = " 😵 ";
        untracked = " 🤷 ‍";
        stashed = " 📦 ";
        modified = " 📝 ";
        staged = "[++\\($count\\)](green)";
        renamed = " ✍️ ";
        deleted = " 🗑 ";
      };

      hostname = {
        ssh_only = false;
        format = "[•$hostname](bg:surface0 bold fg:text)[](bold fg:surface0)";
        trim_at = ".companyname.com";
        disabled = false;
      };

      line_break = {
        disabled = false;
      };

      memory_usage = {
        disabled = true;
        threshold = -1;
        symbol = " ";
        style = "bold dimmed green";
      };

      time = {
        disabled = true;
        format = "🕙[\\[ $time \\]]($style) ";
        time_format = "%T";
      };

      username = {
        style_user = "bold bg:surface0 fg:text";
        style_root = "red bold";
        format = "[](bold fg:surface0)[$user]($style)";
        disabled = false;
        show_always = true;
      };

      directory = {
        home_symbol = " ";
        read_only = "  ";
        style = "bg:blue fg:surface1";
        truncation_length = 2;
        truncation_symbol = ".../";
        format = "[](bold fg:blue)[󰉋 → $path]($style)[](bold fg:blue)";

        substitutions = {
          "Desktop" = "  ";
          "Documents" = "  ";
          "Downloads" = "  ";
          "Music" = " 󰎈 ";
          "Pictures" = "  ";
          "Videos" = "  ";
          "GitHub" = " 󰊤 ";
        };
      };

      cmd_duration = {
        min_time = 0;
        format = "[](bold fg:pink)[󰪢 $duration](bold bg:pink fg:crust)[](bold fg:pink)";
      };
    };
  };
}
