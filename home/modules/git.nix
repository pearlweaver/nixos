{ config, pkgs, ... }: {
  programs.git = {
    enable = true;
    settings = {
      user.name = "pearlweaver";
      user.email = "37861423-pearlweaver@users.noreply.gitlab.com";
      push.autoSetupRemote = true;
      init.defaultBranch = "main";
    };
  };
}
