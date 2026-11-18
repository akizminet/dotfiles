{ pkgs, akquick, ... }:

let
  pythonGio = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  nmOpenvpnSso = pkgs.runCommand "nm-openvpn-sso" {
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    passthru = {
      networkManagerPlugin = "VPN/nm-openvpn-sso-service.name";
    };
  } ''
    mkdir -p $out/bin $out/lib/NetworkManager/VPN $out/share/dbus-1/system.d

    install -m 0755 ${./openvpn-sso/nm-openvpn-sso-helper} $out/bin/.nm-openvpn-sso-helper-unwrapped
    install -m 0755 ${./openvpn-sso/nm-openvpn-sso-service} $out/bin/.nm-openvpn-sso-service-unwrapped
    install -m 0755 ${./openvpn-sso/nm-openvpn-sso-user-agent} $out/bin/.nm-openvpn-sso-user-agent-unwrapped

    sed -i "s|/usr/local/bin/nm-openvpn-sso-helper|$out/bin/nm-openvpn-sso-helper|g" \
      $out/bin/.nm-openvpn-sso-service-unwrapped

    for prog in nm-openvpn-sso-helper nm-openvpn-sso-service nm-openvpn-sso-user-agent; do
      sed -i "1s|^#!.*|#!${pythonGio}/bin/python3|" $out/bin/.$prog-unwrapped
      makeWrapper $out/bin/.$prog-unwrapped $out/bin/$prog \
        --prefix GI_TYPELIB_PATH : "${pkgs.glib.out}/lib/girepository-1.0:${pkgs.gobject-introspection}/lib/girepository-1.0" \
        --prefix PATH : "/run/wrappers/bin:/etc/profiles/per-user/phamnv/bin:/run/current-system/sw/bin:${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.openvpn pkgs.systemd pkgs.xdg-utils pkgs.glib ]}" \
        --prefix XDG_DATA_DIRS : "/etc/profiles/per-user/phamnv/share:/run/current-system/sw/share"
    done

    cat > $out/lib/NetworkManager/VPN/nm-openvpn-sso-service.name <<'EOF'
[VPN Connection]
name=openvpn-sso
service=org.freedesktop.NetworkManager.openvpn-sso
program=@out@/bin/nm-openvpn-sso-service
supports-multiple-connections=false

[libnm]
plugin=/etc/NetworkManager/VPN/libnm-vpn-plugin-openvpn-sso.so

