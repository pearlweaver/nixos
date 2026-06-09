{ config, pkgs, ... }: {
  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = 2283;
    openFirewall = true;
    mediaLocation = "/var/lib/immich/library";

    database = {
      enable = true;
      createDB = true;
      name = "immich";
      user = "immich";
    };

    redis.enable = true;

    environment = {
      TZ = "Asia/Karachi";
    };

    secretsFile = config.sops.secrets."immich/db_password".path;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/immich-app/library 0755 immich immich -"
    "d /var/lib/immich-app/library/encoded-video 0755 immich immich -"
    "d /var/lib/immich-app/library/thumbs 0755 immich immich -"
    "d /var/lib/immich-app/library/upload 0755 immich immich -"
    "d /var/lib/immich-app/library/backups 0755 immich immich -"
    "d /var/lib/immich-app/library/profile 0755 immich immich -"
  ];
}
