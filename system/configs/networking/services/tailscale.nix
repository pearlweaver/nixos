{ config, pkgs, ... }: {
  # Tailscale
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
  };
}
