{ config, pkgs, ... }: {
  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = 2283;
    openFirewall = true;
    mediaLocation = "~/immich-app/library";

    database = {
      enable = true;
      createDB = true;
      name = "immich";
      user = "postgres";
    };

    redis.enable = true;

    environment = {
      TZ = "Asia/Karachi";
    };

    secretsFile = config.sops.secrets."immich/db_password".path;
  };
}
