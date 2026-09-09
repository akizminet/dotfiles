{
  description = "Default user profile for Fedora Sway Atomic";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixgl.url = "github:nix-community/nixGL";
    nixgl.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixgl }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      nixGLIntel = nixgl.packages.${system}.nixGLIntel;
      fcitx5WithAddons = pkgs.kdePackages.fcitx5-with-addons.override {
        addons = [
          pkgs.kdePackages.fcitx5-unikey
          pkgs.kdePackages.fcitx5-configtool
          pkgs.fcitx5-gtk
          pkgs.fcitx5-bamboo
        ];
      };

      googleChromeWrapped = pkgs.symlinkJoin {
        name = "google-chrome-wrapped";
        paths = [ pkgs.google-chrome ];
        buildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          rm -f $out/bin/google-chrome $out/bin/google-chrome-stable
          makeWrapper "${nixGLIntel}/bin/nixGLIntel" "$out/bin/google-chrome-stable" \
            --add-flags "${pkgs.google-chrome}/bin/google-chrome-stable" \
            --add-flags "--ozone-platform=wayland" \
            --add-flags "--enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoDecoder,CanvasOopRasterization" \
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

      flameshotWrapped = pkgs.symlinkJoin {
        name = "flameshot-wrapped";
        paths = [ pkgs.flameshot ];
        buildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          rm -f $out/bin/flameshot
          makeWrapper "${pkgs.flameshot}/bin/flameshot" "$out/bin/flameshot" \
            --set QT_AUTO_SCREEN_SCALE_FACTOR 0 \
            --set QT_SCREEN_SCALE_FACTORS "1;1"
        '';
      };

      hyprlandWrapped = pkgs.symlinkJoin {
        name = "hyprland-wrapped";
        paths = [ pkgs.hyprland ];
        buildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          rm -f $out/bin/Hyprland $out/bin/hyprland $out/bin/start-hyprland
          makeWrapper "${nixGLIntel}/bin/nixGLIntel" "$out/bin/start-hyprland" \
            --add-flags "${pkgs.hyprland}/bin/start-hyprland" \
            --add-flags "--no-nixgl" \
            --add-flags "--path" \
            --add-flags "${pkgs.hyprland}/bin/Hyprland" \
            --prefix __EGL_VENDOR_LIBRARY_DIRS : "${pkgs.mesa}/share/glvnd/egl_vendor.d" \
            --prefix LIBGL_DRIVERS_PATH : "${pkgs.mesa}/lib/dri" \
            --prefix GBM_BACKENDS_PATH : "${pkgs.mesa}/lib/gbm"

          makeWrapper "${nixGLIntel}/bin/nixGLIntel" "$out/bin/Hyprland" \
            --add-flags "${pkgs.hyprland}/bin/start-hyprland" \
            --add-flags "--no-nixgl" \
            --add-flags "--path" \
            --add-flags "${pkgs.hyprland}/bin/Hyprland" \
            --prefix __EGL_VENDOR_LIBRARY_DIRS : "${pkgs.mesa}/share/glvnd/egl_vendor.d" \
            --prefix LIBGL_DRIVERS_PATH : "${pkgs.mesa}/lib/dri" \
            --prefix GBM_BACKENDS_PATH : "${pkgs.mesa}/lib/gbm"
          ln -s $out/bin/Hyprland $out/bin/hyprland
        '';
      };

      hyprpaperWrapped = pkgs.symlinkJoin {
        name = "hyprpaper-wrapped";
        paths = [ pkgs.hyprpaper ];
        buildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          rm -f $out/bin/hyprpaper
          makeWrapper "${nixGLIntel}/bin/nixGLIntel" "$out/bin/hyprpaper" \
            --add-flags "${pkgs.hyprpaper}/bin/hyprpaper" \
            --prefix __EGL_VENDOR_LIBRARY_DIRS : "${pkgs.mesa}/share/glvnd/egl_vendor.d" \
            --prefix LIBGL_DRIVERS_PATH : "${pkgs.mesa}/lib/dri" \
            --prefix GBM_BACKENDS_PATH : "${pkgs.mesa}/lib/gbm"
        '';
      };

      hyprlockWrapped = pkgs.symlinkJoin {
        name = "hyprlock-wrapped";
        paths = [ pkgs.hyprlock ];
        buildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          rm -f $out/bin/hyprlock
          makeWrapper "${nixGLIntel}/bin/nixGLIntel" "$out/bin/hyprlock" \
            --add-flags "${pkgs.hyprlock}/bin/hyprlock" \
            --prefix __EGL_VENDOR_LIBRARY_DIRS : "${pkgs.mesa}/share/glvnd/egl_vendor.d" \
            --prefix LIBGL_DRIVERS_PATH : "${pkgs.mesa}/lib/dri" \
            --prefix GBM_BACKENDS_PATH : "${pkgs.mesa}/lib/gbm"
        '';
      };
    in
    {
      packages.${system} = {
        default = pkgs.buildEnv {
          name = "default-profile";
          paths = [
            # Desktop Environment & Wayland Compositors
            hyprlandWrapped
            pkgs.hyprland-qtutils
            hyprpaperWrapped
            pkgs.hypridle
            hyprlockWrapped
            pkgs.xdg-desktop-portal-hyprland
            pkgs.sway
            pkgs.waybar
            pkgs.rofi
            pkgs.foot
            pkgs.wl-clipboard
            pkgs.mako
            pkgs.libnotify

            # GUI & Desktop Applications
            googleChromeWrapped
            pkgs.libreoffice
            flameshotWrapped

            # CLI & Network Tools
            pkgs.ffmpeg-full
            pkgs.gh
            pkgs.google-cloud-sdk
            tailscaleWrapped
            pkgs.wayvnc
            pkgs.zapret

            # Input Method & Addons
            fcitx5WithAddons

            # Fonts
            pkgs.nerd-fonts.monaspace

            # GPU wrapper
            nixGLIntel
          ];
        };

        fcitx5 = fcitx5WithAddons;
        fcitx5-with-addons = fcitx5WithAddons;
      };
    };
}
