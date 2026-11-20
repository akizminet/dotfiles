{ config, lib, pkgs, hostSpec, ... }:

let
  homeDir = "/home/${hostSpec.username}";
  wallpapersDir = ../configs/sway/wallpapers;
  rofiDir = ../configs/rofi;

  hyprlockConf = pkgs.replaceVars ../configs/hypr/hyprlock.conf {
    inherit homeDir;
  };

  hyprpaperConf = pkgs.replaceVars ../configs/hypr/hyprpaper.conf {
    inherit wallpapersDir;
  };

  mkSubstBin = name: src: replacements:
    pkgs.replaceVarsWith {
      inherit name src replacements;
      dir = "bin";
      isExecutable = true;
      buildInputs = [ pkgs.bash ];
    };

  wallpaperSwitcher = mkSubstBin "wallpaper-switcher" ../scripts/wallpaper-switcher.sh {
    inherit wallpapersDir;
  };

  swayLock = mkSubstBin "sway-lock" ../scripts/sway-lock.sh {
    inherit wallpapersDir;
  };

  swayIdle = pkgs.writeShellScriptBin "sway-idle"
    (builtins.readFile ../scripts/sway-idle.sh);

  powermenu = mkSubstBin "powermenu" ../scripts/powermenu.sh {
    rofiTheme = "${rofiDir}/catppuccin-mocha.rasi";
  };

  screenshotScript = pkgs.writeShellScriptBin "screenshot"
    (builtins.readFile ../scripts/screenshot);

  tsRustdeskForward = pkgs.runCommandLocal "ts-rustdesk-forward" { } ''
    mkdir -p $out/bin
    sed "1s|^#!.*|#!${pkgs.python3}/bin/python3|" ${../scripts/ts-rustdesk-forward} > $out/bin/ts-rustdesk-forward
    chmod 0755 $out/bin/ts-rustdesk-forward
  '';

  gtkBookmarks = pkgs.writeText "gtk-bookmarks" ''
    file://${homeDir}/Documents
    file://${homeDir}/Music
    file://${homeDir}/Pictures
    file://${homeDir}/Videos
    file://${homeDir}/Downloads
  '';
