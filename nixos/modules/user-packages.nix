{ pkgs, celluloid-src, hostSpec, ... }:

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
    paths = [ pkgs.firefox-bin ];
    buildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      rm -f $out/bin/firefox
      makeWrapper "${pkgs.firefox-bin}/bin/firefox" "$out/bin/firefox" \
        --set-default MOZ_ENABLE_WAYLAND 1 \
        --set-default RES_OPTIONS "ndots:0"

      rm -f $out/share/applications/firefox.desktop
      mkdir -p $out/share/applications
      sed "s|Exec=firefox|Exec=$out/bin/firefox|g" \
        ${pkgs.firefox-bin}/share/applications/firefox.desktop > $out/share/applications/firefox.desktop
    '';
  };

  rustdeskWrapped = pkgs.symlinkJoin {
    name = "rustdesk-wrapped";
    paths = [ pkgs.rustdesk ];
    buildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      rm -f $out/bin/rustdesk
      makeWrapper "${pkgs.rustdesk}/bin/rustdesk" "$out/bin/rustdesk" \
        --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${pkgs.pipewire}/lib/gstreamer-1.0"

      rm -f $out/share/applications/rustdesk.desktop
      mkdir -p $out/share/applications
      sed "s|Exec=rustdesk|Exec=$out/bin/rustdesk|g" \
        ${pkgs.rustdesk}/share/applications/rustdesk.desktop > $out/share/applications/rustdesk.desktop
    '';
  };

  celluloidCustom = pkgs.celluloid.overrideAttrs (old: {
    src = celluloid-src;
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.ffmpeg ];
    doCheck = false;
  });
in
{
  users.users.${hostSpec.username}.packages = with pkgs; [
    # GUI & Desktop Applications
    googleChromeWrapped
    firefoxWrapped
    celluloidCustom
    libreoffice
    rustdeskWrapped
    nautilus
    file-roller
    telegram-desktop
    qbittorrent
    dbeaver-bin
    foliate
    resources
    loupe
    papers

    # CLI & Dev Tools
    binutils
    corepack
    ffmpeg-full
    gh
    google-cloud-sdk
    inetutils
    kubernetes-helm
    kubectl
    nodejs_26
    ripgrep
    wayvnc
  ];
}
