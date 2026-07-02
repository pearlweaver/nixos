{ config, pkgs, ... }: {
  # Reverse proxy
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts = {

      # Local

      "immich.local" = {
        locations."/" = {
          proxyPass = "http://localhost:2283";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_buffering off;
            client_max_body_size 50000M;
          '';
        };
      };

      "notebook.local" = {
        locations."/" = {
          proxyPass = "http://127.0.0.1:8502";
          proxyWebsockets = true;
        };
      };

      "adguard.local" = {
        locations."/" = {
          proxyPass = "http://localhost:3000";
          proxyWebsockets = true;
        };
      };

      "navidrome.local" = {
        locations."/" = {
          proxyPass = "http://localhost:4533";
          proxyWebsockets = true;
        };
      };

      # Home Server

      "immich.home" = {
        locations."/" = {
          proxyPass = "http://localhost:2283";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_buffering off;
            client_max_body_size 50000M;
          '';
        };
      };

      "adguard.home" = {
        locations."/" = {
          proxyPass = "http://localhost:3000";
          proxyWebsockets = true;
        };
      };

      "notebook.home" = {
        locations."/" = {
          proxyPass = "http://127.0.0.1:8502";
          proxyWebsockets = true;
        };
      };

      "navidrome.home" = {
        locations."/" = {
          proxyPass = "http://localhost:4533";
          proxyWebsockets = true;
        };
      };

      # Template for any new additions
      # "newservice.local" = {
      #   locations."/" = {
      #     proxyPass = "http://localhost:PORTNUMBER";
      #     proxyWebsockets = true;
      #   };
      # };
    };
  };
}
