{ pkgs, ... }:

{
  # Native NixOS user targets, services & timers (installed in /etc/systemd/user/)
  systemd.user.targets.hyprland-session = {
    description = "Hyprland Session";
    documentation = [ "man:systemd.special(7)" ];
    bindsTo = [ "graphical-session.target" ];
    wants = [ "graphical-session-pre.target" ];
    after = [ "graphical-session-pre.target" ];
  };

  systemd.user.services.nm-openvpn-sso-user-agent = {
    description = "NetworkManager OpenVPN SSO User Agent";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "/run/current-system/sw/bin/nm-openvpn-sso-user-agent";
      Restart = "always";
      RestartSec = 3;
    };
  };

  systemd.user.services.polkit-gnome = {
    description = "Polkit GNOME Authentication Agent";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  systemd.user.services.sway-wallpaper-switcher = {
    description = "Switch Sway/Hyprland Wallpaper according to Sunrise/Sunset";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    path = with pkgs; [
      bash
      coreutils
      findutils
      gawk
      gnugrep
      hyprland
      sway
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/wallpaper-switcher";
    };
  };

  systemd.user.timers.sway-wallpaper-switcher = {
    description = "Timer for Sway/Hyprland Dynamic Day/Night Wallpaper Switcher";
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    timerConfig = {
      OnActiveSec = "10s";
      OnUnitActiveSec = "5min";
    };
  };

  systemd.user.services.tailscaled = {
    description = "Tailscale node agent (userspace daemon)";
    documentation = [ "https://tailscale.com/kb/" ];
    after = [ "network.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.tailscale}/bin/tailscaled --tun=userspace-networking --socket=%t/tailscale/tailscaled.sock --statedir=%h/.local/share/tailscale --socks5-server=0.0.0.0:1055 --outbound-http-proxy-listen=0.0.0.0:1055";
      Restart = "on-failure";
      RestartSec = 5;
      RuntimeDirectory = "tailscale";
    };
  };

  systemd.user.services.ts-rustdesk = {
    description = "Tailscale RustDesk Port Forwarder to Laptop (100.125.232.113)";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "/run/current-system/sw/bin/ts-rustdesk-forward 21117 100.125.232.113 21118";
      Restart = "always";
      RestartSec = 3;
    };
  };

  # Native NixOS zapret DPI bypass service (set enable = true and fill params from `blockcheck`)
  services.zapret = {
    enable = false;
    # params = [
    #   "--dpi-desync=fake,disorder2"
    #   "--dpi-desync-ttl=1"
    #   "--dpi-desync-autottl=2"
    # ];
    # whitelist = [
    #   "youtube.com"
    #   "googlevideo.com"
    #   "ytimg.com"
    #   "youtu.be"
    # ];
  };
}