in
{
  environment.systemPackages = [
    wallpaperSwitcher
    swayLock
    swayIdle
    powermenu
    screenshotScript
    tsRustdeskForward
  ];

  # Desktop portal configuration per compositor (Hyprland uses xdg-desktop-portal-hyprland;
  # Sway keeps nixpkgs default sway-portals.conf using wlr/gtk).
  xdg.portal.config.hyprland = {
    default = [ "hyprland" "gtk" ];
    "org.freedesktop.impl.portal.ScreenCast" = "hyprland";
    "org.freedesktop.impl.portal.Screenshot" = "hyprland";
    "org.freedesktop.impl.portal.FileChooser" = "gtk";
  };

  # System-wide XDG MIME associations (/etc/xdg/mimeapps.list)
  xdg.mime = {
    enable = true;
    defaultApplications = {
      "text/html" = "google-chrome.desktop";
      "x-scheme-handler/http" = "google-chrome.desktop";
      "x-scheme-handler/https" = "google-chrome.desktop";
      "x-scheme-handler/about" = "google-chrome.desktop";
      "x-scheme-handler/unknown" = "google-chrome.desktop";
      "application/xhtml+xml" = "google-chrome.desktop";
      "x-scheme-handler/lmstudio" = "LM-Studio.desktop";
      "x-scheme-handler/antigravity" = "antigravity.desktop";
      "x-scheme-handler/antigravity-ide" = "antigravity-ide.desktop";
      "application/json" = "dev.zed.Zed.desktop";
      "application/pdf" = "org.gnome.Papers.desktop";
      "x-scheme-handler/jetbrains" = "jetbrainsd.desktop";
      "inode/directory" = "org.gnome.Nautilus.desktop";
      "video/x-matroska" = "io.github.celluloid_player.Celluloid.desktop";
      "application/zip" = "org.gnome.FileRoller.desktop";
      "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
      "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
      "x-scheme-handler/ton" = "org.telegram.desktop.desktop";
    };
    addedAssociations = {
      "x-scheme-handler/http" = [ "google-chrome.desktop" "com.google.Chrome.desktop" "firefox.desktop" ];
      "application/xhtml+xml" = [ "google-chrome.desktop" "com.google.Chrome.desktop" "firefox.desktop" ];
      "text/html" = [ "google-chrome.desktop" "com.google.Chrome.desktop" "firefox.desktop" ];
      "x-scheme-handler/https" = [ "google-chrome.desktop" "com.google.Chrome.desktop" "firefox.desktop" ];
      "application/vnd.comicbook-rar" = "org.gnome.Papers.desktop";
      "application/vnd.comicbook+zip" = "org.gnome.Papers.desktop";
      "application/x-cb7" = "org.gnome.Papers.desktop";
      "application/x-cbt" = "org.gnome.Papers.desktop";
      "application/x-ext-cb7" = "org.gnome.Papers.desktop";
      "application/x-ext-cbr" = "org.gnome.Papers.desktop";
      "application/x-ext-cbt" = "org.gnome.Papers.desktop";
      "application/x-ext-cbz" = "org.gnome.Papers.desktop";
      "application/x-ext-djv" = "org.gnome.Papers.desktop";
      "application/x-ext-djvu" = "org.gnome.Papers.desktop";
      "image/vnd.djvu" = "org.gnome.Papers.desktop";
      "image/vnd.djvu+multipage" = "org.gnome.Papers.desktop";
      "application/pdf" = "org.gnome.Papers.desktop";
      "application/x-bzpdf" = "org.gnome.Papers.desktop";
      "application/x-ext-pdf" = "org.gnome.Papers.desktop";
      "application/x-gzpdf" = "org.gnome.Papers.desktop";
      "application/x-xzpdf" = "org.gnome.Papers.desktop";
      "application/illustrator" = "org.gnome.Papers.desktop";
      "image/tiff" = "org.gnome.Papers.desktop";
      "application/json" = "dev.zed.Zed.desktop";
      "inode/directory" = "org.gnome.Nautilus.desktop";
      "video/x-matroska" = [ "userapp-celluloid-A6TUW3.desktop" "io.github.celluloid_player.Celluloid.desktop" ];
      "application/zip" = "org.gnome.FileRoller.desktop";
      "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
      "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
      "x-scheme-handler/ton" = "org.telegram.desktop.desktop";
    };
  };

  # Store-backed declarative dotfile symlinks (read-only static dirs, writable dirs for mutable state)
  systemd.user.tmpfiles.rules = [
    "L+ %h/.config/sway - - - - ${../configs/sway}"
    "L+ %h/.config/ironbar - - - - ${../configs/ironbar}"
    "L+ %h/.config/rofi - - - - ${rofiDir}"
    "L+ %h/.config/foot - - - - ${../configs/foot}"
    "L+ %h/.config/satty - - - - ${../configs/satty}"
    "L+ %h/.config/swaync - - - - ${../configs/swaync}"

    # Keep ~/.config/hypr writable so machine-local xdph.conf can coexist with store-managed files
    "d %h/.config/hypr 0755 - - -"
    "L+ %h/.config/hypr/hyprland.lua - - - - ${../configs/hypr/hyprland.lua}"
    "L+ %h/.config/hypr/hypridle.conf - - - - ${../configs/hypr/hypridle.conf}"
    "L+ %h/.config/hypr/hyprlock.conf - - - - ${hyprlockConf}"
    "L+ %h/.config/hypr/hyprpaper.conf - - - - ${hyprpaperConf}"
    "L+ %h/.config/hypr/hypr_shortcuts.md - - - - ${../configs/hypr/hypr_shortcuts.md}"

    # Keep ~/.config/fcitx5 writable so fcitx5 can write conf/cached_layouts at runtime
    "d %h/.config/fcitx5 0755 - - -"
    "d %h/.config/fcitx5/conf 0755 - - -"
    "L+ %h/.config/fcitx5/config - - - - ${../configs/fcitx5/config}"
    "L+ %h/.config/fcitx5/profile - - - - ${../configs/fcitx5/profile}"
    "L+ %h/.config/fcitx5/conf/notifications.conf - - - - ${../configs/fcitx5/conf/notifications.conf}"

    # Seed GTK3 bookmarks if missing while keeping the file writable for Nautilus
    "d %h/.config/gtk-3.0 0755 - - -"
    "C %h/.config/gtk-3.0/bookmarks 0644 - - - ${gtkBookmarks}"

    # Initial fallback symlink for lockscreens before wallpaper-switcher runs
    "d %h/.cache 0755 - - -"
    "L %h/.cache/current-wallpaper.jpg - - - - ${wallpapersDir}/ghibli-starship-launch-day.jpg"
  ];

  # One-time, idempotent migration from legacy ~/dev/dotfiles symlinks to store-backed dirs
  system.userActivationScripts.migrateLegacyDotfiles = ''
    need_tmpfiles=0
    need_daemon_reload=0

    # 1. Migrate ~/.config/systemd symlink -> real writable dir, preserving machine-local units (e.g. mewsic-bot.service)
    if [ -L "$HOME/.config/systemd" ]; then
      target="$(readlink "$HOME/.config/systemd" || true)"
      case "$target" in
        */dotfiles/systemd|*/dotfiles/systemd/)
          tmp_systemd="$(mktemp -d)"
          if [ -d "$HOME/.config/systemd/user" ]; then
            mkdir -p "$tmp_systemd/user"
            for item in "$HOME/.config/systemd/user"/*; do
              [ -e "$item" ] || [ -L "$item" ] || continue
              base="$(basename "$item")"
              case "$base" in
                hyprland-session.target|nm-openvpn-sso-user-agent.service|polkit-gnome.service|sway-wallpaper-switcher.service|sway-wallpaper-switcher.timer|tailscaled.service|ts-rustdesk.service|default.target.wants|graphical-session.target.wants)
                  ;;
                *)
                  cp -a "$item" "$tmp_systemd/user/"
                  ;;
              esac
            done
            for wants_dir in default.target.wants graphical-session.target.wants; do
              if [ -d "$HOME/.config/systemd/user/$wants_dir" ]; then
                for want in "$HOME/.config/systemd/user/$wants_dir"/*; do
                  [ -e "$want" ] || [ -L "$want" ] || continue
                  wbase="$(basename "$want")"
                  case "$wbase" in
                    nm-openvpn-sso-user-agent.service|polkit-gnome.service|sway-wallpaper-switcher.timer|tailscaled.service|ts-rustdesk.service)
                      ;;
                    *)
                      mkdir -p "$tmp_systemd/user/$wants_dir"
                      cp -a "$want" "$tmp_systemd/user/$wants_dir/"
                      ;;
                  esac
                done
              fi
            done
          fi
          rm -f "$HOME/.config/systemd"
          mkdir -p "$HOME/.config/systemd/user"
          if [ -n "$(ls -A "$tmp_systemd/user" 2>/dev/null || true)" ]; then
            cp -a "$tmp_systemd/user/." "$HOME/.config/systemd/user/"
          fi
          rm -rf "$tmp_systemd"
          need_daemon_reload=1
          ;;
      esac
    fi

    # 2. Migrate ~/.config/hypr symlink -> real dir, preserving local xdph.conf or custom files
    if [ -L "$HOME/.config/hypr" ]; then
      target="$(readlink "$HOME/.config/hypr" || true)"
      case "$target" in
        */dotfiles/hypr|*/dotfiles/hypr/)
          tmp_hypr="$(mktemp -d)"
          for item in "$HOME/.config/hypr"/*; do
            [ -e "$item" ] || [ -L "$item" ] || continue
            base="$(basename "$item")"
            case "$base" in
              hyprland.lua|hypridle.conf|hyprlock.conf|hyprpaper.conf|hypr_shortcuts.md)
                ;;
              *)
                cp -a "$item" "$tmp_hypr/"
                ;;
            esac
          done
          rm -f "$HOME/.config/hypr"
          mkdir -p "$HOME/.config/hypr"
          if [ -n "$(ls -A "$tmp_hypr" 2>/dev/null || true)" ]; then
            cp -a "$tmp_hypr/." "$HOME/.config/hypr/"
          fi
          rm -rf "$tmp_hypr"
          need_tmpfiles=1
          ;;
      esac
    fi

    # 3. Migrate ~/.config/fcitx5 symlink -> real dir, keeping conf/cached_layouts
    if [ -L "$HOME/.config/fcitx5" ]; then
      target="$(readlink "$HOME/.config/fcitx5" || true)"
      case "$target" in
        */dotfiles/fcitx5|*/dotfiles/fcitx5/)
          tmp_fcitx="$(mktemp -d)"
          if [ -f "$HOME/.config/fcitx5/conf/cached_layouts" ]; then
            mkdir -p "$tmp_fcitx/conf"
            cp -a "$HOME/.config/fcitx5/conf/cached_layouts" "$tmp_fcitx/conf/"
          fi
          rm -f "$HOME/.config/fcitx5"
          mkdir -p "$HOME/.config/fcitx5/conf"
          if [ -d "$tmp_fcitx/conf" ]; then
            cp -a "$tmp_fcitx/conf/." "$HOME/.config/fcitx5/conf/"
          fi
          rm -rf "$tmp_fcitx"
          need_tmpfiles=1
          ;;
      esac
    fi

    # 4. Migrate ~/.config/gtk-3.0 symlink -> real dir for writable bookmarks
    if [ -L "$HOME/.config/gtk-3.0" ]; then
      target="$(readlink "$HOME/.config/gtk-3.0" || true)"
      case "$target" in
        */dotfiles/gtk-3.0|*/dotfiles/gtk-3.0/)
          rm -f "$HOME/.config/gtk-3.0"
          mkdir -p "$HOME/.config/gtk-3.0"
          need_tmpfiles=1
          ;;
      esac
    fi

    # 5. Clean up obsolete symlinks pointing into ~/dev/dotfiles
    for legacy_link in \
      "$HOME/.config/xdg-desktop-portal" \
      "$HOME/.config/autostart" \
      "$HOME/.config/mimeapps.list" \
      "$HOME/.config/environment.d" \
      "$HOME/.local/share/applications/antigravity.desktop" \
      "$HOME/.local/bin/antigravity-launcher.sh" \
      "$HOME/.local/bin/restart-antigravity.sh" \
      "$HOME/.local/bin/screenshot" \
      "$HOME/.local/bin/ts-rustdesk-forward"; do
      if [ -L "$legacy_link" ]; then
        target="$(readlink "$legacy_link" || true)"
        case "$target" in
          */dotfiles/*)
            rm -f "$legacy_link"
            ;;
        esac
      fi
    done

    if [ "$need_tmpfiles" -eq 1 ]; then
      ${config.systemd.package}/bin/systemd-tmpfiles --user --create --remove
    fi

    if [ "$need_daemon_reload" -eq 1 ]; then
      ${config.systemd.package}/bin/systemctl --user daemon-reload || true
    fi
  '';
}
