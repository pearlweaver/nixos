{ config, pkgs, ... }: {
  sops = {
    defaultSopsFile = ../../secrets/immich.yaml;
    defaultSopsFormat = "yaml";

    age.sshKeyPaths = [ "~/.ssh/id_ed25519" ];

    secrets = {
      "immich/db_password" = {};
      "immich/db_username" = {};
      "immich/db_name" = {};
    };
  };
}
