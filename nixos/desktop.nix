{ pkgs, celluloid-src, akquick, ... }:

let
  googleChromeWrapped = pkgs.symlinkJoin {
    name = "google-chrome-wrapped";
    paths = [ pkgs.google-chrome ];
    buildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      rm -f $out/bin/google-chrome $out/bin/google-chrome-stable
      makeWrapper "${pkgs.google-chrome}/bin/google-chrome-stable" "$out/bin/google-chrome-stable" \
        --add-flags "--ozone-platform=wayland" \
        --add-flags "--enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoDecoder,CanvasOopRasterization,WebRTCPipeWireCapturer" \
        --add-flags "--disable-features=Vulkan,VulkanFromANGLE,DefaultANGLEVulkan" \
        --add-flags "--ignore-gpu-blocklist" \
        --add-flags "--enable-gpu-rasterization" \
        --add-flags "--enable-zero-copy"
      ln -s $out/bin/google-chrome-stable $out/bin/google-chrome

      rm -f $out/share/applications/google-chrome.desktop
      mkdir -p $out/share/applications
      sed "s|Exec=${pkgs.google-chrome}/bin/google-chrome-stable|Exec=$out/bin/google-chrome-stable|g" \
        ${pkgs.google-chrome}/share/applications/google-chrome.desktop > $out/share/applications/google-chrome.desktop
    '';
  };

  firefoxWrapped = pkgs.symlinkJoin {
    name = "firefox-wrapped";
    paths = [ pkgs.firefox ];
    buildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      rm -f $out/bin/firefox
      makeWrapper "${pkgs.firefox}/bin/firefox" "$out/bin/firefox" \
        --set-default MOZ_ENABLE_WAYLAND 1 \
        --set-default RES_OPTIONS "ndots:0"

      rm -f $out/share/applications/firefox.desktop
      mkdir -p $out/share/applications
      sed "s|Exec=firefox|Exec=$out/bin/firefox|g" \
        ${pkgs.firefox}/share/applications/firefox.desktop > $out/share/applications/firefox.desktop
    '';
  };

  celluloidCustom = pkgs.celluloid.overrideAttrs (old: {
    src = celluloid-src;
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.ffmpeg ];
    doCheck = false;
  });

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
  # Wayland Compositors & Lock Screen (with PAM)
  programs.hyprland.enable = true;
  programs.hyprlock.enable = true;
  programs.sway.enable = true;
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Locale & Input Method (Fcitx5 Vietnamese)
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

  # Fonts
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

  # User & Desktop Applications
  environment.systemPackages = with pkgs; [
    # Wayland & Desktop Utilities
    hyprland-guiutils
    hyprpaper
    hypridle
    ironbar
    rofi
    foot
    wl-clipboard
    swaynotificationcenter
    libnotify
    polkit_gnome
    adwaita-icon-theme
    git

    # GUI & Desktop Applications
    googleChromeWrapped
    firefoxWrapped
    celluloidCustom
    libreoffice
    satty
    rustdesk
    grim
    slurp
    nautilus
    file-roller
    akquick.packages.${pkgs.stdenv.hostPlatform.system}.default
    telegram-desktop
    qbittorrent
    dbeaver-bin
    foliate
    resources
    loupe
    papers

    # CLI & Network Tools
    binutils
    corepack
    ffmpeg-full
    gh
    google-cloud-sdk
    inetutils
    kubernetes-helm
    kubectl
    nodejs_26
    openvpn
    python3
    ripgrep
    wayvnc
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
}
