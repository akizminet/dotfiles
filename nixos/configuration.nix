{ pkgs, ... }:

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
        --prefix PATH : "/run/wrappers/bin:/run/current-system/sw/bin:${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.openvpn pkgs.systemd pkgs.xdg-utils pkgs.glib ]}"
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
in
{
  imports = [
    ./hardware-configuration.nix
    ./desktop.nix
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
