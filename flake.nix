{
  description = "NixOS Base OS + User Profile Flake for homepc";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    celluloid-src = {
      url = "git+ssh://git@github.com/akizminet/akcelluloid.git";
      flake = false;
    };
    akquick.url = "github:akizminet/akquick";
    akquick.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, celluloid-src, akquick }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          (final: prev: { pcre = prev.pcre2; })
        ];
      };

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
    in
    {
      # Layer 1: Base OS (managed with: nh os switch)
      nixosConfigurations = {
        homepc = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit self celluloid-src akquick; };
          modules = [
            { nixpkgs.overlays = [ (final: prev: { pcre = prev.pcre2; }) ]; }
            ./nixos/configuration.nix
          ];
        };
        workstation = self.nixosConfigurations.homepc;
      };

      # Layer 2: User Apps & CLI Dev Tools (managed with: nix profile add/upgrade)
      packages.${system} = {
        default = pkgs.buildEnv {
          name = "default-profile";
          paths = [
            # GUI & Desktop Applications
            googleChromeWrapped
            firefoxWrapped
            celluloidCustom
            pkgs.libreoffice
            pkgs.rustdesk
            pkgs.nautilus
            pkgs.file-roller
            pkgs.telegram-desktop
            pkgs.qbittorrent
            pkgs.dbeaver-bin
            pkgs.foliate
            pkgs.resources
            pkgs.loupe
            pkgs.papers

            # CLI & Dev Tools
            pkgs.binutils
            pkgs.corepack
            pkgs.ffmpeg-full
            pkgs.gh
            pkgs.google-cloud-sdk
            pkgs.inetutils
            pkgs.kubernetes-helm
            pkgs.kubectl
            pkgs.nodejs_26
            pkgs.ripgrep
            pkgs.wayvnc
          ];
        };

        google-chrome = googleChromeWrapped;
        firefox = firefoxWrapped;
        celluloid = celluloidCustom;
        libreoffice = pkgs.libreoffice;
        rustdesk = pkgs.rustdesk;
        nautilus = pkgs.nautilus;
        helm = pkgs.kubernetes-helm;
        kubectl = pkgs.kubectl;
        nodejs = pkgs.nodejs_26;
        corepack = pkgs.corepack;
      };
    };
}
