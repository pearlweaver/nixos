{ ... }: {

  # KERNEL HARDENING
  boot.kernel.sysctl = {
    # Network security
    "net.ipv4.tcp_syncookies" = 1; # Protects against SYN flood attacks
    "net.ipv4.conf.all.rp_filter" = 1; # Blocks spoofed network packets
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0; # Stops attackers redirecting your traffic
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;

    # Memory protection
    "kernel.randomize_va_space" = 2; # Gives random memory addresses to applications
    "kernel.kptr_restrict" = 2; # Hides kernel memory addresses
    "kernel.dmesg_restrict" = 1; # Hides kernel logs from normal users
    "kernel.unprivileged_bpf_disabled" = 1;

    # File watcher limit (already have this)
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
  };

  # APP ARMOR
  # Each application has its own container/sandbox. Even if it gets hacked, it can only access what it allowed to
  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = true;
  };

  # SSH PROTECTION
  # Blocks ip for 1h on failed 5 ssh login attempts
  # I am already using tailscale for remote access, my services are not directly exposed to the internet.
  # This is mostly only useful if I ever decided to expose my services to the internet.
  services.fail2ban = {
  enable = true;
  maxretry = 5;
  bantime = "1h";

  jails = {
      # Protect Immich login
      immich = {
        enabled = true;
        filter = "immich";
        logpath = "/var/log/immich/*.log";
        maxretry = 5;
        bantime = "1h";
      };

      # Protect nginx
      nginx-http-auth = {
        enabled = true;
      };

      nginx-botsearch = {
        enabled = true;
      };
    };
  };
}