[GNOME]
auth-dialog=@authDialog@
properties=libnm-openvpn-sso-properties
supports-external-ui-mode=true
supports-hints=true
EOF
    sed -i \
      -e "s|@out@|$out|g" \
      -e "s|@authDialog@|${pkgs.networkmanager-openvpn}/libexec/nm-openvpn-auth-dialog|g" \
      $out/lib/NetworkManager/VPN/nm-openvpn-sso-service.name

    install -m 0644 ${./openvpn-sso/org.freedesktop.NetworkManager.openvpn-sso.conf} \
      $out/share/dbus-1/system.d/org.freedesktop.NetworkManager.openvpn-sso.conf
  '';

  zapretWrapped = pkgs.symlinkJoin {
    name = "zapret-wrapped";
    paths = [ pkgs.zapret ];
    buildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      rm -f $out/bin/zapret
      makeWrapper "${pkgs.zapret}/bin/zapret" "$out/bin/zapret" \
        --set-default ZAPRET_RW "/etc/zapret" \
        --set-default ZAPRET_CONFIG "/etc/zapret/config"
    '';
  };
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Boot & Swap
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  zramSwap.enable = true;

  # Immutable-style /etc via composefs/erofs overlay with mutable upperdir (/.rw-etc/upper)
  system.etc.overlay.enable = true;
  system.etc.overlay.mutable = true;
  services.userborn.enable = true;
  environment.etc."machine-id".text = "e766ad57c4654c84869e2929fd73e0a0\n";

  # Nix settings & nh helper
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "phamnv" ];
  };
  programs.nh = {
    enable = true;
    flake = "/home/phamnv/dev/dotfiles";
  };
  nixpkgs.config.allowUnfree = true;

  # Networking & Time
  networking.hostName = "homepc";
  networking.networkmanager = {
    enable = true;
    plugins = [
      pkgs.networkmanager-openvpn
      nmOpenvpnSso
    ];
  };
  systemd.services.NetworkManager.restartTriggers = [ nmOpenvpnSso ];
  time.timeZone = "Asia/Ho_Chi_Minh";
  time.hardwareClockInLocalTime = true;

  # Hardware (Intel UHD 730), Audio & Bluetooth
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };
  hardware.bluetooth.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
  security.rtkit.enable = true;
  security.polkit.enable = true;

  # FHS & dynamic linker compatibility for external binaries (e.g. ~/opt/antigravity) & scripts
  services.envfs.enable = true;
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      atk
      cairo
      cups
      dbus
      expat
      fontconfig
      freetype
      gdk-pixbuf
      glib
      gtk3
      icu
      libdrm
      libgbm
      libglvnd
      libnotify
      libpulseaudio
      libuuid
      libxkbcommon
      libxml2
      mesa
      nspr
      nss
      openssl
      pango
      pipewire
      stdenv.cc.cc
      systemd
      vulkan-loader
      wayland
      libx11
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxi
      libxrandr
      libxrender
      libxtst
      libxcb
      libxshmfence
      zlib
    ];
  };

  # System Services
  services.gvfs.enable = true;
  services.tailscale.enable = true;
  services.gnome.gnome-keyring.enable = true;

  # Core Wayland Session, Lock Screen (PAM) & Input Method
  programs.hyprland.enable = true;
  programs.hyprlock.enable = true;
  programs.sway.enable = true;
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      addons = with pkgs; [
        kdePackages.fcitx5-unikey
        kdePackages.fcitx5-configtool
        fcitx5-gtk
        fcitx5-bamboo
      ];
    };
  };

  fonts = {
    fontDir.enable = true;
    packages = with pkgs; [
      nerd-fonts.monaspace
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      liberation_ttf
    ];
  };

  # Minimal base OS & session packages (user apps live in flake.nix -> nix profile)
  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
    akquick.packages.${pkgs.stdenv.hostPlatform.system}.default
    foot
    git
    grim
    hypridle
    hyprland-guiutils
    hyprpaper
    ironbar
    libnotify
    openvpn
    polkit_gnome
    python3
    rofi
    satty
    slurp
    swaynotificationcenter
    wl-clipboard
    zapretWrapped
  ];

  # Declarative dotfile symlinks (replaces setup.sh)
  systemd.user.tmpfiles.rules = [
    "L+ %h/.config/hypr - - - - %h/dev/dotfiles/hypr"
    "L+ %h/.config/sway - - - - %h/dev/dotfiles/sway"
    "L+ %h/.config/ironbar - - - - %h/dev/dotfiles/ironbar"
    "L+ %h/.config/rofi - - - - %h/dev/dotfiles/rofi"
    "L+ %h/.config/foot - - - - %h/dev/dotfiles/foot"
    "L+ %h/.config/gtk-3.0 - - - - %h/dev/dotfiles/gtk-3.0"
    "L+ %h/.config/fcitx5 - - - - %h/dev/dotfiles/fcitx5"
    "L+ %h/.config/satty - - - - %h/dev/dotfiles/satty"
    "L+ %h/.config/swaync - - - - %h/dev/dotfiles/swaync"
    "L+ %h/.config/autostart - - - - %h/dev/dotfiles/autostart"
    "L+ %h/.config/systemd - - - - %h/dev/dotfiles/systemd"
    "L+ %h/.config/environment.d - - - - %h/dev/dotfiles/environment.d"
    "L+ %h/.config/xdg-desktop-portal - - - - %h/dev/dotfiles/xdg-desktop-portal"
    "L+ %h/.config/mimeapps.list - - - - %h/dev/dotfiles/mimeapps.list"
    "L+ %h/.local/bin/antigravity-launcher.sh - - - - %h/dev/dotfiles/bin/antigravity-launcher.sh"
    "L+ %h/.local/bin/restart-antigravity.sh - - - - %h/dev/dotfiles/bin/restart-antigravity.sh"
    "L+ %h/.local/bin/screenshot - - - - %h/dev/dotfiles/bin/screenshot"
    "L+ %h/.local/bin/ts-rustdesk-forward - - - - %h/dev/dotfiles/bin/ts-rustdesk-forward"
    "L+ %h/.local/bin/antigravity - - - - %h/opt/antigravity/antigravity"
    "L+ %h/.local/bin/antigravity-update - - - - %h/dev/workstation/update_antigravity.py"
    "L+ %h/.local/share/applications/antigravity.desktop - - - - %h/dev/dotfiles/applications/antigravity.desktop"
  ];

  # User account matching Fedora UID/GID (1000:1000)
  users.groups.phamnv.gid = 1000;
  users.users.phamnv = {
    isNormalUser = true;
    uid = 1000;
    group = "phamnv";
    description = "Nguyen Van Pham";
    hashedPasswordFile = "/var/lib/nixos/phamnv-password-hash";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "kvm" "input" ];
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "26.11";
}
