{ lib, pkgs, hostSpec, ... }:

let
  # Declarative list of enabled external self-updating apps.
  # Add an app ID here to track/install it via `external-apps sync`;
  # remove an app ID here and run `nh os switch && external-apps sync` to uninstall it.
  enabledApps = [
    "antigravity"
    "agy"
    "zed"
    "idea"
  ];

  homeDir = "/home/${hostSpec.username}";

  antigravity = pkgs.writeShellScriptBin "antigravity" ''
    TARGET="$HOME/opt/antigravity/antigravity"
    if [ -x "$TARGET" ]; then
      exec "$TARGET" "$@"
    fi
    echo "antigravity not found at $TARGET. Run 'external-apps install antigravity' or 'antigravity-update'." >&2
    exit 1
  '';

  antigravityLauncher = pkgs.writeShellScriptBin "antigravity-launcher" ''
    if command -v swaymsg >/dev/null 2>&1 && [ -n "''${WAYLAND_DISPLAY:-}" ]; then
      if swaymsg '[app_id="(?i)^antigravity$"] focus' >/dev/null 2>&1 || \
         swaymsg '[class="(?i)^antigravity$"] focus' >/dev/null 2>&1; then
        exit 0
      fi
    fi

    TARGET="$HOME/opt/antigravity/antigravity"
    if [ -x "$TARGET" ]; then
      exec "$TARGET" "$@"
    elif [ -x "/opt/antigravity/antigravity" ]; then
      exec "/opt/antigravity/antigravity" "$@"
    fi
    echo "antigravity not found at $TARGET. Run 'external-apps install antigravity' or 'antigravity-update'." >&2
    exit 1
  '';

  antigravityRestart = pkgs.writeShellScriptBin "restart-antigravity"
    (builtins.readFile ../../bin/restart-antigravity.sh);

  antigravityUpdate = pkgs.writeShellScriptBin "antigravity-update" ''
    exec ${pkgs.python3}/bin/python3 ${../../scripts/update-antigravity.py} "$@"
  '';

  antigravityCompatAliases = pkgs.runCommand "antigravity-compat-aliases" {
    preferLocalBuild = true;
    allowSubstitutes = false;
  } ''
    mkdir -p $out/bin
    ln -s ${antigravityLauncher}/bin/antigravity-launcher $out/bin/antigravity-launcher.sh
    ln -s ${antigravityRestart}/bin/restart-antigravity $out/bin/restart-antigravity.sh
  '';

  antigravityDesktop = pkgs.makeDesktopItem {
    name = "antigravity";
    desktopName = "Antigravity";
    comment = "Experience liftoff - Agentic Platform";
    exec = "antigravity-launcher %U";
    icon = "${homeDir}/.local/share/pixmaps/antigravity.png";
    terminal = false;
    categories = [ "Development" "Utility" ];
    startupNotify = true;
    startupWMClass = "Antigravity";
    singleMainWindow = true;
    noDisplay = false;
  };

  agy = pkgs.writeShellScriptBin "agy" ''
    TARGET="$HOME/.local/bin/agy"
    if [ -x "$TARGET" ]; then
      exec "$TARGET" "$@"
    fi
    echo "agy not found at $TARGET. Run 'external-apps install agy' to install it." >&2
    exit 1
  '';

  zed = pkgs.writeShellScriptBin "zed" ''
    TARGET="$HOME/.local/zed.app/bin/zed"
    if [ -x "$TARGET" ]; then
      exec "$TARGET" "$@"
    fi
    echo "zed not found at $TARGET. Run 'external-apps install zed' to install it." >&2
    exit 1
  '';

  zedDesktop = pkgs.makeDesktopItem {
    name = "dev.zed.Zed";
    desktopName = "Zed";
    genericName = "Text Editor";
    comment = "A high-performance, multiplayer code editor.";
    exec = "zed %U";
    tryExec = "${homeDir}/.local/zed.app/bin/zed";
    icon = "${homeDir}/.local/zed.app/share/icons/hicolor/512x512/apps/zed.png";
    categories = [ "Utility" "TextEditor" "Development" "IDE" ];
    keywords = [ "zed" ];
    mimeTypes = [ "text/plain" "application/x-zerosize" "x-scheme-handler/zed" ];
    startupNotify = true;
    actions.NewWorkspace = {
      name = "Open a new workspace";
      exec = "zed --new %U";
    };
  };

  idea = pkgs.writeShellScriptBin "idea" ''
    TARGET="$HOME/opt/idea/iu/bin/idea"
    if [ -x "$TARGET" ]; then
      exec "$TARGET" "$@"
    fi
    echo "IntelliJ IDEA not found at $TARGET. Run 'external-apps install idea' to install it." >&2
    exit 1
  '';

  ideaDesktop = pkgs.makeDesktopItem {
    name = "jetbrains-idea";
    desktopName = "IntelliJ IDEA";
    comment = "The Leading IDE for Professional Development in Java and Kotlin";
    exec = "idea %f";
    tryExec = "${homeDir}/opt/idea/iu/bin/idea";
    icon = "${homeDir}/opt/idea/iu/bin/idea.svg";
    categories = [ "Development" "IDE" ];
    terminal = false;
    startupWMClass = "jetbrains-idea";
    startupNotify = true;
  };

  catalog = {
    antigravity = {
      binary = "opt/antigravity/antigravity";
      location = "~/opt/antigravity";
      updater_label = "antigravity-update";
      installer = {
        type = "command";
        argv = [ "${antigravityUpdate}/bin/antigravity-update" ];
      };
      updater = {
        type = "command";
        argv = [ "${antigravityUpdate}/bin/antigravity-update" ];
      };
      remove_paths = [
        "opt/antigravity"
        "opt/antigravity.old"
      ];
      purge_paths = [
        ".config/Antigravity"
        ".cache/Antigravity"
      ];
      packages = [
        antigravity
        antigravityLauncher
        antigravityRestart
        antigravityUpdate
        antigravityCompatAliases
        antigravityDesktop
      ];
    };

    agy = {
      binary = ".local/bin/agy";
      location = "~/.local/bin/agy";
      updater_label = "agy update";
      installer = {
        type = "shell";
        command = "curl -fsSL https://antigravity.google/cli/install.sh | bash";
      };
      updater = {
        type = "command";
        argv = [ "${agy}/bin/agy" "update" ];
      };
      remove_paths = [
        ".local/bin/agy"
      ];
      purge_paths = [
        ".gemini/antigravity-cli"
      ];
      packages = [
        agy
      ];
    };

    zed = {
      binary = ".local/zed.app/bin/zed";
      location = "~/.local/zed.app";
      updater_label = "self-update on startup";
      installer = {
        type = "shell";
        command = "curl -f https://zed.dev/install.sh | sh";
      };
      updater = {
        type = "shell";
        command = "curl -f https://zed.dev/install.sh | sh";
      };
      remove_paths = [
        ".local/zed.app"
        ".local/bin/zed"
        ".local/share/applications/dev.zed.Zed.desktop"
      ];
      purge_paths = [
        ".config/zed"
        ".local/share/zed"
        ".cache/zed"
      ];
      packages = [
        zed
        zedDesktop
      ];
    };

    idea = {
      binary = "opt/idea/iu/bin/idea";
      location = "~/opt/idea/iu";
      updater_label = "in-app / JetBrains API";
      installer = {
        type = "jetbrains";
        product_code = "IIU";
        install_dir = "opt/idea/iu";
      };
      updater = {
        type = "jetbrains";
        product_code = "IIU";
        install_dir = "opt/idea/iu";
      };
      remove_paths = [
        "opt/idea"
        ".local/share/applications/jetbrains-idea.desktop"
      ];
      purge_paths = [
        ".config/JetBrains"
        ".local/share/JetBrains"
        ".cache/JetBrains"
      ];
      packages = [
        idea
        ideaDesktop
      ];
    };
  };

  manifestJson = pkgs.writeText "external-apps-manifest.json" (builtins.toJSON {
    enabled = enabledApps;
    catalog = lib.mapAttrs (_: app: builtins.removeAttrs app [ "packages" ]) catalog;
  });

  externalAppsCli = pkgs.writeShellScriptBin "external-apps" ''
    export PATH="${lib.makeBinPath [
      pkgs.curl
      pkgs.bash
      pkgs.coreutils
      pkgs.gnutar
      pkgs.gzip
      pkgs.xz
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
    ]}:$PATH"
    exec ${pkgs.python3}/bin/python3 ${../../scripts/external-apps.py} --manifest ${manifestJson} "$@"
  '';

  appsStatus = pkgs.writeShellScriptBin "apps-status" ''
    exec ${externalAppsCli}/bin/external-apps status "$@"
  '';
in
{
  # Registry tracking official self-updating external installations in place
  # with install/update/sync/remove orchestration via `external-apps`.
  users.users.${hostSpec.username}.packages =
    [ externalAppsCli appsStatus ]
    ++ lib.concatMap (id: catalog.${id}.packages) enabledApps;
}
