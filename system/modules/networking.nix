{ config, pkgs, ... }: {
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  networking.nftables.enable = false;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 3000 ];
    allowedUDPPorts = [ 53 ];
    trustedInterfaces = [ "tailscale0" ];
  };

  networking.hosts = {
    "127.0.0.1" = [
      "notebook.local"
      "immich.local"
      "adguard.local"
      "navidrome.local"
    ];
  };

  # Tailscale
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
  };

  # Adguard Home
  services.adguardhome = {
    enable = true;
    openFirewall = true;
    host = "0.0.0.0";
    port = 3000;
    settings = {
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
      };
      tls = {
        enable = true;
        port_dns_over_https = 5443;
      };
    };
  };

  # Navidrome
  services.navidrome = {
    enable = true;
    openFirewall = true;
    settings = {
      MusicFolder = "/home/thedreamdev/Music";
      Port = 4533;
      Address = "0.0.0.0";
    };
  };

  # mDNS
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      userServices = true;
      workstation = true;
    };
  };

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
