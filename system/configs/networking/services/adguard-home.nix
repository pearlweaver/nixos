{ config, pkgs, ... }: {
  # Adguard Home
  services.adguardhome = {
    enable = true;
    openFirewall = true;
    host = "0.0.0.0";
    port = 3000;
    settings = {
      dns = {
        bind_hosts = [ "127.0.0.1" "100.74.236.9" ];
        port = 53;
      };
      tls = {
        enable = true;
        port_dns_over_https = 5443;
      };
    };
  };
}
