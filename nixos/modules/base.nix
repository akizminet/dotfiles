{ config, lib, pkgs, akquick, hostSpec, ... }:

let
  pythonGio = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  nmOpenvpnSso = pkgs.runCommand "nm-openvpn-sso" {
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    passthru = {
      networkManagerPlugin = "VPN/nm-openvpn-sso-service.name";
    };
  } ''
    mkdir -p $out/bin $out/lib/NetworkManager/VPN $out/share/dbus-1/system.d

    install -m 0755 ${../openvpn-sso/nm-openvpn-sso-helper} $out/bin/.nm-openvpn-sso-helper-unwrapped
    install -m 0755 ${../openvpn-sso/nm-openvpn-sso-service} $out/bin/.nm-openvpn-sso-service-unwrapped
    install -m 0755 ${../openvpn-sso/nm-openvpn-sso-user-agent} $out/bin/.nm-openvpn-sso-user-agent-unwrapped

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

    install -m 0644 ${../openvpn-sso/org.freedesktop.NetworkManager.openvpn-sso.conf} \
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

  tailscaleBin = pkgs.writeShellScriptBin "tailscale" ''
    SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$UID}/tailscale/tailscaled.sock"
    if [[ "$*" != *--socket* ]] && [ -S "$SOCKET" ]; then
      exec "${pkgs.tailscale}/bin/tailscale" --socket="$SOCKET" "$@"
    else
      exec "${pkgs.tailscale}/bin/tailscale" "$@"
    fi
  '';

  tailscaleWrapped = pkgs.symlinkJoin {
    name = "tailscale-wrapped";
    paths = [ tailscaleBin pkgs.tailscale ];
  };
in
{
  # Boot & Swap
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  zramSwap.enable = true;

  # Immutable-style /etc via composefs/erofs overlay with mutable upperdir (/.rw-etc/upper)
  system.etc.overlay.enable = true;
  system.etc.overlay.mutable = true;
  services.userborn.enable = true;
  environment.etc."machine-id" = lib.mkIf (hostSpec.machineId != null) {
    text = "${hostSpec.machineId}\n";
  };

  # Nix settings & nh helper
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" hostSpec.username ];
  };
  programs.nh = {
    enable = true;
    flake = hostSpec.dotfilesDir;
    package = pkgs.symlinkJoin {
      name = "nh-impure";
      paths = [ pkgs.nh ];
      postBuild = ''
        rm -f $out/bin/nh
        cp ${pkgs.writeShellScript "nh" ''
          if [ "$1" = "os" ]; then
            case " $* " in
              *" -h "*|*" --help "*|*" --impure "*) exec ${pkgs.nh}/bin/nh "$@" ;;
              *" -- "*) exec ${pkgs.nh}/bin/nh "$@" --impure ;;
              *) exec ${pkgs.nh}/bin/nh "$@" -- --impure ;;
            esac
          fi
          exec ${pkgs.nh}/bin/nh "$@"
        ''} $out/bin/nh
      '';
    };
  };
  nixpkgs.config.allowUnfree = true;

  # Networking & Time
  networking.hostName = hostSpec.hostName;
  networking.networkmanager = {
    enable = true;
    plugins = [
      pkgs.networkmanager-openvpn
      nmOpenvpnSso
    ];
  };
  systemd.services.NetworkManager.restartTriggers = [ nmOpenvpnSso ];
  time.timeZone = "Asia/Ho_Chi_Minh";
  time.hardwareClockInLocalTime = lib.mkDefault false;

  # Hardware (auto-detect Intel VA-API when kvm-intel is present), Audio & Bluetooth
  hardware.graphics = {
    enable = true;
    extraPackages = lib.optionals (builtins.elem "kvm-intel" config.boot.kernelModules) (with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ]);
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
  services.resolved.enable = true;
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

  # Minimal base OS & session packages (user apps live in user-packages.nix)
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
    tailscaleWrapped
    wl-clipboard
    zapretWrapped
  ];

  # Declarative dotfile symlinks
  systemd.user.tmpfiles.rules = [
    "L+ %h/.config/hypr - - - - ${hostSpec.dotfilesDir}/hypr"
    "L+ %h/.config/sway - - - - ${hostSpec.dotfilesDir}/sway"
    "L+ %h/.config/ironbar - - - - ${hostSpec.dotfilesDir}/ironbar"
    "L+ %h/.config/rofi - - - - ${hostSpec.dotfilesDir}/rofi"
    "L+ %h/.config/foot - - - - ${hostSpec.dotfilesDir}/foot"
    "L+ %h/.config/gtk-3.0 - - - - ${hostSpec.dotfilesDir}/gtk-3.0"
    "L+ %h/.config/fcitx5 - - - - ${hostSpec.dotfilesDir}/fcitx5"
    "L+ %h/.config/satty - - - - ${hostSpec.dotfilesDir}/satty"
    "L+ %h/.config/swaync - - - - ${hostSpec.dotfilesDir}/swaync"
    "L+ %h/.config/autostart - - - - ${hostSpec.dotfilesDir}/autostart"
    "L+ %h/.config/systemd - - - - ${hostSpec.dotfilesDir}/systemd"
    "L+ %h/.config/environment.d - - - - ${hostSpec.dotfilesDir}/environment.d"
    "L+ %h/.config/xdg-desktop-portal - - - - ${hostSpec.dotfilesDir}/xdg-desktop-portal"
    "L+ %h/.config/mimeapps.list - - - - ${hostSpec.dotfilesDir}/mimeapps.list"
    "L+ %h/.local/bin/antigravity-launcher.sh - - - - ${hostSpec.dotfilesDir}/bin/antigravity-launcher.sh"
    "L+ %h/.local/bin/restart-antigravity.sh - - - - ${hostSpec.dotfilesDir}/bin/restart-antigravity.sh"
    "L+ %h/.local/bin/screenshot - - - - ${hostSpec.dotfilesDir}/bin/screenshot"
    "L+ %h/.local/bin/ts-rustdesk-forward - - - - ${hostSpec.dotfilesDir}/bin/ts-rustdesk-forward"
    "L+ %h/.local/bin/antigravity - - - - %h/opt/antigravity/antigravity"
    "L+ %h/.local/bin/antigravity-update - - - - %h/dev/workstation/auto_update.py"
    "L+ %h/.local/share/applications/antigravity.desktop - - - - ${hostSpec.dotfilesDir}/applications/antigravity.desktop"
  ];

  # User account matching UID/GID (1000:1000)
  users.groups.${hostSpec.username}.gid = 1000;
  users.users.${hostSpec.username} = {
    isNormalUser = true;
    uid = 1000;
    group = hostSpec.username;
    description = hostSpec.username;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "kvm" "input" ];
  } // (
    if hostSpec.hashedPasswordFile != null then {
      hashedPasswordFile = hostSpec.hashedPasswordFile;
    } else {
      initialPassword = "nixos";
    }
  );
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "26.11";
}
